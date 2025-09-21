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
      -- Custom action to open in TUI viewer
      local open_in_viewer = function(bufnr)
        local selection = action_state.get_selected_entry()
        if not selection then
          return
        end

        local article = selection.value
        local navireader = require("navireader")
        local config = navireader.get_config()

        -- Build command
        local binary = config.navireader_bin or "navireader"
        local cmd = string.format("%s view --id %s", binary, vim.fn.shellescape(article.id))

        -- Save current window before closing telescope
        local original_win = vim.api.nvim_get_current_win()

        -- Close telescope
        actions.close(bufnr)

        -- Open terminal after a short delay to ensure telescope is fully closed
        vim.defer_fn(function()
          -- Create buffer for terminal
          local buf = vim.api.nvim_create_buf(false, true)

          -- Calculate window size
          local width = math.min(120, math.floor(vim.o.columns * 0.9))
          local height = math.min(40, math.floor(vim.o.lines * 0.9))
          local col = math.floor((vim.o.columns - width) / 2)
          local row = math.floor((vim.o.lines - height) / 2)

          -- Open floating window
          local win = vim.api.nvim_open_win(buf, true, {
            relative = "editor",
            width = width,
            height = height,
            col = col,
            row = row,
            style = "minimal",
            border = "rounded",
            title = " RSS Article Viewer ",
            title_pos = "center",
          })

          -- Start terminal
          vim.fn.termopen(cmd, {
            on_exit = function()
              vim.schedule(function()
                if vim.api.nvim_win_is_valid(win) then
                  vim.api.nvim_win_close(win, true)
                end
              end)
            end
          })

          -- Enter insert mode for terminal
          vim.cmd('startinsert')
        end, 10)
      end

      -- Replace default action
      actions.select_default:replace(open_in_viewer)

      -- Keep C-n since you said it works
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