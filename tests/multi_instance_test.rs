use std::process::Command;
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use tempfile::TempDir;

#[test]
#[ignore] // Run with: cargo test --ignored multi_instance
fn test_multiple_viewer_instances() {
    // Create a test environment
    let temp_dir = TempDir::new().unwrap();
    let data_dir = temp_dir.path().to_str().unwrap();

    // Prepare test data by initializing cache
    std::env::set_var("ZETRSS_DATA_DIR", data_dir);

    // Create test articles
    let cache = zetrss::cache::TextCache::new().unwrap();
    let test_feed = zetrss::models::Feed {
        url: "https://test.com/feed".to_string(),
        title: "Test Feed".to_string(),
        description: Some("Test".to_string()),
        last_fetched: Some(chrono::Utc::now()),
        items: vec![
            zetrss::models::FeedItem {
                id: "test-1".to_string(),
                feed_url: "https://test.com/feed".to_string(),
                title: "Test Article 1".to_string(),
                link: "https://test.com/1".to_string(),
                description: Some("Test 1".to_string()),
                published: Some(chrono::Utc::now()),
                author: None,
                content: Some("Content 1".to_string()),
                read: false,
                starred: false,
                filepath: None,
            },
            zetrss::models::FeedItem {
                id: "test-2".to_string(),
                feed_url: "https://test.com/feed".to_string(),
                title: "Test Article 2".to_string(),
                link: "https://test.com/2".to_string(),
                description: Some("Test 2".to_string()),
                published: Some(chrono::Utc::now()),
                author: None,
                content: Some("Content 2".to_string()),
                read: false,
                starred: false,
                filepath: None,
            },
        ],
    };

    cache.store_feed(&test_feed).unwrap();

    // Launch multiple viewer instances concurrently
    let handles: Vec<_> = (0..3).map(|i| {
        let data_dir = data_dir.to_string();
        thread::spawn(move || {
            // Each instance gets a unique session ID automatically
            let output = Command::new("./target/release/zetrss")
                .env("ZETRSS_DATA_DIR", &data_dir)
                .arg("view")
                .arg("--id")
                .arg(format!("test-{}", (i % 2) + 1))
                .output();

            match output {
                Ok(out) => {
                    println!("Instance {} completed with status: {}", i, out.status);
                    assert!(out.status.success() || out.status.code() == Some(0));
                }
                Err(e) => {
                    // Expected - viewer requires terminal
                    println!("Instance {} error (expected): {}", i, e);
                }
            }
        })
    }).collect();

    // Wait for all threads to complete
    for handle in handles {
        handle.join().unwrap();
    }

    // Verify no temp files are left behind
    let temp_system_dir = std::env::temp_dir();
    let entries = std::fs::read_dir(&temp_system_dir).unwrap();
    for entry in entries {
        let entry = entry.unwrap();
        let file_name = entry.file_name();
        let name_str = file_name.to_string_lossy();

        // Ensure no zetrss temp files remain
        assert!(
            !name_str.starts_with("zetrss_open_url_") &&
            !name_str.starts_with("zetrss_note_path_"),
            "Found leftover temp file: {}",
            name_str
        );
    }

    println!("Multi-instance test completed successfully");
}