# Makefile for envr - Environment file manager
# Builds release artifacts for GitHub releases

APP_NAME := envr
VERSION := $(shell grep 'version = ' flake.nix | head -1 | sed 's/.*version = "\(.*\)";/\1/')
BUILD_DIR := builds

# Binary names
LINUX_AMD64_BIN := $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-linux-amd64
LINUX_ARM64_BIN := $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-linux-arm64
DARWIN_ARM64_BIN := $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-darwin-arm64

.PHONY: all clean cleanall build-linux build-darwin compress release help

# Default target
all: release clean

# Create build directory
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Generate version.odin from flake.nix
version.odin:
	@echo 'Generating version.odin (v$(VERSION))...'
	@printf 'package main\n\nVERSION :: "$(VERSION)"\n' > version.odin

# Build Linux AMD64
$(LINUX_AMD64_BIN): version.odin $(BUILD_DIR)
	@echo "Building for Linux AMD64..."
	odin build . -target:linux_amd64 -o:speed -out:$(LINUX_AMD64_BIN)
	@echo "Built $(LINUX_AMD64_BIN)"

# Build Linux ARM64
$(LINUX_ARM64_BIN): version.odin $(BUILD_DIR)
	@echo "Building for Linux ARM64..."
	odin build . -target:linux_arm64 -o:speed -out:$(LINUX_ARM64_BIN)
	@echo "Built $(LINUX_ARM64_BIN)"

# Build Darwin ARM64 (Mac)
$(DARWIN_ARM64_BIN): version.odin $(BUILD_DIR)
	@echo "Building for Darwin ARM64..."
	odin build . -target:darwin_arm64 -o:speed -out:$(DARWIN_ARM64_BIN)
	@echo "Built $(DARWIN_ARM64_BIN)"

# Build all binaries
build-linux: $(LINUX_AMD64_BIN) # $(LINUX_ARM64_BIN)
build-darwin: $(DARWIN_ARM64_BIN)

# Compress Linux artifacts with gzip
$(BUILD_DIR)/$(APP_NAME)-$(VERSION)-linux-amd64.tar.gz: $(LINUX_AMD64_BIN)
	@echo "Compressing Linux AMD64 artifact..."
	cd $(BUILD_DIR) && tar -czf $(APP_NAME)-$(VERSION)-linux-amd64.tar.gz --transform 's|.*|$(APP_NAME)|' $(shell basename $(LINUX_AMD64_BIN))

$(BUILD_DIR)/$(APP_NAME)-$(VERSION)-linux-arm64.tar.gz: $(LINUX_ARM64_BIN)
	@echo "Compressing Linux ARM64 artifact..."
	cd $(BUILD_DIR) && tar -czf $(APP_NAME)-$(VERSION)-linux-arm64.tar.gz --transform 's|.*|$(APP_NAME)|' $(shell basename $(LINUX_ARM64_BIN))

# Compress Darwin artifacts with zip
$(BUILD_DIR)/$(APP_NAME)-$(VERSION)-darwin-arm64.zip: $(DARWIN_ARM64_BIN)
	@echo "Compressing Darwin ARM64 artifact..."
	cd $(BUILD_DIR) && cp $(shell basename $(DARWIN_ARM64_BIN)) $(APP_NAME) && zip $(APP_NAME)-$(VERSION)-darwin-arm64.zip $(APP_NAME) && rm $(APP_NAME)

# Compress all artifacts
compress: $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-linux-amd64.tar.gz \
          # $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-linux-arm64.tar.gz \
          # $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-darwin-arm64.zip

# Build and compress all release artifacts
# release: build-linux build-darwin compress
release: build-linux compress
	@echo "Release artifacts created:"
	@ls -la $(BUILD_DIR)/*.tar.gz $(BUILD_DIR)/*.zip 2>/dev/null || echo "No compressed artifacts found"

# Clean binary files only
clean:
	@echo "Cleaning binary files..."
	@rm -f $(LINUX_AMD64_BIN) $(LINUX_ARM64_BIN) $(DARWIN_ARM64_BIN)

# Clean everything in build directory
cleanall:
	@echo "Cleaning build directory..."
	@rm -rf $(BUILD_DIR)

# Show available targets
help:
	@echo "Available targets:"
	@echo "  all         - Build all release artifacts (default)"
	@echo "  release     - Build and compress all release artifacts"
	@echo "  build-linux  - Build Linux binaries only"
	@echo "  build-darwin - Build Darwin binaries only"
	@echo "  compress    - Compress all built binaries"
	@echo "  clean       - Remove binary files only"
	@echo "  cleanall    - Remove entire build directory"
	@echo "  help        - Show this help message"
	@echo ""
	@echo "Release artifacts will be created in $(BUILD_DIR)/"
	@echo "Version: $(VERSION)"
