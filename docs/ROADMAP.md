# Roadmap

## Current State

The plugin is functional: feed discovery, fetching, article browsing (Telescope + TUI), read/starred tracking, search, note creation, and per-feed browsing all work. The Rust binary builds and is distributed as a user-compiled artifact via `./build.sh`. CI runs tests, clippy (with `-D warnings`), and rustfmt on push/PR to main.

## Known Issues

- `get_article_by_id` in `cache.rs` scans all articles linearly. Could be indexed for faster lookup in large collections.

## Potential Next Steps

- Index articles by ID for faster lookup
- Add feed auto-discovery (probe common feed paths for domains found in notes)
