# zet-rss.nvim

A privacy-focused RSS reader that integrates seamlessly with your Neovim Zettelkasten workflow. No servers, no databases - just text files and a fast Rust backend with a beautiful TUI viewer.

## Features

- **Privacy First**: All data stored locally as plain text files
- **Zettelkasten Integration**: Scans your markdown notes for RSS feeds
- **TUI Viewer**: Beautiful terminal UI for reading articles with vim-style navigation
- **Smart Filtering**: Shows unread articles by default, sorted by date
- **Telescope UI**: Browse, search, and manage feeds within Neovim
- **Pure Text Storage**: Articles saved as markdown with YAML frontmatter
- **Fast Search**: Full-text search across all cached articles
- **Offline Reading**: Read cached articles anytime
- **Article Starring**: Mark articles for later reference
- **Unified Commands**: Single ZetRss command with intuitive subcommands

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "navicore/zet-rss.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  build = "cargo build --release && mkdir -p lua/zetrss/bin && cp target/release/zetrss lua/zetrss/bin/",
  lazy = false,  -- IMPORTANT: Required for commands to register properly
  config = function()
    require("zetrss").setup({
      -- Optional: override zet path (auto-detects ~/git/USERNAME/zet by default)
      -- zet_path = vim.fn.expand("~/my-custom-path/zet"),
    })
    -- Load Telescope extension
    require("telescope").load_extension("zetrss")
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'navicore/zet-rss.nvim',
  requires = { 'nvim-telescope/telescope.nvim' },
  run = 'make install',
  config = function()
    require('zetrss').setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-telescope/telescope.nvim'
Plug 'navicore/zet-rss.nvim', { 'do': 'make install' }
```

The plugin automatically compiles the Rust backend on first install. If you need to rebuild:

```bash
cd ~/.local/share/nvim/lazy/zet-rss.nvim  # or wherever your plugins are
cargo build --release && cp target/release/zetrss lua/zetrss/bin/
```

## Usage

### Unified Command Structure

ZetRss uses a single command with subcommands:

```vim
:ZetRss              " Browse unread articles (default)
:ZetRss all          " Browse all articles including read ones
:ZetRss search       " Search articles
:ZetRss starred      " Browse starred articles
:ZetRss scan          " Scan your Zettelkasten for RSS feed URLs
:ZetRss fetch         " Fetch new articles from all feeds
:ZetRss update        " Rescan notes and fetch new articles
:ZetRss mark-all-read " Mark all unread articles as read
:ZetRss clear-cache   " Clear all cached data (with confirmation)
```

### Telescope Commands (Alternative)

```vim
:Telescope zetrss           " Browse unread articles
:Telescope zetrss all       " Browse all articles
:Telescope zetrss search    " Search articles
:Telescope zetrss starred   " Show starred articles
```

### Keyboard Shortcuts

**In Telescope browser:**
- `<CR>` - Open article in TUI viewer (marks as read automatically)
- `<C-n>` - Create a Zettelkasten note from article

**In TUI viewer:**
- `j/k` - Scroll down/up
- `g/G` - Go to top/bottom
- `d/u` - Page down/up
- `Space` - Page down
- `q` - Quit viewer
- `o` - Open in web browser
- `n` - Create Zettelkasten note
- `s` - Toggle starred status

### CLI Usage (optional)

```bash
# Scan your zet directory for RSS feeds (auto-detects ~/git/USERNAME/zet)
zetrss scan

# Scan a custom path
zetrss scan --path ~/my-notes

# Fetch articles from all feeds
zetrss fetch

# Update: rescan zet and fetch
zetrss fetch --update
```

## How It Works

1. **Feed Discovery**: ZetRss scans your markdown files for:
   - URLs marked with `rss:` or `feed:` prefixes
   - YAML frontmatter with `rss_feeds:` lists
   - URLs ending in `.rss`, `.xml`, `/feed`, `/rss`, etc.

2. **Text Storage**: Articles are stored in `~/.local/share/nvim/zetrss/articles/` as markdown:
   ```markdown
   ---
   id: unique-article-id
   feed: https://example.com/rss
   title: Article Title
   link: https://example.com/article
   date: 2024-01-15T12:05:30Z
   read: false
   starred: false
   ---

   Article content...
   ```

3. **Direct File Access**: The Neovim plugin reads directly from these files - no server needed!

## Example Workflow

1. Add RSS feeds to your notes:
   ```markdown
   # Tech Blogs

   RSS: https://news.ycombinator.com/rss
   Feed: https://lobste.rs/rss

   Or in frontmatter:
   ---
   rss_feeds:
     - https://example.com/feed
     - https://blog.example.org/rss
   ---
   ```

2. In Neovim:
   ```vim
   :ZetRss scan     " Find feeds in your notes
   :ZetRss fetch    " Download articles
   :ZetRss          " Start reading!
   ```

3. Create notes from interesting articles with `n` in viewer or `<C-n>` in Telescope

## Data Storage

ZetRss stores data in Neovim's standard data directory:
- **Linux/macOS**: `~/.local/share/nvim/zetrss/`
- **Windows**: `~/AppData/Local/nvim-data/zetrss/`

```
~/.local/share/nvim/zetrss/
├── articles/           # Individual articles as .md files
│   ├── unique-article-id.md
│   └── ...
├── feeds/              # Feed metadata
│   └── feed-name.json
└── state/              # Feed URLs discovered from your notes
    └── feeds.txt
```

Articles are stored with clean, unique IDs and contain metadata in YAML frontmatter including read status, starred status, publication date, and more.

## Benefits

- **No Database**: Just text files you can grep, version control, or edit
- **Privacy**: No tracking, no cloud, no external servers
- **Speed**: Rust backend + local files = instant search
- **Integration**: Works seamlessly with your existing Zettelkasten
- **Hackable**: Plain text format works with any Unix tool
- **Intelligent Defaults**: Shows unread articles first, sorted by date
- **Clean UI**: Optimized Telescope preview with proper text wrapping

## Requirements

- Neovim 0.9+
- Telescope.nvim
- Rust (for building)
- Unix-like system (Linux/macOS)

## License

MIT