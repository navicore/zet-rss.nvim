# Architecture

## Context & Scope

zet-rss.nvim is a companion plugin to [zet.nvim](https://github.com/navicore/zet.nvim) that adds RSS reading to the Zettelkasten workflow. It discovers feeds from zet notes, fetches articles, and presents them through Telescope pickers and a Ratatui-based TUI viewer. Formerly named `navireader`.

**External interactions:**
- RSS/Atom feeds over HTTP (fetched via `reqwest`)
- Local filesystem for all persistent state (no database, no server)
- Neovim APIs (user commands, floating windows, terminal buffers)
- Telescope.nvim (picker UI, previewer, extension registration)
- System browser (via `open`/`xdg-open`, triggered from Lua side)

**Boundaries:** Everything runs locally. The Rust binary is invoked as a subprocess by Lua. Communication between Rust and Lua happens through exit codes, temp files (for URLs/paths), the filesystem (article markdown files), and stdout/stderr.

## Solution Strategy

- **Rust binary (`zetrss`)**: handles feed scanning, HTTP fetching, caching, and the TUI viewer. Built with `tokio` for async I/O, `feed-rs` for RSS/Atom parsing, `ratatui`/`crossterm` for TUI, `clap` for CLI.
- **Lua plugin layer**: Neovim integration via `lua/zetrss/` modules. Calls the Rust binary via `vim.fn.jobstart`/`vim.fn.system` with `ZETRSS_DATA_DIR` env var. Provides `:ZetRss` command with subcommands.
- **Telescope extension** (`lua/telescope/_extensions/zetrss.lua`): article browsing, search, starred, feed listing. Opens TUI viewer in a floating terminal buffer.
- **Plain text storage**: articles stored as markdown with YAML frontmatter. Read/starred state tracked in frontmatter fields. No database.

## Building Blocks

### Rust modules (`src/`)

| Module | Responsibility |
|---|---|
| `main.rs` | CLI entry point, subcommand dispatch (scan, fetch, view, mark-read, mark-all-read, list-feeds) |
| `models.rs` | Core domain types: `FeedItem`, `Feed` |
| `scanner.rs` | Walks Zettelkasten directory, finds `#feed <url>` patterns in markdown files. Returns `FeedSource` (url + source file + line number) |
| `fetcher.rs` | HTTP fetch of RSS/Atom feeds via `reqwest` + `feed-rs`, converts to `Feed`/`FeedItem` |
| `cache.rs` | `TextCache` struct: reads/writes article markdown files, manages feed lists (`state/feeds.json`), handles read/starred state updates. Constructors: `new()` (from env/XDG) and `with_base_dir()` (explicit path, used by tests) |
| `viewer.rs` | Ratatui TUI for reading a single article. Communicates actions (open browser, create note, open in vim) via exit codes + temp files |
| `lib.rs` | Re-exports all modules for library use |

### Lua modules (`lua/`)

| Module | Responsibility |
|---|---|
| `zetrss/init.lua` | Plugin setup, config management, `:ZetRss` command registration, binary discovery, scan/fetch/mark-all-read/clear-cache functions |
| `zetrss/articles.lua` | Reads article markdown files from disk, parses frontmatter, provides filtering (read/unread), sorting, search, feed stats |
| `telescope/_extensions/zetrss.lua` | Telescope extension: pickers for unread/all/search/starred/feeds/browse-feeds. Opens TUI viewer in floating terminal. Handles viewer exit codes for browser/note/vim actions |

### Domain entities

- **FeedSource**: a discovered feed URL with its source markdown file and line number
- **FeedItem**: an article with id, title, link, content, feed_url, published date, read/starred booleans, filepath
- **Feed**: a feed with URL, title, description, last_fetched, and items

### Data directory layout (`~/.local/share/nvim/zetrss/`)

```
articles/   - individual .md files (YAML frontmatter + body)
feeds/      - per-feed JSON metadata
state/      - feeds.json (discovered feed list)
```

## Crosscutting Concepts

- **Rust-Lua coordination**: the Lua plugin passes `ZETRSS_DATA_DIR` as an env var to every Rust binary invocation so both sides read/write the same directory. A `ZETRSS_SESSION_ID` env var prevents temp file race conditions between concurrent viewer sessions.
- **Exit code protocol**: the TUI viewer uses exit codes to signal actions back to Lua: 0=quit, 1=open browser, 2=create note, 3=open in vim. Associated data (URLs, paths) is passed via session-specific temp files.
- **Feed discovery**: feeds are found by scanning markdown files for `#feed <url>` patterns. The README mentions other patterns (rss:, feed:, frontmatter) but the scanner currently only matches `#feed`.
- **Concurrent fetching**: feed fetching uses a semaphore-bounded `buffer_unordered` stream (max 5 concurrent).
- **Error handling**: Rust uses `anyhow::Result` throughout. Lua wraps setup in `pcall` and uses `vim.notify` for user-facing errors.
- **Article identity**: articles are identified by their feed-provided ID, stored in YAML frontmatter. Filenames combine date + sanitized ID. Deduplication happens at store time.
