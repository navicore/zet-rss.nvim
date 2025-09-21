local M = {}

-- Don't initialize config with io.popen at module load time - this can cause race conditions
local config = {
  navireader_path = nil,
  zet_path = nil,
  navireader_bin = nil,
}

-- Track if we've already set up
local is_setup = false

function M.setup(opts)
  -- Prevent double setup
  if is_setup then
    return
  end
  is_setup = true

  -- Merge options first, before any I/O operations
  opts = opts or {}

  -- Set defaults using simple string operations - no I/O yet
  local defaults = {
    navireader_path = vim.fn.expand("~") .. "/.navireader",
    zet_path = nil,  -- Will be set lazily
    navireader_bin = nil,  -- Will be found lazily
  }

  config = vim.tbl_deep_extend("force", defaults, opts)

  -- Create commands - do this synchronously to ensure they exist
  -- Check if commands already exist to avoid errors
  if vim.fn.exists(":NaviReaderScan") == 0 then
    vim.api.nvim_create_user_command("NaviReaderScan", function() M.scan() end,
      { desc = "Scan Zettelkasten for RSS feed URLs" })
  end

  if vim.fn.exists(":NaviReaderFetch") == 0 then
    vim.api.nvim_create_user_command("NaviReaderFetch", function() M.fetch() end,
      { desc = "Fetch RSS articles from all feeds" })
  end

  if vim.fn.exists(":NaviReaderUpdate") == 0 then
    vim.api.nvim_create_user_command("NaviReaderUpdate", function() M.fetch(true) end,
      { desc = "Rescan Zettelkasten and fetch new articles" })
  end

  -- Defer Telescope extension loading to avoid conflicts
  vim.defer_fn(function()
    local ok, telescope = pcall(require, 'telescope')
    if ok then
      pcall(telescope.load_extension, telescope, 'navireader')
    end
  end, 0)

  -- Defer all I/O operations to when they're actually needed
  -- This avoids blocking during setup
end

-- Lazy initialization of paths and binary
local function ensure_initialized()
  -- Lazy init zet_path
  if not config.zet_path then
    local username = vim.fn.system("whoami"):gsub("\n", "")
    config.zet_path = vim.fn.expand("~/git/" .. username .. "/zet")
  end

  -- Lazy find binary
  if not config.navireader_bin then
    local plugin_path = debug.getinfo(1).source:match("@?(.*/)") or ""
    local binary_path = plugin_path:gsub("/navireader/", "/navireader/bin/navireader")

    if vim.fn.executable(binary_path) == 1 then
      config.navireader_bin = binary_path
    else
      -- Try system PATH
      local which_result = vim.fn.system("which navireader 2>/dev/null"):gsub("\n", "")
      if which_result ~= "" then
        config.navireader_bin = which_result
      end
    end
  end

  return config.navireader_bin ~= nil
end

function M.scan()
  if not is_setup then
    vim.notify("NaviReader: Please run :lua require('navireader').setup() first", vim.log.levels.ERROR)
    return
  end

  -- Ensure paths and binary are initialized (lazy)
  if not ensure_initialized() then
    vim.notify("navireader binary not found! Please build it with 'make build' in plugin directory", vim.log.levels.ERROR)
    return
  end

  local cmd = string.format("%s scan --path %s", config.navireader_bin, vim.fn.shellescape(config.zet_path))

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
  if not is_setup then
    vim.notify("NaviReader: Please run :lua require('navireader').setup() first", vim.log.levels.ERROR)
    return
  end

  -- Ensure paths and binary are initialized (lazy)
  if not ensure_initialized() then
    vim.notify("navireader binary not found! Please build it with 'make build' in plugin directory", vim.log.levels.ERROR)
    return
  end

  local cmd = config.navireader_bin .. " fetch"
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

function M.get_config()
  return config
end

-- Debug function to check if commands exist
function M.debug()
  local info = {
    "NaviReader Debug Info:",
    "  Setup complete: " .. tostring(is_setup),
    "  Commands registered:",
    "    :NaviReaderScan exists = " .. vim.fn.exists(":NaviReaderScan"),
    "    :NaviReaderFetch exists = " .. vim.fn.exists(":NaviReaderFetch"),
    "    :NaviReaderUpdate exists = " .. vim.fn.exists(":NaviReaderUpdate"),
    "  Config:",
    "    navireader_path: " .. tostring(config.navireader_path),
    "    zet_path: " .. tostring(config.zet_path),
    "    navireader_bin: " .. tostring(config.navireader_bin),
  }

  -- Show in a floating window so it's clearly visible
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, info)

  local width = 60
  local height = #info
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    border = "rounded",
    style = "minimal",
  })

  -- Close on any key press
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })

  -- Also notify the key info
  if vim.fn.exists(":NaviReaderScan") == 0 then
    vim.notify("NaviReader commands NOT registered!", vim.log.levels.ERROR)
  else
    vim.notify("NaviReader commands are registered", vim.log.levels.INFO)
  end
end

return M