# NaviReader

A privacy-focused RSS reader that integrates seamlessly with your Neovim Zettelkasten workflow. No servers, no databases - just text files and a fast Rust backend.

## Features

- **Privacy First**: All data stored locally as plain text files
- **Zettelkasten Integration**: Scans your markdown notes for RSS feeds
- **Pure Text Storage**: Articles saved as markdown with YAML frontmatter
- **Telescope UI**: Browse, search, and manage feeds within Neovim
- **Fast Search**: Full-text search across all cached articles
- **Offline Reading**: Read cached articles anytime

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "navicore/navireader",
  dependencies = { "nvim-telescope/telescope.nvim" },
  build = "make install",  -- Automatically builds Rust binary
  lazy = false,  -- Load immediately to register commands
  config = function()
    require("navireader").setup({
      -- Optional: override zet path (auto-detects ~/git/USERNAME/zet by default)
      -- zet_path = vim.fn.expand("~/my-custom-path/zet"),
    })
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
make clean build
```

## Usage

### Neovim Commands

```vim
:NaviReaderScan    " Scan your zet for RSS feed URLs
:NaviReaderFetch   " Fetch new articles from all feeds
:NaviReaderUpdate  " Rescan zet and fetch new articles

:Telescope navireader           " Browse all articles
:Telescope navireader search    " Search articles
:Telescope navireader starred   " Show starred articles
```

### Telescope Keybindings

| Key | Action |
|-----|--------|
| `<CR>` | Open article in browser & mark as read |
| `<C-n>` | Create new Zettelkasten note from article |
| `<C-s>` | Toggle star |
| `<C-r>` | Mark as read without opening |
| `<C-y>` | Copy link to clipboard |
| `<C-i>` | Show stats (total/unread counts) |

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

2. **Text Storage**: Articles are stored in `~/.navireader/articles/` as markdown:
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
   :NaviReaderScan     " Find feeds in your notes
   :NaviReaderFetch    " Download articles
   :Telescope navireader  " Start reading!
   ```

3. Create notes from interesting articles with `<C-n>`

## File Structure

```
~/.navireader/
├── articles/           # Individual articles as .md files
│   ├── 20240115-120530-article-title.md
│   └── ...
├── feeds/              # Feed metadata
│   └── feed-name.json
└── state/              # Feed URLs discovered from your notes
    └── feeds.txt
```

## Benefits

- **No Database**: Just text files you can grep, version control, or edit
- **Privacy**: No tracking, no cloud, no external servers
- **Speed**: Rust backend + local files = instant search
- **Integration**: Works seamlessly with your existing Zettelkasten
- **Hackable**: Plain text format works with any Unix tool

## Requirements

- Neovim 0.9+
- Telescope.nvim
- Rust (for building)
- Unix-like system (Linux/macOS)

## License

MIT