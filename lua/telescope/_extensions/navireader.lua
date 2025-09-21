local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local M = {}

local function format_entry(article)
  local date_str = ""
  if article.published then
    -- Try to parse the date
    local year, month, day, hour, min = article.published:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
    if year then
      date_str = string.format("%02d/%02d %02d:%02d", month, day, hour, min)
    else
      date_str = article.published:sub(1, 10)
    end
  end

  local read_indicator = article.read and "✓" or "●"
  local star_indicator = article.starred and "★" or " "

  local feed_name = article.feed or ""
  -- Extract domain from feed URL
  local domain = feed_name:match("https?://([^/]+)") or feed_name

  return string.format(
    "%s %s [%s] %s - %s",
    read_indicator,
    star_indicator,
    date_str,
    article.title or "Untitled",
    domain
  )
end

local function navireader_picker(opts)
  opts = opts or {}

  local articles_module = require("navireader.articles")
  local articles

  if opts.query and opts.query ~= "" then
    articles = articles_module.search_articles(opts.query)
  else
    articles = articles_module.get_articles(opts.limit or 100)
  end

  if #articles == 0 then
    vim.notify("No articles found. Run :NaviReaderFetch to fetch RSS feeds.", vim.log.levels.WARN)
    return
  end

  pickers.new(opts, {
    prompt_title = "NaviReader RSS Articles",
    finder = finders.new_table({
      results = articles,
      entry_maker = function(article)
        return {
          value = article,
          display = format_entry(article),
          ordinal = string.format(
            "%s %s %s",
            article.title or "",
            article.content or "",
            article.feed or ""
          ),
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_buffer_previewer({
      title = "Article Preview",
      define_preview = function(self, entry)
        local article = entry.value
        local lines = {}

        -- Add title
        table.insert(lines, "# " .. (article.title or "Untitled"))
        table.insert(lines, "")

        -- Add metadata
        table.insert(lines, "**Source:** " .. (article.feed or "Unknown"))
        table.insert(lines, "**Link:** " .. (article.link or ""))
        if article.author and article.author ~= "" then
          table.insert(lines, "**Author:** " .. article.author)
        end
        if article.published then
          table.insert(lines, "**Published:** " .. article.published)
        end
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "")

        -- Add content
        if article.content then
          local content_lines = vim.split(article.content, "\n")
          for _, line in ipairs(content_lines) do
            -- Skip the markdown title and link at the end if present
            if not line:match("^# ") and not line:match("^%[Read original%]") then
              table.insert(lines, line)
            end
          end
        end

        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      -- Open in browser (default action)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if selection then
          local article = selection.value
          local articles_module = require("navireader.articles")
          articles_module.mark_as_read(article.id)

          -- Open link in browser
          local open_cmd
          if vim.fn.has("mac") == 1 then
            open_cmd = "open"
          elseif vim.fn.has("unix") == 1 then
            open_cmd = "xdg-open"
          else
            vim.notify("Cannot open browser on this platform", vim.log.levels.ERROR)
            return
          end

          vim.fn.system(open_cmd .. " " .. vim.fn.shellescape(article.link))
          vim.notify("Opened: " .. article.title, vim.log.levels.INFO)

          -- Refresh the picker
          actions.close(prompt_bufnr)
          navireader_picker(opts)
        end
      end)

      -- Toggle star
      map("i", "<C-s>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          local articles_module = require("navireader.articles")
          articles_module.toggle_star(selection.value.id)
          vim.notify("Toggled star for: " .. selection.value.title)

          -- Refresh the picker
          actions.close(prompt_bufnr)
          navireader_picker(opts)
        end
      end)

      -- Mark as read
      map("i", "<C-r>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          local articles_module = require("navireader.articles")
          articles_module.mark_as_read(selection.value.id)
          vim.notify("Marked as read: " .. selection.value.title)

          -- Refresh the picker
          actions.close(prompt_bufnr)
          navireader_picker(opts)
        end
      end)

      -- Copy link to clipboard
      map("i", "<C-y>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          vim.fn.setreg("+", selection.value.link)
          vim.notify("Copied link to clipboard")
        end
      end)

      -- Create note from article
      map("i", "<C-n>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          actions.close(prompt_bufnr)

          local article = selection.value
          local navireader = require("navireader")
          local config = navireader.get_config()

          -- Generate filename
          local date = vim.fn.strftime("%Y%m%d%H%M")
          local safe_title = article.title:gsub("[^%w]+", "-"):lower():sub(1, 50)
          local filename = config.zet_path .. "/" .. date .. "-" .. safe_title .. ".md"

          -- Create note content
          local content = {
            "# " .. article.title,
            "",
            "Source: " .. article.link,
            "Feed: " .. article.feed,
            "Date: " .. (article.published or ""),
            "",
            "## Summary",
            "",
          }

          -- Add first paragraph of content as summary
          if article.content then
            local first_para = article.content:match("^(.-)\n\n") or article.content:sub(1, 500)
            table.insert(content, first_para)
          end

          table.insert(content, "")
          table.insert(content, "## Notes")
          table.insert(content, "")
          table.insert(content, "")

          -- Write file
          vim.fn.writefile(content, filename)
          vim.cmd("edit " .. filename)
          vim.notify("Created note: " .. filename)

          -- Mark as read
          local articles_module = require("navireader.articles")
          articles_module.mark_as_read(article.id)
        end
      end)

      -- Show stats
      map("i", "<C-i>", function()
        local articles_module = require("navireader.articles")
        local stats = articles_module.get_stats()
        vim.notify(string.format(
          "Articles: %d total, %d unread",
          stats.total,
          stats.unread
        ), vim.log.levels.INFO)
      end)

      return true
    end,
  }):find()
end

function M.navireader(opts)
  navireader_picker(opts)
end

function M.search(opts)
  vim.ui.input({ prompt = "Search RSS articles: " }, function(query)
    if query then
      navireader_picker(vim.tbl_extend("force", opts or {}, { query = query }))
    end
  end)
end

function M.starred(opts)
  local articles_module = require("navireader.articles")
  local all_articles = articles_module.get_articles()
  local starred = {}

  for _, article in ipairs(all_articles) do
    if article.starred then
      table.insert(starred, article)
    end
  end

  if #starred == 0 then
    vim.notify("No starred articles", vim.log.levels.INFO)
    return
  end

  opts = opts or {}
  opts.prompt_title = "Starred Articles"
  navireader_picker(vim.tbl_extend("force", opts, { articles = starred }))
end

return require("telescope").register_extension({
  setup = function(ext_config, config)
    -- Extension setup if needed
  end,
  exports = {
    navireader = M.navireader,
    search = M.search,
    starred = M.starred,
  },
})