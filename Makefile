# ZEVM Makefile
# Automatically detects OS and installs dependencies, then builds the project

# Detect OS
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Default target
.DEFAULT_GOAL := build

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Build options
BLST_ENABLED ?= true
MCL_ENABLED ?= true
BLST_INCLUDE ?=
MCL_INCLUDE ?=

# Auto-detect blst location - only use /tmp/blst if not installed system-wide
ifeq ($(BLST_INCLUDE),)
	ifeq ($(BLST_ENABLED),true)
		# Check if blst is installed in standard locations first
		ifeq ($(shell test -f /opt/homebrew/include/blst.h && echo yes),yes)
			# Already installed in /opt/homebrew/include/, don't override
		else ifeq ($(shell test -f /opt/homebrew/include/blst/blst.h && echo yes),yes)
			# Already installed in /opt/homebrew/include/blst/, don't override
		else ifeq ($(shell test -f /usr/local/include/blst.h && echo yes),yes)
			# Already installed in /usr/local/include/, don't override
		else ifeq ($(shell test -f /usr/local/include/blst/blst.h && echo yes),yes)
			# Already installed in /usr/local/include/blst/, don't override
		else ifeq ($(shell test -f /tmp/blst/libblst.a && test -f /tmp/blst/bindings/blst.h && echo yes),yes)
			# Use /tmp/blst if it exists and not installed system-wide
			# blst.h is in bindings/, and our code includes <blst.h>, so point to bindings/
			BLST_INCLUDE := /tmp/blst/bindings
		endif
	endif
endif

# Auto-detect mcl location - only use /tmp/mcl if not installed system-wide
ifeq ($(MCL_INCLUDE),)
	ifeq ($(MCL_ENABLED),true)
		# Check if mcl is installed in standard locations first
		ifeq ($(shell test -d /opt/homebrew/include/mcl && echo yes),yes)
			# Already installed in /opt/homebrew/include/mcl, don't override
		else ifeq ($(shell test -d /usr/local/include/mcl && echo yes),yes)
			# Already installed in /usr/local/include/mcl, don't override
		else ifeq ($(shell test -f /tmp/mcl/libmcl.a && echo yes),yes)
			# Use /tmp/mcl if it exists and not installed system-wide
			MCL_INCLUDE := /tmp/mcl/include
		endif
	endif
endif

# Zig build command with options
ZIG_BUILD_CMD := zig build
ifneq ($(BLST_ENABLED),true)
	ZIG_BUILD_CMD += -Dblst=false
endif
ifneq ($(MCL_ENABLED),true)
	ZIG_BUILD_CMD += -Dmcl=false
endif
ifneq ($(BLST_INCLUDE),)
	ZIG_BUILD_CMD += -Dblst-include=$(BLST_INCLUDE)
endif
ifneq ($(MCL_INCLUDE),)
	ZIG_BUILD_CMD += -Dmcl-include=$(MCL_INCLUDE)
endif

# Spec test options
SPEC_TEST_VERSION = v5.4.0
SPEC_TEST_HASH = 4752348fa84215a9bedfa28df049005d0e54d0e41d3c64c88ee64263388237dc
SPEC_TEST_DIR = spec-tests

.PHONY: help install-deps build test clean check-deps install-brew-deps install-apt-deps install-dnf-deps install-vcpkg-deps generate-spec-tests spec-tests

help: ## Show this help message
	@echo "$(BLUE)ZEVM Build System$(NC)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  $(GREEN)build$(NC)          - Build the project (default, installs deps if needed)"
	@echo "  $(GREEN)install-deps$(NC)    - Install required dependencies"
	@echo "  $(GREEN)check-deps$(NC)      - Check if dependencies are installed"
	@echo "  $(GREEN)test$(NC)            - Run tests"
	@echo "  $(GREEN)clean$(NC)           - Clean build artifacts"
	@echo ""
	@echo "Build Options:"
	@echo "  BLST_ENABLED=$(BLST_ENABLED)    - Enable/disable blst (default: true)"
	@echo "  MCL_ENABLED=$(MCL_ENABLED)      - Enable/disable mcl (default: true)"
	@echo "  BLST_INCLUDE=$(BLST_INCLUDE)    - Custom blst include path"
	@echo "  MCL_INCLUDE=$(MCL_INCLUDE)      - Custom mcl include path"
	@echo ""
	@echo "Examples:"
	@echo "  make                    # Build with all dependencies"
	@echo "  make BLST_ENABLED=false # Build without blst"
	@echo "  make install-deps       # Install dependencies only"
	@echo "  make test               # Run tests"

