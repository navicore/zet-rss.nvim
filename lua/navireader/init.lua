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

  -- Create commands IMMEDIATELY - before any I/O operations
  -- Commands should always be created, even if binary isn't found yet
  local function create_command(name, func, desc)
    local ok, err = pcall(vim.api.nvim_create_user_command, name, func, { desc = desc })
    if not ok and not err:match("already exists") then
      vim.notify("NaviReader: Failed to create command " .. name .. ": " .. err, vim.log.levels.ERROR)
    end
  end

  create_command("NaviReaderScan", function() M.scan() end,
    "Scan Zettelkasten for RSS feed URLs")

  create_command("NaviReaderFetch", function() M.fetch() end,
    "Fetch RSS articles from all feeds")

  create_command("NaviReaderUpdate", function() M.fetch(true) end,
    "Rescan Zettelkasten and fetch new articles")

  -- Load Telescope extension if available (this is safe, no I/O)
  local ok, telescope = pcall(require, 'telescope')
  if ok then
    telescope.load_extension('navireader')
  end

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

return M