" NaviReader - RSS reader for Neovim
" Maintainer: navicore

if exists('g:loaded_navireader')
  finish
endif
let g:loaded_navireader = 1

" Auto-compile on first load if binary doesn't exist
lua << EOF
local binary_path = vim.fn.expand(debug.getinfo(1).source:match("@(.*/)").. "../lua/navireader/bin/navireader")
if vim.fn.executable(binary_path) == 0 then
  local plugin_path = vim.fn.expand(debug.getinfo(1).source:match("@(.*/)").. "../")
  vim.notify("NaviReader: First time setup, building Rust binary...", vim.log.levels.INFO)
  local result = vim.fn.system("cd " .. vim.fn.shellescape(plugin_path) .. " && make build 2>&1")
  if vim.v.shell_error == 0 then
    vim.notify("NaviReader: Build complete!", vim.log.levels.INFO)
  else
    vim.notify("NaviReader: Build failed. Please run 'make build' in plugin directory.\n" .. result, vim.log.levels.ERROR)
  end
end
EOF

" Initialize the plugin
lua require('navireader').setup()

" Load Telescope extension if Telescope is available
lua << EOF
local ok, telescope = pcall(require, 'telescope')
if ok then
  telescope.load_extension('navireader')
end
EOF