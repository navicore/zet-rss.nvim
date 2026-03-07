# Roadmap

## Current State

The plugin is functional: feed discovery, fetching, article browsing (Telescope + TUI), read/starred tracking, search, note creation, and per-feed browsing all work. The Rust binary builds and is distributed as a user-compiled artifact via `cargo build --release`.

## Known Issues

- `get_article_by_id` in `cache.rs` scans all articles linearly. Could be indexed for faster lookup in large collections.
- `test_get_articles_limit` is flaky in the bin test target due to shared `ZETRSS_DATA_DIR` env var across concurrent tests creating timestamp collisions.

## Potential Next Steps

- Index articles by ID for faster lookup
- Add feed auto-discovery (probe common feed paths for domains found in notes)
