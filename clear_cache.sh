#!/bin/bash

echo "Clearing ZetRss cache..."

# Clear Neovim data directory
if [ -d "$HOME/.local/share/nvim/zetrss" ]; then
    echo "Removing: $HOME/.local/share/nvim/zetrss"
    rm -rf "$HOME/.local/share/nvim/zetrss"
fi

# Clear fallback directory
if [ -d "$HOME/.local/share/zetrss" ]; then
    echo "Removing: $HOME/.local/share/zetrss"
    rm -rf "$HOME/.local/share/zetrss"
fi

echo "Cache cleared! Run :ZetRss fetch to get fresh articles."