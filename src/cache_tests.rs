use super::*;
use crate::models::{Feed, FeedItem};
use chrono::Utc;
use tempfile::TempDir;

fn create_test_cache() -> (TextCache, TempDir) {
    let temp_dir = TempDir::new().unwrap();
    std::env::set_var("NAVIREADER_DATA_DIR", temp_dir.path().to_str().unwrap());
    let cache = TextCache::new().unwrap();
    (cache, temp_dir)
}

fn create_test_feed() -> Feed {
    Feed {
        url: "https://example.com/feed".to_string(),
        title: "Test Feed".to_string(),
        description: Some("Test Description".to_string()),
        last_fetched: Some(Utc::now()),
        items: vec![
            FeedItem {
                id: "test-article-1".to_string(),
                feed_url: "https://example.com/feed".to_string(),
                title: "Test Article 1".to_string(),
                link: "https://example.com/article1".to_string(),
                description: Some("Article 1 description".to_string()),
                published: Some(Utc::now()),
                author: Some("Test Author".to_string()),
                content: Some("Article 1 content".to_string()),
                read: false,
                starred: false,
            },
            FeedItem {
                id: "test-article-2".to_string(),
                feed_url: "https://example.com/feed".to_string(),
                title: "Test Article 2".to_string(),
                link: "https://example.com/article2".to_string(),
                description: Some("Article 2 description".to_string()),
                published: Some(Utc::now()),
                author: Some("Test Author".to_string()),
                content: Some("Article 2 content".to_string()),
                read: false,
                starred: false,
            },
        ],
    }
}

#[test]
fn test_o1_article_lookup() {
    let (cache, _temp_dir) = create_test_cache();
    let feed = create_test_feed();

    // Store the feed
    cache.store_feed(&feed).unwrap();

    // Test O(1) lookup by ID
    let article = cache.get_article_by_id("test-article-1").unwrap();
    assert!(article.is_some());
    let article = article.unwrap();
    assert_eq!(article.id, "test-article-1");
    assert_eq!(article.title, "Test Article 1");

    // Test non-existent article
    let article = cache.get_article_by_id("non-existent").unwrap();
    assert!(article.is_none());
}

#[test]
fn test_mark_as_read() {
    let (cache, _temp_dir) = create_test_cache();
    let feed = create_test_feed();

    // Store the feed
    cache.store_feed(&feed).unwrap();

    // Mark article as read
    cache.mark_as_read("test-article-1").unwrap();

    // Verify it's marked as read
    let article = cache.get_article_by_id("test-article-1").unwrap().unwrap();
    assert!(article.read);

    // Verify error for non-existent article
    let result = cache.mark_as_read("non-existent");
    assert!(result.is_err());
}

#[test]
fn test_toggle_star() {
    let (cache, _temp_dir) = create_test_cache();
    let feed = create_test_feed();

    // Store the feed
    cache.store_feed(&feed).unwrap();

    // Toggle star on
    cache.toggle_star("test-article-1").unwrap();
    let article = cache.get_article_by_id("test-article-1").unwrap().unwrap();
    assert!(article.starred);

    // Toggle star off
    cache.toggle_star("test-article-1").unwrap();
    let article = cache.get_article_by_id("test-article-1").unwrap().unwrap();
    assert!(!article.starred);

    // Verify error for non-existent article
    let result = cache.toggle_star("non-existent");
    assert!(result.is_err());
}

#[test]
fn test_get_articles_limit() {
    let (cache, _temp_dir) = create_test_cache();
    let mut feed = create_test_feed();

    // Add more articles
    for i in 3..10 {
        feed.items.push(FeedItem {
            id: format!("test-article-{}", i),
            feed_url: "https://example.com/feed".to_string(),
            title: format!("Test Article {}", i),
            link: format!("https://example.com/article{}", i),
            description: Some(format!("Article {} description", i)),
            published: Some(Utc::now()),
            author: Some("Test Author".to_string()),
            content: Some(format!("Article {} content", i)),
            read: false,
            starred: false,
        });
    }

    cache.store_feed(&feed).unwrap();

    // Test with limit
    let articles = cache.get_articles(Some(5)).unwrap();
    assert_eq!(articles.len(), 5);

    // Test without limit
    let articles = cache.get_articles(None).unwrap();
    assert_eq!(articles.len(), 9);
}