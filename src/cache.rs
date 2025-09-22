use anyhow::{Result, Context};
use crate::models::{Feed, FeedItem};
use chrono::{Utc, DateTime};
use std::fs;
use std::path::{Path, PathBuf};
use serde_json;

/// Text-based cache for RSS articles and feeds
/// Stores articles as markdown files with YAML frontmatter
pub struct TextCache {
    base_dir: PathBuf,
    articles_dir: PathBuf,
}

impl TextCache {
    /// Creates a new TextCache instance
    /// Initializes the data directory structure if it doesn't exist
    pub fn new() -> Result<Self> {
        // Check if running from Neovim and use its data directory
        let base_dir = if let Ok(nvim_data) = std::env::var("NAVIREADER_DATA_DIR") {
            // If Neovim sets this env var, use it
            PathBuf::from(nvim_data)
        } else {
            // Otherwise use XDG data directory standard
            if let Ok(xdg_data) = std::env::var("XDG_DATA_HOME") {
                PathBuf::from(xdg_data).join("navireader")
            } else {
                // Fallback to ~/.local/share/navireader (XDG default)
                let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
                PathBuf::from(home).join(".local/share/navireader")
            }
        };

        fs::create_dir_all(&base_dir)?;
        let articles_dir = base_dir.join("articles");
        fs::create_dir_all(&articles_dir)?;
        fs::create_dir_all(base_dir.join("feeds"))?;
        fs::create_dir_all(base_dir.join("state"))?;

        Ok(Self { base_dir, articles_dir })
    }

    /// Stores a feed's articles to disk
    /// Each article is saved as a separate markdown file
    pub fn store_feed(&self, feed: &Feed) -> Result<()> {
        for item in &feed.items {
            self.store_article(item)?;
        }

        let feed_meta_path = self.base_dir
            .join("feeds")
            .join(format!("{}.json", sanitize_filename(&feed.url)));

        let meta = serde_json::json!({
            "url": feed.url,
            "title": feed.title,
            "description": feed.description,
            "last_fetched": Utc::now(),
        });

        fs::write(feed_meta_path, serde_json::to_string_pretty(&meta)?)?;

        Ok(())
    }

    fn store_article(&self, item: &FeedItem) -> Result<()> {
        let filename = format!(
            "{}-{}.md",
            item.published
                .unwrap_or_else(|| Utc::now())
                .format("%Y%m%d-%H%M%S"),
            sanitize_filename(&item.id)
        );

        let filepath = self.base_dir.join("articles").join(filename);

        if filepath.exists() {
            return Ok(());
        }

        let content = format!(
            r#"---
id: {}
feed: {}
title: {}
link: {}
author: {}
date: {}
read: false
starred: false
---

# {}

{}

{}

[Read original]({})
"#,
            item.id,
            item.feed_url,
            item.title.replace('\n', " "),
            item.link,
            item.author.as_deref().unwrap_or(""),
            item.published
                .map(|d| d.to_rfc3339())
                .unwrap_or_else(|| Utc::now().to_rfc3339()),
            item.title,
            item.description.as_deref().unwrap_or(""),
            item.content.as_deref().unwrap_or(""),
            item.link
        );

        fs::write(filepath, content)?;
        Ok(())
    }

    /// Retrieves articles from disk, sorted by modification time
    /// Returns up to `limit` articles if specified
    pub fn get_articles(&self, limit: Option<usize>) -> Result<Vec<FeedItem>> {
        let mut articles = Vec::new();
        let articles_dir = self.base_dir.join("articles");

        let mut entries: Vec<_> = fs::read_dir(&articles_dir)?
            .filter_map(|e| e.ok())
            .filter(|e| {
                e.path()
                    .extension()
                    .map_or(false, |ext| ext == "md")
            })
            .collect();

        entries.sort_by_key(|e| {
            e.metadata()
                .and_then(|m| m.modified())
                .unwrap_or_else(|_| std::time::SystemTime::now())
        });
        entries.reverse();

        let limit = limit.unwrap_or(entries.len());

        for entry in entries.into_iter().take(limit) {
            if let Ok(item) = self.parse_article_file(&entry.path()) {
                articles.push(item);
            }
        }

        Ok(articles)
    }

    /// Get a single article by ID with O(1) lookup
    pub fn get_article_by_id(&self, article_id: &str) -> Result<Option<FeedItem>> {
        let article_path = self.articles_dir.join(format!("{}.md", article_id));
        if !article_path.exists() {
            return Ok(None);
        }
        self.parse_article_file(&article_path).map(Some)
    }

