use anyhow::{Result, anyhow};
use feed_rs::parser;
use reqwest;
use crate::models::{Feed, FeedItem};
use chrono::Utc;

/// Fetches an RSS/Atom feed from the given URL
/// Parses the feed and converts it to our internal Feed model
/// Returns an error if the fetch fails or the feed is invalid
pub async fn fetch_feed(url: &str) -> Result<Feed> {
    let client = reqwest::Client::builder()
        .user_agent("NaviReader/0.1")
        .timeout(std::time::Duration::from_secs(30))
        .build()?;

    let response = client.get(url).send().await?;

    if !response.status().is_success() {
        return Err(anyhow!("Failed to fetch feed: {}", response.status()));
    }

    let bytes = response.bytes().await?;
    let feed = parser::parse(&bytes[..])?;

    let mut items = Vec::new();

    for entry in feed.entries {
        let id = entry.id.clone();
        let title = entry.title
            .map(|t| t.content)
            .unwrap_or_else(|| "Untitled".to_string());

        let link = entry.links
            .first()
            .map(|l| l.href.clone())
            .unwrap_or_else(|| url.to_string());

        let description = entry.summary.map(|s| s.content);

        let published = entry.published
            .or(entry.updated)
            .map(|d| d.with_timezone(&Utc));

        let author = entry.authors
            .first()
            .and_then(|a| Some(a.name.clone()));

        let content = entry.content
            .and_then(|c| c.body)
            .or_else(|| description.clone());

        items.push(FeedItem {
            id,
            feed_url: url.to_string(),
            title,
            link,
            description,
            published,
            author,
            content,
            read: false,
            starred: false,
            filepath: None,
        });
    }

    let feed_title = feed.title
        .map(|t| t.content)
        .unwrap_or_else(|| url.to_string());

    let feed_description = feed.description.map(|d| d.content);

    Ok(Feed {
        url: url.to_string(),
        title: feed_title,
        description: feed_description,
        last_fetched: Some(Utc::now()),
        items,
    })
}