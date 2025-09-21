.PHONY: install build clean

BINARY_NAME = navireader
INSTALL_DIR = lua/navireader/bin

install: build
	@echo "NaviReader installed successfully!"

build:
	@echo "Building NaviReader..."
	@cargo build --release --quiet 2>/dev/null || cargo build --release
	@mkdir -p $(INSTALL_DIR)
	@cp target/release/$(BINARY_NAME) $(INSTALL_DIR)/
	@echo "Binary installed to $(INSTALL_DIR)/"

clean:
	@cargo clean
	@rm -rf $(INSTALL_DIR)

test:
	@cargo test