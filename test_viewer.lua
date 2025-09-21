-- Test navireader viewer in floating window
local function test_viewer()
  local buf = vim.api.nvim_create_buf(false, true)

  local width = 120
  local height = 40
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = ' Test Viewer ',
    title_pos = 'center',
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Get first article ID
  local articles = require("navireader.articles").get_articles(1)
  if #articles == 0 then
    vim.notify("No articles found", vim.log.levels.ERROR)
    return
  end

  local cmd = "./bin/navireader view --id " .. vim.fn.shellescape(articles[1].id)

  print("Running command: " .. cmd)

  local job_id = vim.fn.termopen(cmd, {
    on_exit = function(job, exit_code)
      print("Terminal exited with code: " .. exit_code)
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end)
    end,
  })

  print("Job ID: " .. (job_id or "nil"))

  vim.cmd('startinsert')

  -- Add escape mapping
  vim.api.nvim_buf_set_keymap(buf, 't', '<Esc>', '<C-\\><C-n>', { noremap = true })
end

vim.api.nvim_create_user_command('TestViewer', test_viewer, {})

print("Run :TestViewer to test")