#!/bin/bash

echo "Clearing NaviReader cache..."

# Clear Neovim data directory
if [ -d "$HOME/.local/share/nvim/navireader" ]; then
    echo "Removing: $HOME/.local/share/nvim/navireader"
    rm -rf "$HOME/.local/share/nvim/navireader"
fi

# Clear fallback directory
if [ -d "$HOME/.local/share/navireader" ]; then
    echo "Removing: $HOME/.local/share/navireader"
    rm -rf "$HOME/.local/share/navireader"
fi

# Clear old location if it exists
if [ -d "$HOME/.navireader" ]; then
    echo "Removing old cache: $HOME/.navireader"
    rm -rf "$HOME/.navireader"
fi

echo "Cache cleared! Run :NaviReaderFetch to get fresh articles."