# Check if dependencies are installed
check-deps:
	@echo "$(BLUE)Checking dependencies...$(NC)"
	@command -v zig >/dev/null 2>&1 || (echo "$(RED)✗ Zig is not installed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Zig is installed$(NC)"
	@command -v pkg-config >/dev/null 2>&1 || echo "$(YELLOW)⚠ pkg-config not found (may be needed)$(NC)"
	@BLST_FOUND=0; MCL_FOUND=0; \
	if [ "$(BLST_ENABLED)" = "true" ]; then \
		if pkg-config --exists blst 2>/dev/null; then \
			echo "$(GREEN)✓ blst library found (via pkg-config)$(NC)"; \
			BLST_FOUND=1; \
		elif [ -f /opt/homebrew/lib/libblst.a ] || [ -f /opt/homebrew/lib/libblst.dylib ]; then \
			if [ -f /opt/homebrew/include/blst/blst.h ] || [ -f /opt/homebrew/include/blst.h ]; then \
				echo "$(GREEN)✓ blst library found in /opt/homebrew$(NC)"; \
				BLST_FOUND=1; \
			else \
				echo "$(YELLOW)⚠ blst library found but headers missing$(NC)"; \
			fi \
		elif [ -f /usr/local/lib/libblst.a ] || [ -f /usr/local/lib/libblst.dylib ]; then \
			if [ -f /usr/local/include/blst/blst.h ] || [ -f /usr/local/include/blst.h ]; then \
				echo "$(GREEN)✓ blst library found in /usr/local$(NC)"; \
				BLST_FOUND=1; \
			else \
				echo "$(YELLOW)⚠ blst library found but headers missing$(NC)"; \
			fi \
		elif [ -f /tmp/blst/libblst.a ] && [ -f /tmp/blst/bindings/blst.h ]; then \
			echo "$(GREEN)✓ blst library found in /tmp/blst$(NC)"; \
			echo "$(YELLOW)  Headers at /tmp/blst/bindings/blst.h$(NC)"; \
			BLST_FOUND=1; \
		else \
			echo "$(RED)✗ blst library not found$(NC)"; \
		fi \
	fi; \
	if [ "$(MCL_ENABLED)" = "true" ]; then \
		if pkg-config --exists mcl 2>/dev/null || [ -f /usr/local/lib/libmcl.a ] || [ -f /opt/homebrew/lib/libmcl.a ] || [ -f /usr/lib/libmcl.a ] || [ -f /usr/local/lib/libmcl.dylib ] || [ -f /opt/homebrew/lib/libmcl.dylib ] || [ -f /usr/lib/libmcl.dylib ]; then \
			echo "$(GREEN)✓ mcl library found$(NC)"; \
			MCL_FOUND=1; \
		else \
			echo "$(RED)✗ mcl library not found$(NC)"; \
		fi \
	fi; \
	if [ "$(BLST_ENABLED)" = "true" ] && [ "$$BLST_FOUND" = "0" ]; then \
		echo ""; \
		echo "$(RED)Error: blst library is required but not found.$(NC)"; \
		echo "$(YELLOW)Options:$(NC)"; \
		echo "  1. Install blst: $(BLUE)make install-deps$(NC)"; \
		echo "  2. Build without blst: $(BLUE)make BLST_ENABLED=false$(NC)"; \
		echo "  3. See CROSS_PLATFORM.md for manual installation instructions"; \
		exit 1; \
	fi; \
	if [ "$(MCL_ENABLED)" = "true" ] && [ "$$MCL_FOUND" = "0" ]; then \
		echo ""; \
		echo "$(RED)Error: mcl library is required but not found.$(NC)"; \
		echo "$(YELLOW)Options:$(NC)"; \
		echo "  1. Install mcl: $(BLUE)make install-deps$(NC)"; \
		echo "  2. Build without mcl: $(BLUE)make MCL_ENABLED=false$(NC)"; \
		echo "  3. See CROSS_PLATFORM.md for manual installation instructions"; \
		exit 1; \
	fi

# Install dependencies based on OS
install-deps: check-os
	@echo "$(BLUE)Installing dependencies for $(UNAME_S)...$(NC)"
ifeq ($(UNAME_S),Darwin)
	@$(MAKE) install-brew-deps
else ifeq ($(UNAME_S),Linux)
	@if command -v apt-get >/dev/null 2>&1; then \
		$(MAKE) install-apt-deps; \
	elif command -v dnf >/dev/null 2>&1; then \
		$(MAKE) install-dnf-deps; \
	else \
		echo "$(RED)✗ Unsupported Linux distribution. Please install dependencies manually.$(NC)"; \
		exit 1; \
	fi
else ifeq ($(UNAME_S),MINGW64_NT-10.0)
	@$(MAKE) install-vcpkg-deps
else
	@echo "$(RED)✗ Unsupported OS: $(UNAME_S)$(NC)"
	@echo "Please install dependencies manually. See CROSS_PLATFORM.md for instructions."
	@exit 1
endif

# Check OS and provide helpful message
check-os:
	@echo "$(BLUE)Detected OS: $(UNAME_S) ($(UNAME_M))$(NC)"

# Install dependencies on macOS using Homebrew
install-brew-deps:
	@echo "$(BLUE)Installing dependencies via Homebrew...$(NC)"
	@command -v brew >/dev/null 2>&1 || (echo "$(RED)✗ Homebrew is not installed. Install from https://brew.sh$(NC)" && exit 1)
	@echo "$(GREEN)✓ Homebrew found$(NC)"
	@echo "$(YELLOW)Installing system dependencies...$(NC)"
	@brew install secp256k1 openssl || true
	@if [ "$(BLST_ENABLED)" = "true" ]; then \
		if [ -f /opt/homebrew/lib/libblst.a ] || [ -f /usr/local/lib/libblst.a ] || [ -f /usr/lib/libblst.a ] || [ -f /opt/homebrew/lib/libblst.dylib ] || [ -f /usr/local/lib/libblst.dylib ] || [ -f /usr/lib/libblst.dylib ]; then \
			echo "$(GREEN)✓ blst library already installed$(NC)"; \
		else \
			echo "$(YELLOW)Building blst from source...$(NC)"; \
			if [ ! -d /tmp/blst ]; then \
				cd /tmp && git clone https://github.com/supranational/blst.git || exit 1; \
			fi; \
			cd /tmp/blst && ./build.sh || (echo "$(RED)✗ Failed to build blst$(NC)" && exit 1); \
			if [ ! -f /tmp/blst/bindings/blst.h ]; then \
				echo "$(RED)✗ blst.h not found after build at /tmp/blst/bindings/blst.h$(NC)"; \
				echo "$(YELLOW)Checking /tmp/blst structure...$(NC)"; \
				ls -la /tmp/blst/ 2>/dev/null || true; \
				ls -la /tmp/blst/bindings/ 2>/dev/null || true; \
				exit 1; \
			fi; \
			echo "$(GREEN)✓ blst headers verified at /tmp/blst/bindings/blst.h$(NC)"; \
			echo "$(YELLOW)Installing blst library...$(NC)"; \
			if [ -d /opt/homebrew/lib ] && [ -w /opt/homebrew/lib ]; then \
				cp libblst.a /opt/homebrew/lib/ 2>/dev/null || true; \
				mkdir -p /opt/homebrew/include 2>/dev/null || true; \
				cp bindings/*.h /opt/homebrew/include/ 2>/dev/null || true; \
				if [ -f /opt/homebrew/include/blst.h ]; then \
					echo "$(GREEN)✓ blst installed to /opt/homebrew/include$(NC)"; \
				else \
					echo "$(YELLOW)⚠ Could not install to /opt/homebrew/include, will use /tmp/blst/bindings$(NC)"; \
				fi \
			else \
				sudo cp libblst.a /opt/homebrew/lib/ 2>/dev/null || cp libblst.a /usr/local/lib/ 2>/dev/null || true; \
				sudo mkdir -p /opt/homebrew/include 2>/dev/null || mkdir -p /usr/local/include 2>/dev/null || true; \
				sudo cp bindings/*.h /opt/homebrew/include/ 2>/dev/null || cp bindings/*.h /usr/local/include/ 2>/dev/null || true; \
				if [ -f /opt/homebrew/include/blst.h ] || [ -f /usr/local/include/blst.h ]; then \
					echo "$(GREEN)✓ blst installed$(NC)"; \
				else \
					echo "$(YELLOW)⚠ Could not install headers, will use /tmp/blst/bindings$(NC)"; \
				fi \
			fi; \
			echo "$(GREEN)✓ blst build complete (headers available at /tmp/blst/bindings/blst.h)$(NC)"; \
		fi \
	fi
	@if [ "$(MCL_ENABLED)" = "true" ]; then \
		if [ -f /opt/homebrew/lib/libmcl.a ] || [ -f /usr/local/lib/libmcl.a ] || [ -f /usr/lib/libmcl.a ] || [ -f /opt/homebrew/lib/libmcl.dylib ] || [ -f /usr/local/lib/libmcl.dylib ] || [ -f /usr/lib/libmcl.dylib ]; then \
			echo "$(GREEN)✓ mcl library already installed$(NC)"; \
		else \
			echo "$(YELLOW)Building mcl from source...$(NC)"; \
			if [ ! -d /tmp/mcl ]; then \
				cd /tmp && git clone https://github.com/herumi/mcl.git || exit 1; \
			fi; \
			cd /tmp/mcl && \
			if [ -f Makefile ]; then \
				make -j$$(sysctl -n hw.ncpu 2>/dev/null || echo 4) || (echo "$(RED)✗ Failed to build mcl$(NC)" && exit 1); \
			elif [ -f CMakeLists.txt ]; then \
				mkdir -p build && cd build && \
				cmake .. && make -j$$(sysctl -n hw.ncpu 2>/dev/null || echo 4) || (echo "$(RED)✗ Failed to build mcl$(NC)" && exit 1); \
			else \
				echo "$(YELLOW)Building mcl (using default build method)...$(NC)"; \
				make -j$$(sysctl -n hw.ncpu 2>/dev/null || echo 4) || (echo "$(RED)✗ Failed to build mcl - may need manual installation$(NC)" && exit 1); \
			fi; \
			echo "$(YELLOW)Installing mcl library...$(NC)"; \
			if [ -d /opt/homebrew/lib ]; then \
				find /tmp/mcl/lib -name "libmcl*.a" -exec cp {} /opt/homebrew/lib/ \; 2>/dev/null || \
				find /tmp/mcl/lib -name "libmcl*.a" -exec sudo cp {} /opt/homebrew/lib/ \; 2>/dev/null || true; \
				find /tmp/mcl/lib -name "libmcl*.dylib" -exec cp {} /opt/homebrew/lib/ \; 2>/dev/null || \
				find /tmp/mcl/lib -name "libmcl*.dylib" -exec sudo cp {} /opt/homebrew/lib/ \; 2>/dev/null || true; \
				if [ -d /tmp/mcl/include/mcl ]; then \
					cp -r /tmp/mcl/include/mcl /opt/homebrew/include/ 2>/dev/null || \
					sudo cp -r /tmp/mcl/include/mcl /opt/homebrew/include/ 2>/dev/null || true; \
				fi; \
				echo "$(GREEN)✓ mcl installed to /opt/homebrew$(NC)"; \
			else \
				find /tmp/mcl/lib -name "libmcl*.a" -exec sudo cp {} /usr/local/lib/ \; 2>/dev/null || true; \
				find /tmp/mcl/lib -name "libmcl*.dylib" -exec sudo cp {} /usr/local/lib/ \; 2>/dev/null || true; \
				if [ -d /tmp/mcl/include/mcl ]; then \
					sudo cp -r /tmp/mcl/include/mcl /usr/local/include/ 2>/dev/null || true; \
				fi; \
				echo "$(GREEN)✓ mcl installed to /usr/local$(NC)"; \
			fi \
		fi \
	fi
	@echo "$(GREEN)✓ Dependencies installation complete$(NC)"

# Install dependencies on Linux (Debian/Ubuntu) using apt
install-apt-deps:
	@echo "$(BLUE)Installing dependencies via apt...$(NC)"
	@sudo apt-get update
	@sudo apt-get install -y libsecp256k1-dev libssl-dev build-essential git cmake
	@if [ "$(BLST_ENABLED)" = "true" ]; then \
		if [ -f /usr/local/lib/libblst.a ] || [ -f /usr/lib/libblst.a ] || [ -f /usr/local/lib/libblst.so ] || [ -f /usr/lib/libblst.so ]; then \
			echo "$(GREEN)✓ blst library already installed$(NC)"; \
		else \
			echo "$(YELLOW)Building blst from source...$(NC)"; \
			if [ ! -d /tmp/blst ]; then \
				cd /tmp && git clone https://github.com/supranational/blst.git || exit 1; \
			fi; \
			cd /tmp/blst && ./build.sh || (echo "$(RED)✗ Failed to build blst$(NC)" && exit 1); \
			echo "$(YELLOW)Installing blst library...$(NC)"; \
			sudo cp libblst.a /usr/local/lib/ 2>/dev/null || true; \
			sudo mkdir -p /usr/local/include 2>/dev/null || true; \
			sudo cp bindings/*.h /usr/local/include/ 2>/dev/null || true; \
			echo "$(GREEN)✓ blst installed$(NC)"; \
		fi \
	fi
	@if [ "$(MCL_ENABLED)" = "true" ]; then \
		if [ -f /usr/local/lib/libmcl.a ] || [ -f /usr/lib/libmcl.a ] || [ -f /usr/local/lib/libmcl.so ] || [ -f /usr/lib/libmcl.so ]; then \
			echo "$(GREEN)✓ mcl library already installed$(NC)"; \
		else \
			echo "$(YELLOW)Building mcl from source...$(NC)"; \
			if [ ! -d /tmp/mcl ]; then \
				cd /tmp && git clone https://github.com/herumi/mcl.git || exit 1; \
			fi; \
			cd /tmp/mcl && \
			if [ -f Makefile ]; then \
				make -j$$(nproc 2>/dev/null || echo 4) || (echo "$(RED)✗ Failed to build mcl$(NC)" && exit 1); \
			elif [ -f CMakeLists.txt ]; then \
				mkdir -p build && cd build && \
				cmake .. && make -j$$(nproc 2>/dev/null || echo 4) || (echo "$(RED)✗ Failed to build mcl$(NC)" && exit 1); \
			else \
				echo "$(YELLOW)Building mcl (using default build method)...$(NC)"; \
				make -j$$(nproc 2>/dev/null || echo 4) || (echo "$(RED)✗ Failed to build mcl - may need manual installation$(NC)" && exit 1); \
			fi; \
			echo "$(YELLOW)Installing mcl library...$(NC)"; \
			find /tmp/mcl/lib -name "libmcl*.a" -exec sudo cp {} /usr/local/lib/ \; 2>/dev/null || true; \
			find /tmp/mcl/lib -name "libmcl*.so" -exec sudo cp {} /usr/local/lib/ \; 2>/dev/null || true; \
			if [ -d /tmp/mcl/include/mcl ]; then \
				sudo cp -r /tmp/mcl/include/mcl /usr/local/include/ 2>/dev/null || true; \
			fi; \
			echo "$(GREEN)✓ mcl installed$(NC)"; \
		fi \
	fi
	@echo "$(GREEN)✓ Dependencies installation complete$(NC)"

# Install dependencies on Linux (Fedora/RHEL) using dnf
install-dnf-deps:
	@echo "$(BLUE)Installing dependencies via dnf...$(NC)"
	@sudo dnf install -y libsecp256k1-devel openssl-devel gcc gcc-c++ make git cmake
	@if [ "$(BLST_ENABLED)" = "true" ]; then \
		if [ -f /usr/local/lib/libblst.a ] || [ -f /usr/lib/libblst.a ] || [ -f /usr/local/lib/libblst.so ] || [ -f /usr/lib/libblst.so ]; then \
			echo "$(GREEN)✓ blst library already installed$(NC)"; \
		else \
			echo "$(YELLOW)Building blst from source...$(NC)"; \
			if [ ! -d /tmp/blst ]; then \
				cd /tmp && git clone https://github.com/supranational/blst.git || exit 1; \
			fi; \
			cd /tmp/blst && ./build.sh || (echo "$(RED)✗ Failed to build blst$(NC)" && exit 1); \
			echo "$(YELLOW)Installing blst library...$(NC)"; \
			sudo cp libblst.a /usr/local/lib/ 2>/dev/null || true; \
			sudo mkdir -p /usr/local/include 2>/dev/null || true; \
			sudo cp bindings/*.h /usr/local/include/ 2>/dev/null || true; \
			echo "$(GREEN)✓ blst installed$(NC)"; \
		fi \
	fi
	@if [ "$(MCL_ENABLED)" = "true" ]; then \
		if [ -f /usr/local/lib/libmcl.a ] || [ -f /usr/lib/libmcl.a ] || [ -f /usr/local/lib/libmcl.so ] || [ -f /usr/lib/libmcl.so ]; then \
			echo "$(GREEN)✓ mcl library already installed$(NC)"; \
		else \
			echo "$(YELLOW)Building mcl from source...$(NC)"; \
			if [ ! -d /tmp/mcl ]; then \
				cd /tmp && git clone https://github.com/herumi/mcl.git || exit 1; \
			fi; \
			cd /tmp/mcl && \
			if [ -f Makefile ]; then \
				make -j$$(nproc 2>/dev/null || echo 4) || (echo "$(RED)✗ Failed to build mcl$(NC)" && exit 1); \
			elif [ -f CMakeLists.txt ]; then \
				mkdir -p build && cd build && \
				cmake .. && make -j$$(nproc 2>/dev/null || echo 4) || (echo "$(RED)✗ Failed to build mcl$(NC)" && exit 1); \
			else \
				echo "$(YELLOW)Building mcl (using default build method)...$(NC)"; \
				make -j$$(nproc 2>/dev/null || echo 4) || (echo "$(RED)✗ Failed to build mcl - may need manual installation$(NC)" && exit 1); \
			fi; \
			echo "$(YELLOW)Installing mcl library...$(NC)"; \
			find /tmp/mcl/lib -name "libmcl*.a" -exec sudo cp {} /usr/local/lib/ \; 2>/dev/null || true; \
			find /tmp/mcl/lib -name "libmcl*.so" -exec sudo cp {} /usr/local/lib/ \; 2>/dev/null || true; \
			if [ -d /tmp/mcl/include/mcl ]; then \
				sudo cp -r /tmp/mcl/include/mcl /usr/local/include/ 2>/dev/null || true; \
			fi; \
			echo "$(GREEN)✓ mcl installed$(NC)"; \
		fi \
	fi
	@echo "$(GREEN)✓ Dependencies installation complete$(NC)"

# Install dependencies on Windows using vcpkg
install-vcpkg-deps:
	@echo "$(BLUE)Installing dependencies via vcpkg...$(NC)"
	@command -v vcpkg >/dev/null 2>&1 || (echo "$(RED)✗ vcpkg is not installed. Install from https://github.com/Microsoft/vcpkg$(NC)" && exit 1)
	@vcpkg install secp256k1 openssl
	@if [ "$(BLST_ENABLED)" = "true" ]; then \
		vcpkg install blst || echo "$(YELLOW)Note: blst may need to be built from source$(NC)"; \
	fi
	@if [ "$(MCL_ENABLED)" = "true" ]; then \
		vcpkg install mcl || echo "$(YELLOW)Note: mcl may need to be built from source$(NC)"; \
	fi
	@echo "$(GREEN)✓ Dependencies installation complete$(NC)"

# Build the project
build: check-deps
	@echo "$(BLUE)Building ZEVM...$(NC)"
	@echo "$(YELLOW)Build command: $(ZIG_BUILD_CMD)$(NC)"
	@$(ZIG_BUILD_CMD)
	@echo "$(GREEN)✓ Build complete!$(NC)"

# Build with dependency installation
build-with-deps: install-deps build

# Run tests
test: build
	@echo "$(BLUE)Running tests...$(NC)"
	@if [ "$(UNAME_S)" = "Darwin" ]; then \
		export DYLD_LIBRARY_PATH="/opt/homebrew/lib:/usr/local/lib:$$DYLD_LIBRARY_PATH"; \
	fi; \
	./zig-out/bin/zevm-test || zig build test
	@echo "$(GREEN)✓ Tests complete!$(NC)"

# Clean build artifacts
clean:
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	@rm -rf zig-out zig-cache .zig-cache
	@echo "$(GREEN)✓ Clean complete!$(NC)"

# Generate spec test data from Ethereum execution-spec-tests fixtures
generate-spec-tests:
	@if [ -f "$(SPEC_TEST_DIR)/generated/data.zig" ]; then \
		CURRENT_HASH=$$(shasum -a 256 $(SPEC_TEST_DIR)/generated/data.zig | cut -d' ' -f1); \
		if [ "$$CURRENT_HASH" = "$(SPEC_TEST_HASH)" ]; then \
			echo "$(GREEN)Spec tests already generated for $(SPEC_TEST_VERSION) (hash verified), skipping.$(NC)"; \
			exit 0; \
		fi; \
	fi; \
	echo "$(BLUE)Downloading execution-spec-tests $(SPEC_TEST_VERSION)...$(NC)"; \
	mkdir -p $(SPEC_TEST_DIR)/fixtures; \
	curl -sL "https://github.com/ethereum/execution-spec-tests/releases/download/$(SPEC_TEST_VERSION)/fixtures_develop.tar.gz" \
		| tar xz --strip-components=1 -C $(SPEC_TEST_DIR)/fixtures/; \
	echo "$(BLUE)Building spec test generator...$(NC)"; \
	$(ZIG_BUILD_CMD) spec-test-generator; \
	mkdir -p $(SPEC_TEST_DIR)/generated; \
	echo "$(BLUE)Generating Zig test data...$(NC)"; \
	./zig-out/bin/spec-test-generator $(SPEC_TEST_DIR)/fixtures/state_tests $(SPEC_TEST_DIR)/generated/data.zig; \
	rm -rf $(SPEC_TEST_DIR)/fixtures; \
	echo "$(GREEN)Generated spec tests from $(SPEC_TEST_VERSION)$(NC)"

# Build and run spec tests
spec-tests: generate-spec-tests
	@echo "$(BLUE)Building spec test runner...$(NC)"
	@$(ZIG_BUILD_CMD) spec-test-runner
	@echo "$(BLUE)Running spec tests...$(NC)"
	@./zig-out/bin/spec-test-runner $(ARGS)

# Install dependencies and build (convenience target)
all: install-deps build

