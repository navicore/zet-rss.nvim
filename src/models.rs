use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedItem {
    pub id: String,
    pub feed_url: String,
    pub title: String,
    pub link: String,
    pub description: Option<String>,
    pub published: Option<DateTime<Utc>>,
    pub author: Option<String>,
    pub content: Option<String>,
    pub read: bool,
    pub starred: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Feed {
    pub url: String,
    pub title: String,
    pub description: Option<String>,
    pub last_fetched: Option<DateTime<Utc>>,
    pub items: Vec<FeedItem>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SearchResult {
    pub items: Vec<FeedItem>,
    pub total: usize,
}