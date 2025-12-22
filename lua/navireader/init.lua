local M = {}

local config = {
  navireader_path = vim.fn.stdpath("data") .. "/navireader",
  zet_path = nil,
  navireader_bin = nil,
}

function M.setup(opts)
  -- Wrap everything in pcall to catch any errors
  local ok, err = pcall(function()
    opts = opts or {}

    -- Get username and set default zet path
    local username = vim.fn.system("whoami"):gsub("\n", "")
    local defaults = {
      navireader_path = vim.fn.stdpath("data") .. "/navireader",
      zet_path = vim.fn.expand("~/git/" .. username .. "/zet"),
      navireader_bin = nil,
    }

    config = vim.tbl_deep_extend("force", defaults, opts)

  -- Find binary
  local plugin_path = debug.getinfo(1).source:match("@?(.*/)") or ""
  local binary_path = plugin_path .. "bin/navireader"

  if vim.fn.executable(binary_path) == 1 then
    config.navireader_bin = binary_path
  else
    -- Try system PATH
    local which_result = vim.fn.system("which navireader 2>/dev/null"):gsub("\n", "")
    if which_result ~= "" then
      config.navireader_bin = which_result
    end
  end

  -- Create main command with subcommands
  vim.api.nvim_create_user_command("NaviReader", function(opts)
    local subcommand = opts.args

    if subcommand == "" or subcommand == "browse" then
      -- Default action: browse unread articles
      require('telescope').extensions.navireader.navireader()
    elseif subcommand == "scan" then
      M.scan()
    elseif subcommand == "fetch" then
      M.fetch()
    elseif subcommand == "update" then
      M.fetch(true)
    elseif subcommand == "all" then
      require('telescope').extensions.navireader.all()
    elseif subcommand == "search" then
      require('telescope').extensions.navireader.search()
    elseif subcommand == "starred" then
      require('telescope').extensions.navireader.starred()
    elseif subcommand == "feeds" then
      require('telescope').extensions.navireader.feeds()
    elseif subcommand == "browse-feeds" then
      require('telescope').extensions.navireader.browse_feeds()
    elseif subcommand == "clear-cache" then
      M.clear_cache()
    elseif subcommand == "mark-all-read" then
      M.mark_all_read()
    else
      vim.notify("Unknown subcommand: " .. subcommand .. "\n\nAvailable subcommands:\n" ..
        "  browse (default) - Browse unread articles\n" ..
        "  all              - Browse all articles (including read)\n" ..
        "  search           - Search articles\n" ..
        "  starred          - Browse starred articles\n" ..
        "  feeds            - List scanned RSS feeds\n" ..
        "  browse-feeds     - Browse articles by feed\n" ..
        "  scan             - Scan Zettelkasten for RSS feeds\n" ..
        "  fetch            - Fetch RSS articles\n" ..
        "  update           - Rescan and fetch new articles\n" ..
        "  mark-all-read    - Mark all unread articles as read\n" ..
        "  clear-cache      - Clear all cached data",
        vim.log.levels.ERROR)
    end
  end, {
    nargs = "?",
    complete = function(arg_lead, cmd_line, cursor_pos)
      return vim.tbl_filter(function(item)
        return vim.startswith(item, arg_lead)
      end, {
        "browse",
        "all",
        "search",
        "starred",
        "feeds",
        "browse-feeds",
        "scan",
        "fetch",
        "update",
        "mark-all-read",
        "clear-cache"
      })
    end,
    desc = "NaviReader RSS reader commands"
  })

    -- Don't load Telescope extension in setup - let user do it manually
    -- This might be causing conflicts with markdown files
    -- local ok, telescope = pcall(require, 'telescope')
    -- if ok then
    --   telescope.load_extension('navireader')
    -- end
  end)

  if not ok then
    vim.notify("NaviReader setup failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.scan()
  if not config.navireader_bin then
    vim.notify("navireader binary not found! Please build it with 'make build' in plugin directory", vim.log.levels.ERROR)
    return
  end

  -- Use env command to set environment variable
  local cmd = string.format("env NAVIREADER_DATA_DIR=%s %s scan --path %s",
    vim.fn.shellescape(config.navireader_path),
    config.navireader_bin,
    vim.fn.shellescape(config.zet_path))

  vim.notify("Scanning for RSS feeds...", vim.log.levels.INFO)

  vim.fn.jobstart(cmd, {
    on_exit = function(_, code)
      if code == 0 then
        vim.notify("RSS feed scan completed!", vim.log.levels.INFO)
      else
        vim.notify("RSS feed scan failed!", vim.log.levels.ERROR)
      end
    end,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          print(line)
        end
      end
    end,
  })
end

function M.fetch(update)
  if not config.navireader_bin then
    vim.notify("navireader binary not found! Please build it with 'make build' in plugin directory", vim.log.levels.ERROR)
    return
  end

  -- Use env command to set environment variable
  local cmd = string.format("env NAVIREADER_DATA_DIR=%s %s fetch",
    vim.fn.shellescape(config.navireader_path),
    config.navireader_bin)
  if update then
    cmd = cmd .. " --update"
  end

  vim.notify("Fetching RSS feeds...", vim.log.levels.INFO)

  vim.fn.jobstart(cmd, {
    on_exit = function(_, code)
      if code == 0 then
        vim.notify("RSS feeds fetched successfully!", vim.log.levels.INFO)
      else
        vim.notify("Failed to fetch RSS feeds!", vim.log.levels.ERROR)
      end
    end,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" and (line:match("✓") or line:match("✗")) then
          print(line)
        end
      end
    end,
  })
end

function M.mark_all_read()
  -- Count unread articles first
  local articles = require("navireader.articles")
  local all_articles = articles.get_articles(nil, {show_read = false})
  local unread_count = 0

  for _, article in ipairs(all_articles) do
    if not article.read then
      unread_count = unread_count + 1
    end
  end

  if unread_count == 0 then
    vim.notify("No unread articles to mark as read.", vim.log.levels.INFO)
    return
  end

  -- Confirm with user
  local message = string.format(
    "Mark %d unread articles as read? (y/N): ",
    unread_count
  )

  vim.ui.input({ prompt = message }, function(input)
    if input and (input:lower() == "y" or input:lower() == "yes") then
      -- Call the Rust backend to mark all as read
      local binary = config.navireader_bin or "navireader"
      local cmd = string.format("env NAVIREADER_DATA_DIR=%s %s mark-all-read 2>&1",
        vim.fn.shellescape(config.navireader_path),
        binary)

      local result = vim.fn.system(cmd)

      if vim.v.shell_error == 0 then
        vim.notify(string.format("Marked %d articles as read.", unread_count), vim.log.levels.INFO)
      else
        vim.notify("Failed to mark articles as read: " .. result, vim.log.levels.ERROR)
      end
    else
      vim.notify("Cancelled.", vim.log.levels.INFO)
    end
  end)
end

function M.clear_cache()
  -- Get article count for informative message
  local articles_dir = config.navireader_path .. "/articles"
  local count = 0
  local handle = io.popen("ls " .. vim.fn.shellescape(articles_dir) .. "/*.md 2>/dev/null | wc -l")
  if handle then
    count = tonumber(handle:read("*a")) or 0
    handle:close()
  end

  local message = string.format(
    "This will delete:\n• %d cached articles\n• All feed metadata\n• Scan results\n\nAre you sure? (y/N): ",
    count
  )

  vim.ui.input({ prompt = message }, function(input)
    if input and (input:lower() == "y" or input:lower() == "yes") then
      -- Clear the directories
      local paths = {
        config.navireader_path,
        vim.fn.expand("~/.local/share/navireader"),  -- Fallback location
        vim.fn.expand("~/.navireader"),  -- Old location if it exists
      }

      local cleared = false
      for _, path in ipairs(paths) do
        if vim.fn.isdirectory(path) == 1 then
          vim.fn.delete(path, "rf")
          cleared = true
        end
      end

      if cleared then
        vim.notify("NaviReader cache cleared! Run :NaviReaderScan and :NaviReaderFetch to get fresh articles.", vim.log.levels.INFO)
      else
        vim.notify("No cache found to clear.", vim.log.levels.WARN)
      end
    else
      vim.notify("Cache clear cancelled.", vim.log.levels.INFO)
    end
  end)
end

function M.get_config()
  return config
end

return M