use anyhow::Result;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use walkdir::WalkDir;

/// Information about a discovered feed
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedSource {
    pub url: String,
    pub source_file: String,
    pub line_number: usize,
}

/// Scans a directory recursively for markdown files containing RSS feed URLs
/// Looks for URLs marked with '#feed' tag
/// Returns a deduplicated list of feed URLs with their source locations
pub async fn scan_markdown_for_feeds(zet_path: &str) -> Result<Vec<FeedSource>> {
    // Use HashMap to deduplicate by URL, keeping first occurrence
    let mut feeds: HashMap<String, FeedSource> = HashMap::new();

    // Match URLs explicitly marked with #feed tag
    let feed_tag_regex = Regex::new(r"#feed\s+(https?://[^\s\)>\]]+)")?;

    for entry in WalkDir::new(zet_path)
        .follow_links(true)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().is_some_and(|ext| ext == "md"))
    {
        let path = entry.path();
        let content = fs::read_to_string(path)?;

        for (line_num, line) in content.lines().enumerate() {
            for cap in feed_tag_regex.captures_iter(line) {
                if let Some(url) = cap.get(1) {
                    let url_str = url.as_str().trim();
                    // Clean up the URL - remove trailing punctuation that might not be part of URL
                    let url_str = url_str.trim_end_matches(['.', ',', ')', ']', '>']);

                    // Only insert if we haven't seen this URL before
                    if !feeds.contains_key(url_str) {
                        feeds.insert(
                            url_str.to_string(),
                            FeedSource {
                                url: url_str.to_string(),
                                source_file: path.to_string_lossy().to_string(),
                                line_number: line_num + 1, // 1-indexed for editors
                            },
                        );
                    }
                }
            }
        }
    }

    Ok(feeds.into_values().collect())
}
