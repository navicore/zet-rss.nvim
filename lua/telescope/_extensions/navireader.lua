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
  local picker_type = opts.picker_type or "unread"

  local articles_module = require("navireader.articles")
  local articles

  if opts.query and opts.query ~= "" then
    articles = articles_module.search_articles(opts.query)
  elseif opts.feed_url then
    -- Filter by specific feed
    local article_opts = {
      show_read = opts.show_read or false
    }
    articles = articles_module.get_articles_by_feed(opts.feed_url, article_opts)
  else
    -- Pass options for filtering
    local article_opts = {
      show_read = opts.show_read or false  -- Default to hiding read items
    }
    articles = articles_module.get_articles(opts.limit or 100, article_opts)
  end

  if #articles == 0 then
    local msg = opts.feed_url and "No unread articles for this feed." or "No articles found. Run :NaviReaderFetch to fetch RSS feeds."
    vim.notify(msg, vim.log.levels.WARN)
    return
  end

  local prompt_title = opts.prompt_title or "NaviReader RSS Articles"

  pickers.new(opts, {
    prompt_title = prompt_title,
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
        table.insert(lines, "Source: " .. (article.feed or "Unknown"))
        if article.author and article.author ~= "" then
          table.insert(lines, "Author: " .. article.author)
        end
        if article.published then
          table.insert(lines, "Date: " .. article.published)
        end
        table.insert(lines, "---")
        table.insert(lines, "")

        -- Process content
        if article.content then
          local content = article.content

          -- Clean up the content
          content = content:gsub("^# [^\n]+\n*", "")  -- Remove duplicate title
          content = content:gsub("%[Read original%][^\n]*\n*$", "")  -- Remove read link
          content = content:gsub("^%s+", ""):gsub("%s+$", "")  -- Trim

          -- Get preview width for wrapping
          local preview_width = vim.api.nvim_win_get_width(self.state.winid) - 6

          -- Process line by line
          local in_blank = false
          for line in content:gmatch("([^\n]*)\n?") do
            -- Skip multiple blank lines
            if line:match("^%s*$") then
              if not in_blank then
                table.insert(lines, "")
                in_blank = true
              end
            else
              in_blank = false

              -- Wrap long lines
              line = line:gsub("^%s+", ""):gsub("%s+$", "")  -- Trim line

              if #line > 0 then
                if #line <= preview_width then
                  table.insert(lines, line)
                else
                  -- Wrap the line
                  local pos = 1
                  while pos <= #line do
                    local end_pos = math.min(pos + preview_width - 1, #line)

                    -- Try to break at word boundary
                    if end_pos < #line then
                      for i = end_pos, pos + math.floor(preview_width * 0.7), -1 do
                        if line:sub(i, i):match("[%s%p]") then
                          end_pos = i
                          break
                        end
                      end
                    end

                    local segment = line:sub(pos, end_pos):gsub("^%s+", "")
                    if #segment > 0 then
                      table.insert(lines, segment)
                    end
                    pos = end_pos + 1
                  end
                end
              end
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

        -- Build command with environment variable using env command
        local binary = config.navireader_bin or "navireader"
        -- Generate unique session ID for temp file coordination
        local session_id = vim.fn.system("uuidgen"):gsub("\n", "")
        if session_id == "" then
          -- Fallback if uuidgen is not available
          session_id = tostring(os.time()) .. "-" .. tostring(math.random(1000000))
        end
        local cmd = string.format("env NAVIREADER_DATA_DIR=%s NAVIREADER_SESSION_ID=%s %s view --id %s",
          vim.fn.shellescape(config.navireader_path),
          vim.fn.shellescape(session_id),
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

          -- Create autocommand group for cleanup
          local augroup_name = "NaviReaderTerminal_" .. buf
          local ok, augroup = pcall(vim.api.nvim_create_augroup, augroup_name, { clear = true })

          if not ok then
            vim.notify("NaviReader: Failed to create augroup: " .. tostring(augroup), vim.log.levels.ERROR)
          else
            -- Set up autocommand to re-enter terminal mode when window gains focus
            local ok_winenter, err_winenter = pcall(vim.api.nvim_create_autocmd, "WinEnter", {
              group = augroup,
              buffer = buf,
              callback = function()
                if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() == win then
                  vim.cmd('startinsert')
                end
              end,
            })
            if not ok_winenter then
              vim.notify("NaviReader: Failed to create WinEnter autocmd: " .. tostring(err_winenter), vim.log.levels.ERROR)
            end

            -- Also handle FocusGained for when returning from another desktop
            local ok_focus, err_focus = pcall(vim.api.nvim_create_autocmd, "FocusGained", {
              group = augroup,
              buffer = buf,
              callback = function()
                if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() == win then
                  vim.cmd('startinsert')
                end
              end,
            })
            if not ok_focus then
              vim.notify("NaviReader: Failed to create FocusGained autocmd: " .. tostring(err_focus), vim.log.levels.ERROR)
            end
          end

          -- Start terminal
          local ok_term, job_id = pcall(vim.fn.termopen, cmd, {
            on_exit = function(_, exit_code)
              vim.schedule(function()
                -- Clean up autocommands
                pcall(vim.api.nvim_del_augroup_by_name, augroup_name)

                if vim.api.nvim_win_is_valid(win) then
                  vim.api.nvim_win_close(win, true)
                end

                -- Handle exit codes
                if exit_code == 0 then
                  -- Normal exit - reopen Telescope
                  vim.defer_fn(function()
                    if picker_type == "all" then
                      require('telescope').extensions.navireader.all()
                    elseif picker_type == "starred" then
                      require('telescope').extensions.navireader.starred()
                    elseif picker_type == "search" then
                      require('telescope').extensions.navireader.search()
                    else
                      require('telescope').extensions.navireader.navireader()
                    end
                  end, 50)
                elseif exit_code == 1 then
                  -- Open browser
                  -- Use session-specific temp file
                  local temp_dir = vim.fn.tempname():match("^(.*/)") or "/tmp/"
                  local temp_file_path = temp_dir .. "navireader_open_url_" .. session_id .. ".txt"
                  local url_file = io.open(temp_file_path, "r")
                  if url_file then
                    local url = url_file:read("*a")
                    url_file:close()
                    -- Clean up temp file after reading
                    os.remove(temp_file_path)
                    vim.fn.system("open " .. vim.fn.shellescape(url))
                  end
                elseif exit_code == 2 then
                  -- Open note
                  -- Use session-specific temp file
                  local temp_dir = vim.fn.tempname():match("^(.*/)") or "/tmp/"
                  local temp_file_path = temp_dir .. "navireader_note_path_" .. session_id .. ".txt"
                  local note_file = io.open(temp_file_path, "r")
                  if note_file then
                    local note_path = note_file:read("*a")
                    note_file:close()
                    -- Clean up temp file after reading
                    os.remove(temp_file_path)
                    vim.cmd("edit " .. vim.fn.fnameescape(note_path))
                  end
                end
              end)
            end
          })

          if not ok_term then
            vim.notify("NaviReader: Failed to start terminal: " .. tostring(job_id), vim.log.levels.ERROR)
            if vim.api.nvim_win_is_valid(win) then
              vim.api.nvim_win_close(win, true)
            end
            return
          end

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
  navireader_picker(vim.tbl_extend("force", opts, { articles = starred, picker_type = "starred" }))
end

function M.feeds(opts)
  opts = opts or {}

  local articles_module = require("navireader.articles")
  local feeds = articles_module.get_feeds()

  if #feeds == 0 then
    vim.notify("No feeds found. Run :NaviReader scan first.", vim.log.levels.WARN)
    return
  end

  pickers.new(opts, {
    prompt_title = "NaviReader RSS Feeds",
    finder = finders.new_table({
      results = feeds,
      entry_maker = function(feed)
        -- Extract domain from URL for display
        local domain = feed.url:match("https?://([^/]+)") or feed.url
        -- Get just the filename from source_file
        local source_name = feed.source_file:match("([^/]+)$") or feed.source_file

        return {
          value = feed,
          display = string.format("%s  (%s)", domain, source_name),
          ordinal = feed.url .. " " .. domain .. " " .. feed.source_file,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_buffer_previewer({
      title = "Feed Info",
      define_preview = function(self, entry)
        local feed = entry.value
        local lines = {}

        -- Extract domain
        local domain = feed.url:match("https?://([^/]+)") or "Unknown"

        table.insert(lines, "# " .. domain)
        table.insert(lines, "")
        table.insert(lines, "**URL:** " .. feed.url)
        table.insert(lines, "")
        table.insert(lines, "**Source File:** " .. feed.source_file)
        table.insert(lines, "")
        table.insert(lines, "**Line:** " .. tostring(feed.line_number))
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "")
        table.insert(lines, "Press <Enter> to open the source file")

        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      -- Open source file on Enter
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if not selection then
          return
        end

        local feed = selection.value
        actions.close(prompt_bufnr)

        -- Open the source file at the line number
        if feed.source_file and feed.source_file ~= "" then
          vim.cmd("edit " .. vim.fn.fnameescape(feed.source_file))
          if feed.line_number and feed.line_number > 0 then
            vim.api.nvim_win_set_cursor(0, { feed.line_number, 0 })
            vim.cmd("normal! zz")  -- Center the line
          end
        else
          vim.notify("No source file information available for this feed", vim.log.levels.WARN)
        end
      end)

      return true
    end,
  }):find()
end

function M.browse_feeds(opts)
  opts = opts or {}

  local articles_module = require("navireader.articles")
  local feeds = articles_module.get_feeds_with_stats()

  if #feeds == 0 then
    vim.notify("No feeds found. Run :NaviReader scan first.", vim.log.levels.WARN)
    return
  end

  -- Sort feeds by unread count (most unread first)
  table.sort(feeds, function(a, b)
    return a.unread > b.unread
  end)

  pickers.new(opts, {
    prompt_title = "Browse Feeds",
    finder = finders.new_table({
      results = feeds,
      entry_maker = function(feed)
        local domain = feed.url:match("https?://([^/]+)") or feed.url
        local unread_indicator = feed.unread > 0 and string.format("(%d unread)", feed.unread) or "(all read)"

        return {
          value = feed,
          display = string.format("%s  %s  [%d total]", domain, unread_indicator, feed.total),
          ordinal = feed.url .. " " .. domain,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_buffer_previewer({
      title = "Feed Info",
      define_preview = function(self, entry)
        local feed = entry.value
        local lines = {}

        local domain = feed.url:match("https?://([^/]+)") or "Unknown"

        table.insert(lines, "# " .. domain)
        table.insert(lines, "")
        table.insert(lines, "**URL:** " .. feed.url)
        table.insert(lines, "")
        table.insert(lines, string.format("**Articles:** %d total, %d unread", feed.total, feed.unread))
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "")
        table.insert(lines, "Press <Enter> to browse articles from this feed")

        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if not selection then
          return
        end

        local feed = selection.value
        local domain = feed.url:match("https?://([^/]+)") or feed.url
        actions.close(prompt_bufnr)

        -- Open article picker filtered to this feed
        vim.defer_fn(function()
          navireader_picker({
            feed_url = feed.url,
            prompt_title = "Articles: " .. domain,
            picker_type = "feed_browse",
          })
        end, 10)
      end)

      return true
    end,
  }):find()
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
    feeds = M.feeds,
    browse_feeds = M.browse_feeds,
  },
})