" NaviReader - RSS reader for Neovim
" Maintainer: navicore

if exists('g:loaded_navireader')
  finish
endif
let g:loaded_navireader = 1

" The plugin will be initialized when the user calls require('navireader').setup()
" This allows for proper lazy-loading and configuration