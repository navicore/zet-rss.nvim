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
    -- Pass options for filtering
    local article_opts = {
      show_read = opts.show_read or false  -- Default to hiding read items
    }
    articles = articles_module.get_articles(opts.limit or 100, article_opts)
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

        -- Get preview window width for text wrapping
        local preview_width = vim.api.nvim_win_get_width(self.state.winid) - 4  -- Account for padding

        -- Helper function to wrap text
        local function wrap_text(text, width)
          if not text or text == "" then return {} end

          local wrapped = {}
          for paragraph in text:gmatch("[^\n]+") do
            -- Skip empty lines
            if paragraph:match("^%s*$") then
              if #wrapped > 0 and wrapped[#wrapped] ~= "" then
                table.insert(wrapped, "")
              end
            else
              -- Wrap long lines
              while #paragraph > width do
                local break_point = width
                -- Try to break at a space
                for i = width, 1, -1 do
                  if paragraph:sub(i, i) == " " then
                    break_point = i
                    break
                  end
                end
                table.insert(wrapped, paragraph:sub(1, break_point):gsub("^%s+", ""))
                paragraph = paragraph:sub(break_point + 1)
              end
              if paragraph ~= "" then
                table.insert(wrapped, paragraph:gsub("^%s+", ""))
              end
            end
          end
          return wrapped
        end

        -- Add title (wrapped if necessary)
        local title = article.title or "Untitled"
        if #title > preview_width then
          local title_lines = wrap_text(title, preview_width - 2)  -- Account for "# "
          for i, line in ipairs(title_lines) do
            if i == 1 then
              table.insert(lines, "# " .. line)
            else
              table.insert(lines, "  " .. line)
            end
          end
        else
          table.insert(lines, "# " .. title)
        end
        table.insert(lines, "")

        -- Add metadata
        table.insert(lines, "**Source:** " .. (article.feed or "Unknown"))

        -- Wrap long URLs if needed
        local link = article.link or ""
        if #link > preview_width - 10 then
          table.insert(lines, "**Link:**")
          for _, line in ipairs(wrap_text(link, preview_width - 2)) do
            table.insert(lines, "  " .. line)
          end
        else
          table.insert(lines, "**Link:** " .. link)
        end

        if article.author and article.author ~= "" then
          table.insert(lines, "**Author:** " .. article.author)
        end
        if article.published then
          table.insert(lines, "**Published:** " .. article.published)
        end
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "")

        -- Process and add content
        if article.content then
          -- Clean up content: remove excessive newlines and format
          local content = article.content

          -- Remove markdown title if it duplicates the article title
          content = content:gsub("^# [^\n]+\n*", "")

          -- Remove "Read original" link at the end
          content = content:gsub("%[Read original%][^\n]*\n*$", "")

          -- Collapse multiple newlines into maximum of 2
          content = content:gsub("\n\n\n+", "\n\n")

          -- Wrap the content
          local wrapped_lines = wrap_text(content, preview_width)
          for _, line in ipairs(wrapped_lines) do
            table.insert(lines, line)
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

        -- Build command with environment variable using env command
        local binary = config.navireader_bin or "navireader"
        local cmd = string.format("env NAVIREADER_DATA_DIR=%s %s view --id %s",
          vim.fn.shellescape(config.navireader_path),
          binary,
          vim.fn.shellescape(article.id))

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
            on_exit = function(_, exit_code)
              vim.schedule(function()
                if vim.api.nvim_win_is_valid(win) then
                  vim.api.nvim_win_close(win, true)
                end

                -- Handle exit codes
                if exit_code == 1 then
                  -- Open browser
                  local url_file = io.open("/tmp/navireader_open_url.txt", "r")
                  if url_file then
                    local url = url_file:read("*a")
                    url_file:close()
                    vim.fn.system("open " .. vim.fn.shellescape(url))
                  end
                elseif exit_code == 2 then
                  -- Open note
                  local note_file = io.open("/tmp/navireader_note_path.txt", "r")
                  if note_file then
                    local note_path = note_file:read("*a")
                    note_file:close()
                    vim.cmd("edit " .. vim.fn.fnameescape(note_path))
                  end
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

function M.all(opts)
  -- Show all articles including read ones
  navireader_picker(vim.tbl_extend("force", opts or {}, { show_read = true }))
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
    all = M.all,
    search = M.search,
    starred = M.starred,
  },
})