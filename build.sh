#!/bin/sh
set -e
echo "zet-rss.nvim: building Rust binary..."
cargo build --release 2>&1
mkdir -p lua/zetrss/bin
cp target/release/zetrss lua/zetrss/bin/
echo "zet-rss.nvim: build complete"
