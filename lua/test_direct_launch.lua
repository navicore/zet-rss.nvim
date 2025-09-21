-- Test launching viewer directly without Telescope
local function launch_viewer_test()
  -- Get first article
  local articles = require("navireader.articles").get_articles(1)
  if #articles == 0 then
    vim.notify("No articles found", vim.log.levels.ERROR)
    return
  end

  local article = articles[1]
  local navireader = require("navireader")
  local config = navireader.get_config()

  -- Build command
  local binary = config.navireader_bin or "navireader"
  local cmd = string.format("%s view --id %s", binary, vim.fn.shellescape(article.id))

  print("Command: " .. cmd)

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
end

vim.api.nvim_create_user_command('TestDirectLaunch', launch_viewer_test, {})

print("Run :TestDirectLaunch to test viewer without Telescope")