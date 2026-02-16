-- Simplest possible test
vim.api.nvim_create_user_command('TestSimple', function()
  local buf = vim.api.nvim_create_buf(false, true)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = 80,
    height = 24,
    col = 10,
    row = 5,
    style = 'minimal',
    border = 'single',
  })

  -- Test with bash
  vim.fn.termopen('bash', {
    on_exit = function()
      pcall(vim.api.nvim_win_close, win, true)
    end
  })

  vim.cmd('startinsert')
end, {})

vim.api.nvim_create_user_command('TestZetRss', function()
  local buf = vim.api.nvim_create_buf(false, true)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = 120,
    height = 40,
    col = 10,
    row = 5,
    style = 'minimal',
    border = 'single',
  })

  -- Test with zetrss directly
  vim.fn.termopen('./bin/zetrss view --id 20250608-143800-68a4aeb157a8610001cb3f36', {
    on_exit = function()
      pcall(vim.api.nvim_win_close, win, true)
    end
  })

  vim.cmd('startinsert')
end, {})

print("Commands created: :TestSimple and :TestZetRss")