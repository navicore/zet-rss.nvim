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

  -- Create commands
  vim.api.nvim_create_user_command("NaviReaderScan", function() M.scan() end,
    { desc = "Scan Zettelkasten for RSS feed URLs" })

  vim.api.nvim_create_user_command("NaviReaderFetch", function() M.fetch() end,
    { desc = "Fetch RSS articles from all feeds" })

  vim.api.nvim_create_user_command("NaviReaderUpdate", function() M.fetch(true) end,
    { desc = "Rescan Zettelkasten and fetch new articles" })

  -- Convenience commands for Telescope functions
  vim.api.nvim_create_user_command("NaviReader", function()
    require('telescope').extensions.navireader.navireader()
  end, { desc = "Browse unread RSS articles" })

  vim.api.nvim_create_user_command("NaviReaderAll", function()
    require('telescope').extensions.navireader.all()
  end, { desc = "Browse all RSS articles (including read)" })

  vim.api.nvim_create_user_command("NaviReaderSearch", function()
    require('telescope').extensions.navireader.search()
  end, { desc = "Search RSS articles" })

  vim.api.nvim_create_user_command("NaviReaderStarred", function()
    require('telescope').extensions.navireader.starred()
  end, { desc = "Browse starred RSS articles" })

  vim.api.nvim_create_user_command("NaviReaderClearCache", function()
    M.clear_cache()
  end, { desc = "Clear all cached RSS articles and data" })

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