mod scanner;
mod fetcher;
mod cache;
mod models;
mod viewer;

use clap::{Parser, Subcommand};
use anyhow::Result;
use tracing_subscriber;

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

            for feed_url in feeds {
                println!("Fetching: {}", feed_url);
                match fetcher::fetch_feed(&feed_url).await {
                    Ok(feed_data) => {
                        cache.store_feed(&feed_data)?;
                        println!("  ✓ Stored {} items", feed_data.items.len());
                    }
                    Err(e) => {
                        eprintln!("  ✗ Failed: {}", e);
                    }
                }
            }
        }
        Commands::View { id } => {
            // Launch the TUI viewer
            let exit_code = viewer::run_viewer(&id)?;
            std::process::exit(exit_code);
        }
    }

    Ok(())
}
