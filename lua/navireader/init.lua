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

    if vim.fn.executable(binary_path) == 1 then
      config.navireader_bin = vim.fn.expand(binary_path)
    else
      -- Fallback to system PATH
      local handle = io.popen("which navireader 2>/dev/null")
      local result = handle:read("*a")
      handle:close()
      config.navireader_bin = result:gsub("\n", "")
    end
  end

  -- Create commands
  vim.api.nvim_create_user_command("NaviReaderScan", function()
    M.scan()
  end, {})

  vim.api.nvim_create_user_command("NaviReaderFetch", function()
    M.fetch()
  end, {})

  vim.api.nvim_create_user_command("NaviReaderUpdate", function()
    M.fetch(true)
  end, {})
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