    fn parse_article_file(&self, path: &Path) -> Result<FeedItem> {
        let content = fs::read_to_string(path)
            .with_context(|| format!("Failed to read article file: {}", path.display()))?;

        let parts: Vec<&str> = content.splitn(3, "---").collect();
        if parts.len() < 3 {
            return Err(anyhow::anyhow!("Invalid article format in {}: expected YAML frontmatter", path.display()));
        }

        let frontmatter = parts[1];
        let body = parts[2];

        let mut id = String::new();
        let mut feed_url = String::new();
        let mut title = String::new();
        let mut link = String::new();
        let mut author = None;
        let mut published = None;
        let mut read = false;
        let mut starred = false;

        for line in frontmatter.lines() {
            if let Some((key, value)) = line.split_once(':') {
                let key = key.trim();
                let value = value.trim();

                match key {
                    "id" => id = value.to_string(),
                    "feed" => feed_url = value.to_string(),
                    "title" => title = value.to_string(),
                    "link" => link = value.to_string(),
                    "author" => {
                        if !value.is_empty() {
                            author = Some(value.to_string());
                        }
                    }
                    "date" => {
                        published = DateTime::parse_from_rfc3339(value)
                            .ok()
                            .map(|d| d.with_timezone(&Utc));
                    }
                    "read" => read = value == "true",
                    "starred" => starred = value == "true",
                    _ => {}
                }
            }
        }

        Ok(FeedItem {
            id,
            feed_url,
            title,
            link,
            description: Some(body.to_string()),
            published,
            author,
            content: Some(body.to_string()),
            read,
            starred,
        })
    }

    /// Marks an article as read
    /// Updates the YAML frontmatter in the article file
    pub fn mark_as_read(&self, item_id: &str) -> Result<()> {
        self.update_article_state(item_id, "read", "true")
            .with_context(|| format!("Failed to mark article {} as read", item_id))
    }

    pub fn mark_as_unread(&self, item_id: &str) -> Result<()> {
        self.update_article_state(item_id, "read", "false")
    }

    /// Toggles the starred status of an article
    /// Updates the YAML frontmatter in the article file
    pub fn toggle_star(&self, item_id: &str) -> Result<()> {
        // Direct O(1) file access using article ID as filename
        let article_path = self.articles_dir.join(format!("{}.md", item_id));
        if !article_path.exists() {
            return Err(anyhow::anyhow!("Article not found: {}", item_id));
        }

        let content = fs::read_to_string(&article_path)
            .with_context(|| format!("Failed to read article {}", item_id))?;
        let is_starred = content.contains("starred: true");
        let new_value = if is_starred { "false" } else { "true" };
        self.update_article_state(item_id, "starred", new_value)
            .with_context(|| format!("Failed to toggle star for article {}", item_id))
    }

    fn update_article_state(&self, item_id: &str, field: &str, value: &str) -> Result<()> {
        // Direct O(1) file access using article ID as filename
        let article_path = self.articles_dir.join(format!("{}.md", item_id));
        if !article_path.exists() {
            return Err(anyhow::anyhow!("Article not found: {}", item_id));
        }

        let content = fs::read_to_string(&article_path)
            .with_context(|| format!("Failed to read article {}", item_id))?;
                    let old_line = format!("{}: ", field);
                    let new_line = format!("{}: {}", field, value);

                    let updated = content
                        .lines()
                        .map(|line| {
                            if line.starts_with(&old_line) {
                                new_line.clone()
                            } else {
                                line.to_string()
                            }
                        })
                        .collect::<Vec<_>>()
                        .join("\n");

        fs::write(&article_path, updated)
            .with_context(|| format!("Failed to update article {}", item_id))?;
        Ok(())
    }

    pub fn search_articles(&self, query: &str) -> Result<Vec<FeedItem>> {
        let mut results = Vec::new();
        let articles_dir = self.base_dir.join("articles");
        let query_lower = query.to_lowercase();

        for entry in fs::read_dir(&articles_dir)? {
            let entry = entry?;
            let path = entry.path();

            if path.extension().map_or(false, |ext| ext == "md") {
                let content = fs::read_to_string(&path)?;
                if content.to_lowercase().contains(&query_lower) {
                    if let Ok(item) = self.parse_article_file(&path) {
                        results.push(item);
                    }
                }
            }
        }

        results.sort_by(|a, b| b.published.cmp(&a.published));
        Ok(results)
    }

    pub fn get_unread_count(&self) -> Result<usize> {
        let articles_dir = self.base_dir.join("articles");
        let mut count = 0;

        for entry in fs::read_dir(&articles_dir)? {
            let entry = entry?;
            let path = entry.path();

            if path.extension().map_or(false, |ext| ext == "md") {
                let content = fs::read_to_string(&path)?;
                if content.contains("read: false") {
                    count += 1;
                }
            }
        }

        Ok(count)
    }

    pub fn store_feed_list(&self, feeds: Vec<String>) -> Result<()> {
        let feeds_file = self.base_dir.join("state").join("feeds.txt");
        fs::write(feeds_file, feeds.join("\n"))?;
        Ok(())
    }

    pub fn get_feed_list(&self) -> Result<Vec<String>> {
        let feeds_file = self.base_dir.join("state").join("feeds.txt");

        if !feeds_file.exists() {
            return Ok(Vec::new());
        }

        let content = fs::read_to_string(feeds_file)?;
        Ok(content
            .lines()
            .filter(|line| !line.is_empty())
            .map(String::from)
            .collect())
    }
}

fn sanitize_filename(s: &str) -> String {
    s.chars()
        .map(|c| {
            if c.is_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect::<String>()
        .chars()
        .take(50)
        .collect()
}