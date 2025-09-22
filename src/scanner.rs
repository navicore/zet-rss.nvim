use anyhow::Result;
use regex::Regex;
use std::collections::HashSet;
use std::fs;
use walkdir::WalkDir;

/// Scans a directory recursively for markdown files containing RSS feed URLs
/// Looks for URLs marked with 'rss:', 'feed:', in YAML frontmatter, or with RSS-like extensions
/// Returns a deduplicated list of feed URLs
pub async fn scan_markdown_for_feeds(zet_path: &str) -> Result<Vec<String>> {
    let mut feeds = HashSet::new();

    // Match URLs explicitly marked as RSS/feed
    let explicit_feed_regex = Regex::new(r"(?i)(?:rss[:\s]+|feed[:\s]+|<!-- rss:\s*)(https?://[^\s\)>\]]+)")?;

    // Match frontmatter feed lists
    let frontmatter_regex = Regex::new(r"(?m)^rss_feeds?:\s*\n((?:\s*-\s*.+\n)+)")?;
    let frontmatter_item_regex = Regex::new(r"^\s*-\s*(.+)$")?;

    // Match URLs with definitive feed file extensions or paths
    let feed_extension_regex = Regex::new(r"(https?://[^\s\)>\]]+(?:\.rss|\.xml|\.atom)(?:\?[^\s\)>\]]*)?)")?;
    let feed_path_regex = Regex::new(r"(https?://[^\s\)>\]]+/(?:feed|rss|atom)(?:/|\?|$)[^\s\)>\]]*)")?;

    for entry in WalkDir::new(zet_path)
        .follow_links(true)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |ext| ext == "md"))
    {
        let content = fs::read_to_string(entry.path())?;

        // Look for explicitly marked RSS feeds
        for cap in explicit_feed_regex.captures_iter(&content) {
            if let Some(url) = cap.get(1) {
                let url_str = url.as_str().trim();
                // Clean up the URL - remove trailing punctuation that might not be part of URL
                let url_str = url_str.trim_end_matches(|c: char| c == '.' || c == ',' || c == ')' || c == ']' || c == '>');
                feeds.insert(url_str.to_string());
            }
        }

        // Look for feeds in frontmatter
        if let Some(fm_cap) = frontmatter_regex.captures(&content) {
            if let Some(items) = fm_cap.get(1) {
                for item_cap in frontmatter_item_regex.captures_iter(items.as_str()) {
                    if let Some(url) = item_cap.get(1) {
                        let cleaned_url = url.as_str().trim().trim_matches('"').trim_matches('\'');
                        if cleaned_url.starts_with("http") {
                            feeds.insert(cleaned_url.to_string());
                        }
                    }
                }
            }
        }

        // Look for URLs with feed file extensions
        for cap in feed_extension_regex.captures_iter(&content) {
            if let Some(url) = cap.get(1) {
                let url_str = url.as_str();
                // Filter out common false positives
                if !url_str.contains("/post/") && !url_str.contains("/blog/post/") {
                    feeds.insert(url_str.to_string());
                }
            }
        }

        // Look for URLs with feed paths (but be strict)
        for cap in feed_path_regex.captures_iter(&content) {
            if let Some(url) = cap.get(1) {
                let url_str = url.as_str();
                // Only include if it ends with /feed, /rss, or /atom (with or without trailing slash)
                if url_str.ends_with("/feed") || url_str.ends_with("/feed/") ||
                   url_str.ends_with("/rss") || url_str.ends_with("/rss/") ||
                   url_str.ends_with("/atom") || url_str.ends_with("/atom/") ||
                   url_str.contains("/feed?") || url_str.contains("/rss?") || url_str.contains("/atom?") {
                    feeds.insert(url_str.to_string());
                }
            }
        }
    }

    Ok(feeds.into_iter().collect())
}

pub async fn discover_feeds_from_domains(zet_path: &str) -> Result<Vec<String>> {
    let domain_regex = Regex::new(r"https?://([^/\s]+)")?;
    let mut domains = HashSet::new();
    let mut discovered_feeds = Vec::new();

    for entry in WalkDir::new(zet_path)
        .follow_links(true)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |ext| ext == "md"))
    {
        let content = fs::read_to_string(entry.path())?;
        for cap in domain_regex.captures_iter(&content) {
            if let Some(domain) = cap.get(1) {
                domains.insert(domain.as_str().to_string());
            }
        }
    }

    for domain in domains {
        let potential_feeds = vec![
            format!("https://{}/feed", domain),
            format!("https://{}/rss", domain),
            format!("https://{}/feed.xml", domain),
            format!("https://{}/rss.xml", domain),
            format!("https://{}/atom.xml", domain),
            format!("https://{}/index.xml", domain),
        ];

        for feed_url in potential_feeds {
            if check_feed_exists(&feed_url).await {
                discovered_feeds.push(feed_url);
                break;
            }
        }
    }

    Ok(discovered_feeds)
}

async fn check_feed_exists(url: &str) -> bool {
    match reqwest::Client::new()
        .head(url)
        .timeout(std::time::Duration::from_secs(5))
        .send()
        .await
    {
        Ok(response) => response.status().is_success(),
        Err(_) => false,
    }
}