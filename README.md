# ZEVM - Zig Ethereum Virtual Machine

[![Zig](https://img.shields.io/badge/Zig-0.15.1+-blue.svg)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-0.3.1-orange.svg)](RELEASE_NOTES.md)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](https://github.com/10d9e/zevm/actions)
[![Tests](https://img.shields.io/badge/Tests-100%25%20Passing-brightgreen.svg)](https://github.com/10d9e/zevm/actions)

A high-performance Ethereum Virtual Machine implementation in Zig.

<img width="400" height="400" alt="image" src="https://github.com/user-attachments/assets/9be1b24d-4c8e-423a-b9b4-8fb47378be55" />

## Overview

ZEVM is a complete EVM implementation that provides:
- Full Ethereum protocol support up to the Osaka hardfork (Fusaka-ready)
- Modular architecture for easy customization
- High-performance execution
- Comprehensive precompile support (all 18 standard precompiles)
- Built-in debugging and inspection tools
- Type-safe implementation leveraging Zig's compile-time guarantees
- **Fusaka devnet ready** - Full support for Osaka hardfork features

## Features

### Core Components

- **Primitives**: Core types (U256, Address, Hash), constants, and hardfork definitions
- **Bytecode**: Opcode definitions, bytecode analysis, and EIP-7702 support
- **State Management**: Account info, storage, and state transitions
- **Database**: Pluggable database interface with in-memory implementation
- **Context**: Block, transaction, and configuration management
- **Interpreter**: Stack-based EVM interpreter with gas tracking
- **Precompiles**: Ethereum precompiled contracts (SHA256, RIPEMD160, ECRECOVER, etc.)
- **Handler**: Transaction execution orchestration
- **Inspector**: Debugging and profiling tools

### Supported Hardforks

- Frontier
- Homestead
- Tangerine
- Spurious Dragon
- Byzantium
- Constantinople
- Petersburg
- Istanbul
- Berlin
- London
- Paris (The Merge)
- Shanghai
- Cancun
- Prague
- **Osaka** (Latest) - **Fusaka devnet ready** ✅

### Precompiled Contracts

All 18 standard Ethereum precompiles are fully implemented:

- **Identity** (0x04): Data copy
- **SHA256** (0x02): SHA-256 hash function
- **RIPEMD160** (0x03): RIPEMD-160 hash function
- **ECRECOVER** (0x01): Elliptic curve signature recovery
- **ModExp** (0x05): Modular exponentiation (Byzantium/Berlin/Osaka variants)
- **BN254** (0x06-0x08): BN254 curve operations (Add, Mul, Pairing)
- **Blake2F** (0x09): Blake2 compression function
- **KZG Point Evaluation** (0x0A): KZG commitment verification (EIP-4844)
- **BLS12-381** (0x0B-0x11): All 7 BLS12-381 curve operations
- **P256Verify** (0x100): secp256r1 signature verification (RIP-7212)

**Osaka Hardfork Features:**
- ✅ ModExp Osaka gas calculation (EIP-7883)
- ✅ EIP-7823 input size limits (1024 bytes)
- ✅ P256Verify Osaka gas cost (6900 gas)
- ✅ PrecompileId support for Fusaka devnet

## Building

### Quick Start (Recommended)

The easiest way to build ZEVM is using the provided Makefile:

```bash
# Auto-detect OS, install dependencies, and build
make

# Or step by step:
make install-deps  # Install dependencies
make build         # Build the project
make test          # Run tests
```

The Makefile automatically:
- Detects your operating system (macOS, Linux, Windows)
- Installs required dependencies via the appropriate package manager
- Builds the project with correct options

See `make help` for more options.

### Prerequisites

- Zig 0.15.1 or later
- C compiler (for system libraries)
- **blst library** (required, see [CROSS_PLATFORM.md](CROSS_PLATFORM.md) for installation)
- **mcl library** (required, see [CROSS_PLATFORM.md](CROSS_PLATFORM.md) for installation)
- **secp256k1** (required, typically available via package managers)
- **OpenSSL** (required, typically available via package managers)

**⚠️ Note**: If you see "library not found" errors for `blst` or `mcl`, you need to install these libraries first. See [CROSS_PLATFORM.md](CROSS_PLATFORM.md) for detailed installation instructions. You can temporarily disable them with `zig build -Dblst=false -Dmcl=false`, but this will disable related precompiles.

### Manual Build Commands

If you prefer to build manually:

```bash
# Build the library and all executables
zig build

# Run the comprehensive test suite
./zig-out/bin/zevm-test

# Run examples
./zig-out/bin/simple_contract
./zig-out/bin/gas_inspector_example
./zig-out/bin/precompile_example
./zig-out/bin/version_info
```

## Examples

### Simple Contract Execution

```zig
const database = @import("database");
const context = @import("context");
const primitives = @import("primitives");
const interpreter = @import("interpreter");
const bytecode = @import("bytecode");
const state = @import("state");

// Create an in-memory database
var db = database.InMemoryDB.init(std.heap.c_allocator);
defer db.deinit();

// Create a context with Prague specification
var ctx = context.Context.new(db, primitives.SpecId.prague);

// Create bytecode
const bytecode_obj = bytecode.Bytecode.new();

// Set up the contract account
const contract_address: primitives.Address = [_]u8{0x01} ** 20;
const account = state.AccountInfo.new(
    @as(primitives.U256, 0), // balance
    0, // nonce
    primitives.KECCAK_EMPTY, // code hash
    bytecode_obj,
);

try db.insertAccount(contract_address, account);

// Set up transaction
var tx = context.TxEnv.default();
defer tx.deinit();
tx.caller = [_]u8{0x02} ** 20;
tx.gas_limit = 100000;
ctx.tx = tx;

// Create interpreter
const inputs = interpreter.InputsImpl.new(
    tx.caller,
    contract_address,
    @as(primitives.U256, 0),
    &[_]u8{},
    tx.gas_limit,
    interpreter.CallScheme.call,
    false,
    0,
);

var interp = interpreter.Interpreter.new(
    interpreter.Memory.new(),
    interpreter.ExtBytecode.new(bytecode_obj),
    inputs,
    false,
    primitives.SpecId.prague,
    tx.gas_limit,
);
```

### Gas Tracking with Inspector

```zig
const inspector = @import("inspector");
const interpreter = @import("interpreter");

// Create a gas inspector
var gas_inspector = inspector.GasInspector.new();

// Create a gas tracker
var gas = interpreter.Gas.new(100000);

// Initialize the inspector
gas_inspector.initializeInterp(&gas);

// Simulate operations
_ = gas.spend(3); // PUSH1
gas_inspector.step(&gas);

_ = gas.spend(3); // ADD
gas_inspector.stepEnd(&gas);

// Check gas usage
std.log.info("Gas remaining: {}", .{gas_inspector.gasRemaining()});
std.log.info("Last gas cost: {}", .{gas_inspector.lastGasCost()});
```

### Using Precompiles

```zig
const precompile = @import("precompile");

// Create an identity precompile
const identity_precompile = precompile.Precompile.new(
    precompile.PrecompileId.Identity,
    precompile.u64ToAddress(4),
    precompile.identity.identityRun,
);

// Execute the precompile
const input = "Hello, ZEVM!";
const result = identity_precompile.execute(input, 10000);

switch (result) {
    .success => |output| {
        std.log.info("Gas used: {}", .{output.gas_used});
        std.log.info("Output: {s}", .{output.bytes});
    },
    .err => |err| {
        std.log.err("Error: {}", .{err});
    },
}
```

## Testing

The project includes a comprehensive test suite covering all modules:

```bash
# Run all tests
./zig-out/bin/zevm-test
```

Other executables:
`./zig-out/bin/precompile_example` - Precompile demonstration
`./zig-out/bin/simple_contract` - Basic contract execution
`./zig-out/bin/gas_inspector_example` - Gas tracking example
`./zig-out/bin/zevm-test` - Comprehensive test suite

Test coverage includes:
- Primitives (U256, Address, Hash operations)
- Bytecode (opcode parsing and analysis)
- State management (account and storage)
- Database operations
- Context management
- Interpreter execution
- Precompile functionality
- Handler orchestration
- Inspector tools
- Integration tests

## Ethereum State Tests

ZEVM includes a runner for the official [Ethereum execution-spec-tests](https://github.com/ethereum/execution-spec-tests) state test fixtures. These tests verify EVM correctness against the Ethereum specification across supported hardforks (Prague, Osaka).

### Quick Start

```bash
# Download fixtures, generate test data, build and run
make spec-tests
```

### Step by Step

```bash
# 1. Download fixtures and generate the Zig test data file
make generate-spec-tests

# 2. Build the runner
zig build spec-test-runner

# 3. Run all state tests
./zig-out/bin/spec-test-runner
```

### Filtering

```bash
# Run only Osaka fork tests
./zig-out/bin/spec-test-runner --fork=Osaka

# Filter by test name substring
./zig-out/bin/spec-test-runner --filter=sstore

# Stop on first failure
./zig-out/bin/spec-test-runner --fail-fast

# Show passing tests
./zig-out/bin/spec-test-runner --verbose

# Combine flags
./zig-out/bin/spec-test-runner --fork=Prague --filter=shift --fail-fast
```

### How It Works

1. **Generator** (`src/spec_test/generator.zig`) parses JSON fixtures from `ethereum/execution-spec-tests` and emits a hardcoded Zig data file (`spec-tests/generated/data.zig`).
2. **Runner** (`src/spec_test/runner.zig`) imports the generated data, sets up pre-state (accounts, storage, balances), executes bytecode through the interpreter, and validates post-state storage against expectations.
3. **Types** (`src/spec_test/types.zig`) defines the shared `TestCase`, `PreAccount`, and `StorageEntry` structures.

## Performance

ZEVM is designed for high performance:
- Zero-cost abstractions using Zig's compile-time features
- Minimal allocations with stack-based execution
- Efficient memory management
- Optimized opcode dispatch
- Fast precompile implementations

## Fusaka Devnet Support

ZEVM is **fully ready** for Fusaka devnet testing:

- ✅ **PrecompileId Implementation**: Complete with Custom variant support
- ✅ **Osaka Hardfork**: All Osaka-specific precompile changes implemented
- ✅ **EIP-7823 & EIP-7883**: ModExp Osaka gas calculation and input limits
- ✅ **P256Verify Osaka**: Correct gas cost (6900) for Osaka hardfork
- ✅ **Feature Parity**: 100% match with revm reference implementation

See [FUSAKA_READINESS.md](FUSAKA_READINESS.md) for complete verification checklist.

## Contributing

Contributions are welcome! Areas for improvement:
- Additional database backends
- Performance optimizations
- Extended test coverage (Ethereum state tests)
- Documentation improvements
- EOF (EIP-7702) enhancements

## License

This project is a port of [revm](https://github.com/bluealloy/revm) to Zig. Please refer to the original project for licensing information.

## Acknowledgments

- [revm](https://github.com/bluealloy/revm) - The original Rust implementation
- The Ethereum Foundation for the EVM specification
- The Zig community for the excellent language and tooling

## Status

ZEVM v0.3.1 is now available! **Fusaka devnet ready** with full Osaka hardfork support.

### ✅ Completed
- Core EVM interpreter with all standard opcodes
- Gas tracking and metering
- State management and database interface
- **All 18 standard precompiles** (100% feature parity with revm)
- **Osaka hardfork support** (ModExp Osaka, P256Verify Osaka)
- **Fusaka devnet ready** (PrecompileId implementation)
- Inspector tools and debugging capabilities
- Comprehensive test suite (73+ precompile tests)
- Cross-platform build system (macOS, Linux, Windows)
- Static linking support for self-contained binaries
- Complete documentation and examples

### 🚀 Recent Updates (v0.3.1)
- **Fusaka/Osaka Support**: Full implementation of PrecompileId with Custom variant
- **ModExp Osaka**: Fixed gas calculation to match EIP-7883 specification
- **EIP-7823**: Corrected input size limits to 1024 bytes
- **PrecompileId Enhancements**: Added `name()` and `precompile()` methods

See [FUSAKA_READINESS.md](FUSAKA_READINESS.md) for detailed Fusaka readiness verification.

## Release Information

- **Current Version**: v0.3.1
- **Release Date**: December 2, 2025
- **Fusaka Status**: ✅ Ready for Fusaka devnet testing
- **Release Notes**: [RELEASE_NOTES.md](RELEASE_NOTES.md)
- **Changelog**: [CHANGELOG.md](CHANGELOG.md)
- **Fusaka Readiness**: [FUSAKA_READINESS.md](FUSAKA_READINESS.md)

## Resources

- ported from [revm](https://github.com/bluealloy/revm).
- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf)
- [EVM Opcodes](https://www.evm.codes/)
- [Ethereum Improvement Proposals](https://eips.ethereum.org/)
- [revm Documentation](https://github.com/bluealloy/revm)
- [Zig Documentation](https://ziglang.org/documentation/master/)
- [CI/CD Documentation](CI.md)
