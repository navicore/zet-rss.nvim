# NaviReader

A privacy-focused RSS reader that integrates seamlessly with your Neovim Zettelkasten workflow. No servers, no databases - just text files and a fast Rust backend with a beautiful TUI viewer.

## Features

- 🔒 **Privacy First**: All data stored locally as plain text files
- 📝 **Zettelkasten Integration**: Scans your markdown notes for RSS feeds
- 📖 **TUI Viewer**: Beautiful terminal UI for reading articles with vim-style navigation
- 🔍 **Smart Filtering**: Shows unread articles by default, sorted by date
- 🎯 **Telescope UI**: Browse, search, and manage feeds within Neovim
- 💾 **Pure Text Storage**: Articles saved as markdown with YAML frontmatter
- ⚡ **Fast Search**: Full-text search across all cached articles
- 📱 **Offline Reading**: Read cached articles anytime
- ⭐ **Article Starring**: Mark articles for later reference
- 🗂️ **Unified Commands**: Single NaviReader command with intuitive subcommands

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "navicore/navireader",
  dependencies = { "nvim-telescope/telescope.nvim" },
  build = "cargo build --release && mkdir -p bin && cp target/release/navireader bin/",
  lazy = false,  -- IMPORTANT: Required for commands to register properly
  config = function()
    require("navireader").setup({
      -- Optional: override zet path (auto-detects ~/git/USERNAME/zet by default)
      -- zet_path = vim.fn.expand("~/my-custom-path/zet"),
    })
    -- Load Telescope extension
    require("telescope").load_extension("navireader")
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'navicore/navireader',
  requires = { 'nvim-telescope/telescope.nvim' },
  run = 'make install',
  config = function()
    require('navireader').setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-telescope/telescope.nvim'
Plug 'navicore/navireader', { 'do': 'make install' }
```

The plugin automatically compiles the Rust backend on first install. If you need to rebuild:

```bash
cd ~/.local/share/nvim/lazy/navireader  # or wherever your plugins are
cargo build --release && cp target/release/navireader bin/
```

## Usage

### Unified Command Structure

NaviReader uses a single command with subcommands:

```vim
:NaviReader              " Browse unread articles (default)
:NaviReader all          " Browse all articles including read ones
:NaviReader search       " Search articles
:NaviReader starred      " Browse starred articles
:NaviReader scan          " Scan your Zettelkasten for RSS feed URLs
:NaviReader fetch         " Fetch new articles from all feeds
:NaviReader update        " Rescan notes and fetch new articles
:NaviReader mark-all-read " Mark all unread articles as read
:NaviReader clear-cache   " Clear all cached data (with confirmation)
```

### Telescope Commands (Alternative)

```vim
:Telescope navireader           " Browse unread articles
:Telescope navireader all       " Browse all articles
:Telescope navireader search    " Search articles
:Telescope navireader starred   " Show starred articles
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
navireader scan

# Scan a custom path
navireader scan --path ~/my-notes

# Fetch articles from all feeds
navireader fetch

# Update: rescan zet and fetch
navireader fetch --update
```

## How It Works

1. **Feed Discovery**: NaviReader scans your markdown files for:
   - URLs marked with `rss:` or `feed:` prefixes
   - YAML frontmatter with `rss_feeds:` lists
   - URLs ending in `.rss`, `.xml`, `/feed`, `/rss`, etc.

2. **Text Storage**: Articles are stored in `~/.local/share/nvim/navireader/articles/` as markdown:
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
   :NaviReader scan     " Find feeds in your notes
   :NaviReader fetch    " Download articles
   :NaviReader          " Start reading!
   ```

3. Create notes from interesting articles with `n` in viewer or `<C-n>` in Telescope

## Data Storage

NaviReader stores data in Neovim's standard data directory:
- **Linux/macOS**: `~/.local/share/nvim/navireader/`
- **Windows**: `~/AppData/Local/nvim-data/navireader/`

```
~/.local/share/nvim/navireader/
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