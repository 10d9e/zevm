# ZEVM Opcode Implementation Status

**Branch:** `opcodes_upstream_based` (based on `daniel/feat/arithmetic_basic_opcodes`)
**Last Updated:** 2026-02-06 (Arithmetic category completed)
**Build Status:** ✅ Passing (all tests)

## Overview

This document tracks the opcode implementation status for ZEVM after rebasing onto the upstream branch that provides:
- **Fixed-size Stack** implementation (`[1024]U256` array, no heap allocation)
- **Arithmetic operations** (ADD, SUB, MUL, DIV, MOD, ADDMOD, MULMOD, EXP)
- **Modern API patterns** optimized for performance

We've restored and adapted additional opcode categories from the previous implementation branch (`opcodes_forks_backup`) to work with the new Stack API.

---

## ✅ Implemented Opcodes: 55 Total

### Arithmetic Operations (`opcodes/arithmetic.zig`) - 11 opcodes ✅ COMPLETE
From upstream `daniel/feat/arithmetic_basic_opcodes` + newly added signed operations:
- ✅ **ADD** (0x01) - Wrapping addition with overflow
- ✅ **MUL** (0x02) - Wrapping multiplication
- ✅ **SUB** (0x03) - Wrapping subtraction
- ✅ **DIV** (0x04) - Unsigned division (returns 0 on div-by-zero)
- ✅ **SDIV** (0x05) - Signed division (two's complement)
- ✅ **MOD** (0x06) - Unsigned modulo (returns 0 on mod-by-zero)
- ✅ **SMOD** (0x07) - Signed modulo (result has sign of dividend)
- ✅ **ADDMOD** (0x08) - `(a + b) % N` with overflow handling
- ✅ **MULMOD** (0x09) - `(a * b) % N` using double-and-add
- ✅ **EXP** (0x0A) - Exponentiation with dynamic gas (10 + 50*bytesize)
- ✅ **SIGNEXTEND** (0x0B) - Sign extend value from byte position

**API Pattern:**
```zig
pub inline fn opAdd(stack: *Stack, gas: *Gas) InstructionResult
```

### Bitwise Operations (`opcodes/bitwise.zig`) - 8 opcodes
Restored and adapted from backup:
- ✅ **AND** (0x16) - Bitwise AND (`a & b`)
- ✅ **OR** (0x17) - Bitwise OR (`a | b`)
- ✅ **XOR** (0x18) - Bitwise XOR (`a ^ b`)
- ✅ **NOT** (0x19) - Bitwise NOT (`~a`)
- ✅ **BYTE** (0x1A) - Extract byte at position
- ✅ **SHL** (0x1B) - Shift left
- ✅ **SHR** (0x1C) - Logical shift right
- ✅ **SAR** (0x1D) - Arithmetic shift right (sign extension)

**API Pattern:**
```zig
pub inline fn opAnd(stack: *Stack, gas: *Gas) InstructionResult
```

### Comparison Operations (`opcodes/comparison.zig`) - 6 opcodes
Restored and adapted from backup:
- ✅ **LT** (0x10) - Less than (unsigned)
- ✅ **GT** (0x11) - Greater than (unsigned)
- ✅ **SLT** (0x12) - Less than (signed, two's complement)
- ✅ **SGT** (0x13) - Greater than (signed, two's complement)
- ✅ **EQ** (0x14) - Equality test
- ✅ **ISZERO** (0x15) - Is zero test

**API Pattern:**
```zig
pub inline fn opLt(stack: *Stack, gas: *Gas) InstructionResult
```

### Stack Operations (`opcodes/stack.zig`) - 18 opcodes
Restored and adapted from backup:
- ✅ **POP** (0x50) - Remove top item
- ✅ **PUSH0** (0x5F) - Push 0 (Shanghai+)
- ✅ **PUSH1-PUSH32** (0x60-0x7F) - Push 1-32 bytes from bytecode
- ✅ **DUP1-DUP16** (0x80-0x8F) - Duplicate nth stack item
- ✅ **SWAP1-SWAP16** (0x90-0x9F) - Swap top with nth item

**API Pattern:**
```zig
pub inline fn opPop(stack: *Stack, gas: *Gas) InstructionResult
pub inline fn opPushN(stack: *Stack, gas: *Gas, bytecode: []const u8, pc: *usize, n: u8) InstructionResult
pub inline fn opDupN(stack: *Stack, gas: *Gas, n: u8) InstructionResult
pub inline fn opSwapN(stack: *Stack, gas: *Gas, n: u8) InstructionResult
```

### Control Flow Operations (`opcodes/control.zig`) - 6 opcodes
Restored and adapted from backup:
- ✅ **STOP** (0x00) - Halt execution
- ✅ **JUMP** (0x56) - Unconditional jump to JUMPDEST
- ✅ **JUMPI** (0x57) - Conditional jump if non-zero
- ✅ **JUMPDEST** (0x5B) - Valid jump destination marker
- ✅ **PC** (0x58) - Push program counter
- ✅ **GAS** (0x5A) - Push remaining gas

**API Pattern:**
```zig
pub inline fn opJump(stack: *Stack, gas: *Gas, bytecode: Bytecode, pc: *usize) InstructionResult
pub inline fn opPc(stack: *Stack, gas: *Gas, pc: usize) InstructionResult
```

### Memory Operations (`opcodes/memory.zig`) - 5 opcodes
Restored and adapted from backup:
- ✅ **MLOAD** (0x51) - Load 32 bytes from memory
- ✅ **MSTORE** (0x52) - Store 32 bytes to memory
- ✅ **MSTORE8** (0x53) - Store 1 byte to memory
- ✅ **MSIZE** (0x59) - Get memory size in bytes
- ✅ **MCOPY** (0x5E) - Copy memory region (Cancun+)

**API Pattern:**
```zig
pub inline fn opMload(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult
```

**Gas Costs:** Base cost + memory expansion cost (quadratic: `3*words + words²/512`)

### Cryptographic Operations (`opcodes/keccak.zig`) - 1 opcode
Restored and adapted from backup:
- ✅ **KECCAK256** (0x20) - Compute Keccak-256 hash

**API Pattern:**
```zig
pub inline fn opKeccak256(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult
```

**Gas Cost:** 30 + 6 * num_words

---

## 🚧 Not Yet Implemented

### Storage Operations - 4 opcodes
**Requires Host Interface for state access**
- ⏳ **SLOAD** (0x54) - Load from persistent storage
- ⏳ **SSTORE** (0x55) - Store to persistent storage
- ⏳ **TLOAD** (0x5C) - Load from transient storage (Cancun+)
- ⏳ **TSTORE** (0x5D) - Store to transient storage (Cancun+)

**Requirements:**
- Host interface with `sload()` and `sstore()` methods
- EIP-2200 gas accounting (net gas metering)
- EIP-2929 cold/warm access tracking
- EIP-3529 reduced refunds (London+)

### Environment Information - 26 opcodes
**Requires Host Interface for execution context**

**Call Data & Code:**
- ⏳ ADDRESS (0x30), CALLER (0x33), CALLVALUE (0x34)
- ⏳ CALLDATALOAD (0x35), CALLDATASIZE (0x36), CALLDATACOPY (0x37)
- ⏳ CODESIZE (0x38), CODECOPY (0x39)
- ⏳ GASPRICE (0x3A)
- ⏳ RETURNDATASIZE (0x3D), RETURNDATACOPY (0x3E)

**External Code:**
- ⏳ EXTCODESIZE (0x3B), EXTCODECOPY (0x3C), EXTCODEHASH (0x3F)

**Block Information:**
- ⏳ BLOCKHASH (0x40), COINBASE (0x41), TIMESTAMP (0x42)
- ⏳ NUMBER (0x43), DIFFICULTY/PREVRANDAO (0x44), GASLIMIT (0x45)
- ⏳ CHAINID (0x46), BASEFEE (0x48)

**Account & Balance:**
- ⏳ BALANCE (0x31), SELFBALANCE (0x47), ORIGIN (0x32)

**Blob (Cancun+):**
- ⏳ BLOBHASH (0x49), BLOBBASEFEE (0x4A)

### System Operations - 9 opcodes
**Requires Host Interface for state changes and logging**
- ⏳ **RETURN** (0xF3) - Return output data
- ⏳ **REVERT** (0xFD) - Revert with output data
- ⏳ **SELFDESTRUCT** (0xFF) - Destroy contract (EIP-6780 changes in Cancun+)
- ⏳ **LOG0-LOG4** (0xA0-0xA4) - Emit log events with 0-4 topics

### Call Operations - 4 opcodes
**Complex, requires sub-interpreter execution**
- ⏳ **CALL** (0xF1) - Message call to another contract
- ⏳ **CALLCODE** (0xF2) - Call with alternative code (deprecated)
- ⏳ **DELEGATECALL** (0xF4) - Call preserving msg.sender
- ⏳ **STATICCALL** (0xFA) - Read-only call (Byzantium+)

**Requirements:**
- Sub-context creation and frame management
- Recursive interpreter execution
- Gas forwarding (63/64 rule)
- Call depth tracking (max 1024)
- Return data buffer management

### Create Operations - 2 opcodes
**Complex, requires contract deployment**
- ⏳ **CREATE** (0xF0) - Create new contract
- ⏳ **CREATE2** (0xF5) - Create with deterministic address (Constantinople+)

**Requirements:**
- Init code execution
- Address calculation (CREATE vs CREATE2 differ)
- Contract deployment and code storage
- Constructor logic execution

---

## 📋 Infrastructure Status

### 1. Instruction Dispatch Table ✅ IMPLEMENTED
**Status:** ✅ Implemented (`instruction_table.zig`, 270 lines)

**Features:**
- 256-entry instruction table with base gas costs
- Hardfork-specific table construction (Frontier → Osaka)
- Progressive opcode enablement per hardfork:
  - **Homestead**: DELEGATECALL
  - **Byzantium**: REVERT, RETURNDATASIZE, RETURNDATACOPY, STATICCALL, SHL, SHR, SAR
  - **Constantinople**: CREATE2, EXTCODEHASH
  - **Istanbul**: CHAINID, gas repricing
  - **Berlin**: EIP-2929 cold/warm access costs
  - **London**: BASEFEE
  - **Shanghai**: PUSH0
  - **Cancun**: TLOAD, TSTORE, MCOPY, BLOBHASH, BLOBBASEFEE
  - **Osaka**: (no new opcodes)
- Invalid opcode detection via `isOpcodeEnabled()`
- Base gas cost lookup via `getBaseGasCost()`

**API:**
```zig
const table = instruction_table.makeInstructionTable(.shanghai);
if (table.isOpcodeEnabled(opcode)) {
    const gas = table.getBaseGasCost(opcode);
}
```

### 2. Gas Cost Module ✅ IMPLEMENTED
**Status:** ✅ Implemented (`gas_costs.zig`, 220 lines)

**Features:**
- All EVM gas constants (G_BASE, G_VERYLOW, G_LOW, etc.)
- Memory expansion cost calculation (quadratic formula)
- Spec-dependent SLOAD costs:
  - Pre-Istanbul: 200-800 gas
  - Berlin+: 2100 (cold) / 100 (warm)
- SSTORE gas cost calculation (EIP-2200, EIP-2929, EIP-3529):
  - Handles original/current/new value combinations
  - Refund calculations for clearing storage
  - Cold/warm access costs
- CALL gas cost calculation (EIP-2929)
- Helper functions: `memoryExpansionCost()`, `toWordSize()`

**API:**
```zig
const sload_cost = gas_costs.getSloadCost(.berlin, is_cold);
const sstore_result = gas_costs.getSstoreCost(.london, original, current, new, is_cold);
const expansion = gas_costs.memoryExpansionCost(current_words, new_words);
```

### 3. Host Interface
**Status:** ❌ Not implemented

Many opcodes require external state and environment access. Need:
- Host trait/interface (function pointer-based or vtable)
- StateHost implementation wrapping `EvmState` and `TransientStorage`
- Integration with `BlockEnv`, `TxEnv`, `CfgEnv` from context
- Methods for:
  - Storage operations (sload, sstore, tload, tstore)
  - Account queries (balance, code, extcode*)
  - Block information (blockhash, timestamp, number, etc.)
  - Transaction info (caller, origin, gasprice, etc.)
  - Logging (log0-log4)
  - Complex operations (call, create, selfdestruct)

**Reference:** Previous implementation had `host.zig` (577 lines)

### 4. Execution Loop Integration
**Status:** ⚠️ Partial

The interpreter has execution infrastructure, but needs:
- Opcode fetching and dispatch
- Program counter management
- Instruction result handling
- Integration of all opcode signatures (Stack, Gas, Memory, Host, etc.)
- Use of instruction table for validation and gas charging

**Reference:** Previous implementation modified `interpreter.zig` with `run()` method

---

## 🔑 Key Design Patterns

### Fixed-Size Stack API
**Benefit:** No heap allocations, better performance

```zig
// Old pattern (removed)
const a = stack.pop() orelse return .stack_underflow;
stack.push(result) catch return .stack_overflow;

// New pattern (current)
if (!stack.hasItems(2)) return .stack_underflow;
const a = stack.peekUnsafe(0);
const b = stack.peekUnsafe(1);
stack.shrinkUnsafe(1);
stack.setTopUnsafe().* = a +% b;
```

**Pattern:** peek-peek-shrink-overwrite

### Real U256 Operators
**Benefit:** Uses Zig's built-in integer operators, no hallucinated methods

```zig
// Old (incorrect)
const result = a.bitand(b);  // Method doesn't exist

// New (correct)
const result = a & b;  // Built-in operator
```

### Opcode Function Signatures

| Opcode Type | Signature | Example |
|-------------|-----------|---------|
| Simple (arithmetic, bitwise, comparison) | `fn(stack: *Stack, gas: *Gas) InstructionResult` | ADD, AND, LT |
| Stack operations | `fn(stack: *Stack, gas: *Gas, ...) InstructionResult` | PUSH needs bytecode, DUP needs n |
| Control flow | Needs bytecode and PC | JUMP, JUMPI |
| Memory operations | `fn(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult` | MLOAD, MSTORE |
| State operations | Will need Host parameter | SLOAD, SSTORE, BALANCE |
| System operations | Will need Host parameter | LOG, RETURN, SELFDESTRUCT |

---

## 📊 Implementation Progress

| Category | Implemented | Missing | Total | % Complete |
|----------|-------------|---------|-------|------------|
| Arithmetic | 11 | 0 | 11 | 100% ✅ |
| Bitwise | 8 | 0 | 8 | 100% ✅ |
| Comparison | 6 | 0 | 6 | 100% ✅ |
| Stack | 18 | 0 | 18 | 100% ✅ |
| Control | 6 | 0 | 6 | 100% ✅ |
| Memory | 5 | 0 | 5 | 100% ✅ |
| Storage | 0 | 4 | 4 | 0% |
| Environment | 0 | 26 | 26 | 0% |
| System | 1 (STOP) | 8 | 9 | 11% |
| Keccak | 1 | 0 | 1 | 100% ✅ |
| Call/Create | 0 | 6 | 6 | 0% |
| **TOTAL** | **55** | **44** | **99** | **56%** |

*Note: CALL/CREATE family excluded from total as they require separate frame execution infrastructure*

---

## 🧪 Testing Status

- ✅ **Upstream tests:** 92/92 passing (from `daniel/feat/arithmetic_basic_opcodes`)
- ❌ **Opcode unit tests:** Not yet added for restored opcodes
- ❌ **Integration tests:** Not yet added for full bytecode execution
- ❌ **Ethereum test suite:** Not yet integrated

---

## 🚀 Next Steps

### Immediate Priorities

1. **Design and implement Host interface**
   - Complexity: High
   - Blocks: Storage, Environment, System opcodes
   - Reference previous `host.zig` but adapt to new patterns
   - **Critical blocker** for 44 remaining opcodes

2. **Create instruction dispatch table**
   - Complexity: Medium
   - Needed for execution loop integration
   - Maps 256 opcodes to function pointers
   - Handles hardfork-specific availability

3. **Implement storage opcodes** (SLOAD, SSTORE, TLOAD, TSTORE)
   - Complexity: Medium
   - Depends on: Host interface
   - Requires: EIP-2200/2929/3529 gas accounting

4. **Implement environment opcodes** (26 opcodes)
   - Complexity: Low-Medium
   - Depends on: Host interface
   - Mostly straightforward Host method calls

5. **Implement system opcodes** (RETURN, REVERT, LOG, SELFDESTRUCT)
   - Complexity: Medium
   - Depends on: Host interface

### Future Work

7. **CALL/CREATE operations**
   - Complexity: Very High
   - Requires: Frame management, recursive execution, address calculation

8. **Comprehensive testing**
   - Unit tests for each opcode
   - Integration tests with real bytecode
   - Ethereum official test suite
   - Gas accounting verification

9. **Performance optimization**
   - Benchmark against revm
   - Profile hot paths
   - Optimize allocations

---

## 📚 References

- **Upstream branch:** `daniel/feat/arithmetic_basic_opcodes`
- **Backup branch:** `opcodes_forks_backup` (previous implementation)
- **REVM source:** `revm/crates/interpreter/src/`
- **Ethereum Yellow Paper:** Gas costs and specifications
- **Key EIPs:**
  - EIP-2200: SSTORE net gas metering
  - EIP-2929: Cold/warm access (Berlin)
  - EIP-3529: Reduced refunds (London)
  - EIP-1153: Transient storage (Cancun)
  - EIP-3855: PUSH0 (Shanghai)
  - EIP-5656: MCOPY (Cancun)
  - EIP-6780: SELFDESTRUCT changes (Cancun)

---

## 🔍 File Locations

### Infrastructure
```
src/interpreter/
├── instruction_table.zig  # Hardfork-specific instruction tables (270 lines) ✅
├── gas_costs.zig         # Gas constants and dynamic cost functions (220 lines) ✅
└── opcodes/              # Opcode implementations
    ├── main.zig              # Module exports
    ├── arithmetic.zig        # 11 opcodes + tests ✅
    ├── arithmetic_tests.zig  # ~90 tests ✅
    ├── bitwise.zig          # 8 opcodes ✅
    ├── bitwise_tests.zig    # 55 tests ✅
    ├── comparison.zig       # 6 opcodes ✅
    ├── comparison_tests.zig # 39 tests ✅
    ├── stack.zig            # 18 opcodes ✅
    ├── stack_tests.zig      # 42 tests ✅
    ├── control.zig          # 6 opcodes ✅
    ├── control_tests.zig    # 41 tests ✅
    ├── memory.zig           # 5 opcodes ✅
    ├── memory_tests.zig     # 38 tests ✅
    ├── keccak.zig           # 1 opcode ✅
    └── keccak_tests.zig     # 20 tests ✅
```

### Still to Create
```
src/interpreter/opcodes/
├── storage.zig         # SLOAD, SSTORE, TLOAD, TSTORE (requires Host)
├── environment.zig     # 26 environment info opcodes (requires Host)
├── system.zig          # RETURN, REVERT, LOG0-4, SELFDESTRUCT (requires Host)
├── call.zig            # CALL, CALLCODE, DELEGATECALL, STATICCALL (requires Host + frames)
└── create.zig          # CREATE, CREATE2 (requires Host + deployment)
```

### Benchmarks
```
benchmarks/main.zig     # Comprehensive benchmarks for arithmetic + bitwise opcodes
```

---

**Status Summary:** 55/99 opcodes implemented (56%), with comprehensive test coverage (~325 tests). Hardfork-specific instruction tables and gas cost infrastructure complete. 7 opcode categories fully implemented with tests. Host interface is the main blocker for remaining 44 opcodes.
