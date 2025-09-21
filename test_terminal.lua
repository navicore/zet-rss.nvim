-- Test terminal input in floating window
local function test_terminal()
  local buf = vim.api.nvim_create_buf(false, true)

  local width = 80
  local height = 24
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
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Test with a simple command that accepts input
  local job_id = vim.fn.termopen('bash -c "echo Press any key to test input && read -n1 && echo You pressed a key!"', {
    on_exit = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end)
    end,
  })

  vim.cmd('startinsert')
end

vim.api.nvim_create_user_command('TestTerminal', test_terminal, {})

print("Run :TestTerminal to test")