local M = {}

local config = {
  navireader_path = vim.fn.expand("~") .. "/.navireader",
  zet_path = vim.fn.expand("~/git/" .. io.popen("whoami"):read("*a"):gsub("\n", "") .. "/zet"),
  navireader_bin = nil, -- will search in PATH if not specified
}

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  -- Find navireader binary in plugin's bin directory
  if not config.navireader_bin then
    local plugin_path = debug.getinfo(1).source:match("@?(.*/)") or ""
    local binary_path = plugin_path .. "bin/navireader"

    -- Check if binary exists, if not, try to build it
    if vim.fn.executable(binary_path) == 0 then
      local plugin_root = plugin_path:gsub("/lua/navireader/$", "")
      vim.notify("NaviReader: Building Rust binary...", vim.log.levels.INFO)
      local result = vim.fn.system("cd " .. vim.fn.shellescape(plugin_root) .. " && make build 2>&1")
      if vim.v.shell_error ~= 0 then
        vim.notify("NaviReader: Build failed. Please run 'make build' in plugin directory.", vim.log.levels.ERROR)
        return
      end
    end

    if vim.fn.executable(binary_path) == 1 then
      config.navireader_bin = vim.fn.expand(binary_path)
    else
      -- Fallback to system PATH
      local handle = io.popen("which navireader 2>/dev/null")
      local result = handle:read("*a")
      handle:close()
      config.navireader_bin = result:gsub("\n", "")

      if config.navireader_bin == "" then
        vim.notify("NaviReader: Binary not found. Please ensure it's built.", vim.log.levels.ERROR)
        return
      end
    end
  end

  -- Create commands
  vim.api.nvim_create_user_command("NaviReaderScan", function()
    M.scan()
  end, { desc = "Scan Zettelkasten for RSS feed URLs" })

  vim.api.nvim_create_user_command("NaviReaderFetch", function()
    M.fetch()
  end, { desc = "Fetch RSS articles from all feeds" })

  vim.api.nvim_create_user_command("NaviReaderUpdate", function()
    M.fetch(true)
  end, { desc = "Rescan Zettelkasten and fetch new articles" })

  -- Load Telescope extension if available
  local ok, telescope = pcall(require, 'telescope')
  if ok then
    telescope.load_extension('navireader')
  end
end

function M.scan()
  if not config.navireader_bin or config.navireader_bin == "" then
    vim.notify("navireader binary not found! Please build it with 'cargo build --release'", vim.log.levels.ERROR)
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
  if not config.navireader_bin or config.navireader_bin == "" then
    vim.notify("navireader binary not found! Please build it with 'cargo build --release'", vim.log.levels.ERROR)
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