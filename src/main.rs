mod scanner;
mod fetcher;
mod cache;
mod models;
mod viewer;

use clap::{Parser, Subcommand};
use anyhow::Result;
use tracing_subscriber;
use futures::stream::{self, StreamExt};
use std::sync::Arc;
use tokio::sync::Semaphore;

#[derive(Parser)]
#[command(name = "navireader")]
#[command(about = "RSS reader integrated with your Zettelkasten", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Scan {
        #[arg(short, long)]
        path: Option<String>,
    },
    Fetch {
        #[arg(short, long)]
        update: bool,
    },
    View {
        #[arg(short, long)]
        id: String,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let cli = Cli::parse();

    match cli.command {
        Commands::Scan { path } => {
            let scan_path = match path {
                Some(p) => p,
                None => {
                    // Get username dynamically
                    let username = std::env::var("USER")
                        .or_else(|_| std::env::var("USERNAME"))
                        .unwrap_or_else(|_| "user".to_string());
                    format!("~/git/{}/zet", username)
                }
            };
            let expanded_path = shellexpand::tilde(&scan_path).to_string();
            let feeds = scanner::scan_markdown_for_feeds(&expanded_path).await?;

            let cache = cache::TextCache::new()?;
            cache.store_feed_list(feeds.clone())?;

            println!("Found {} RSS feeds:", feeds.len());
            for feed in feeds {
                println!("  - {}", feed);
            }
        }
        Commands::Fetch { update } => {
            let cache = cache::TextCache::new()?;
            let feeds = if update {
                // Get username dynamically for update path
                let username = std::env::var("USER")
                    .or_else(|_| std::env::var("USERNAME"))
                    .unwrap_or_else(|_| "user".to_string());
                let zet_path = format!("~/git/{}/zet", username);
                let expanded_path = shellexpand::tilde(&zet_path).to_string();
                let new_feeds = scanner::scan_markdown_for_feeds(&expanded_path).await?;
                cache.store_feed_list(new_feeds.clone())?;
                new_feeds
            } else {
                cache.get_feed_list()?
            };

            // Concurrent fetching with rate limiting (max 5 concurrent fetches)
            const MAX_CONCURRENT_FETCHES: usize = 5;
            let semaphore = Arc::new(Semaphore::new(MAX_CONCURRENT_FETCHES));
            let cache = Arc::new(cache);

            println!("Fetching {} feeds (up to {} concurrently)...", feeds.len(), MAX_CONCURRENT_FETCHES);

            let fetch_tasks = feeds.into_iter().map(|feed_url| {
                let sem = semaphore.clone();
                let cache = cache.clone();
                async move {
                    let _permit = sem.acquire().await.unwrap();
                    println!("  Fetching: {}", feed_url);
                    match fetcher::fetch_feed(&feed_url).await {
                        Ok(feed_data) => {
                            let item_count = feed_data.items.len();
                            match cache.store_feed(&feed_data) {
                                Ok(_) => println!("    ✓ Stored {} items", item_count),
                                Err(e) => eprintln!("    ✗ Failed to store: {}", e),
                            }
                        }
                        Err(e) => {
                            eprintln!("    ✗ Failed to fetch: {}", e);
                        }
                    }
                }
            });

            // Execute all fetches concurrently
            stream::iter(fetch_tasks)
                .buffer_unordered(MAX_CONCURRENT_FETCHES)
                .collect::<Vec<_>>()
                .await;

            println!("\nFeed fetching complete!");
        }
        Commands::View { id } => {
            // Launch the TUI viewer
            let exit_code = viewer::run_viewer(&id)?;
            std::process::exit(exit_code);
        }
    }

    Ok(())
}
