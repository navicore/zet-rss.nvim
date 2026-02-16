" ZetRss - RSS reader for Neovim
" Maintainer: navicore

if exists('g:loaded_zetrss')
  finish
endif
let g:loaded_zetrss = 1

" The plugin will be initialized when the user calls require('zetrss').setup()
" This allows for proper lazy-loading and configuration