const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const gas_costs = @import("gas_costs.zig");
const Stack = @import("stack.zig").Stack;
const Gas = @import("gas.zig").Gas;
const Memory = @import("memory.zig").Memory;
const InstructionResult = @import("instruction_result.zig").InstructionResult;

// Import opcode implementations
const opcodes = @import("opcodes/main.zig");

/// Function pointer type for instruction execution
/// Note: Different opcodes have different signatures, so we'll need multiple function pointer types
pub const SimpleInstructionFn = *const fn (*Stack, *Gas) InstructionResult;
pub const MemoryInstructionFn = *const fn (*Stack, *Gas, *Memory) InstructionResult;

/// Entry in the instruction table
pub const InstructionEntry = struct {
    /// Base gas cost (some opcodes have dynamic costs calculated during execution)
    base_gas: u64,
    /// Whether this opcode is valid in this hardfork
    enabled: bool = true,
};

/// Instruction table - 256 entries for all possible opcodes
pub const InstructionTable = [256]InstructionEntry;

/// Create an invalid/disabled opcode entry
fn invalid() InstructionEntry {
    return .{ .base_gas = 0, .enabled = false };
}

/// Create a valid instruction entry
fn entry(gas: u64) InstructionEntry {
    return .{ .base_gas = gas, .enabled = true };
}

/// Build instruction table for a specific hardfork
pub fn makeInstructionTable(spec: primitives.SpecId) InstructionTable {
    var table = makeFrontierTable();

    // Apply hardfork-specific changes
    if (primitives.isEnabledIn(spec, .homestead)) applyHomesteadChanges(&table);
    if (primitives.isEnabledIn(spec, .tangerine)) applyTangerineChanges(&table);
    if (primitives.isEnabledIn(spec, .byzantium)) applyByzantiumChanges(&table);
    if (primitives.isEnabledIn(spec, .constantinople)) applyConstantinopleChanges(&table);
    if (primitives.isEnabledIn(spec, .istanbul)) applyIstanbulChanges(&table);
    if (primitives.isEnabledIn(spec, .berlin)) applyBerlinChanges(&table);
    if (primitives.isEnabledIn(spec, .london)) applyLondonChanges(&table);
    if (primitives.isEnabledIn(spec, .shanghai)) applyShanghaiChanges(&table);
    if (primitives.isEnabledIn(spec, .cancun)) applyCancunChanges(&table);
    if (primitives.isEnabledIn(spec, .osaka)) applyOsakaChanges(&table);

    return table;
}

/// Base Frontier instruction table
fn makeFrontierTable() InstructionTable {
    var table: InstructionTable = undefined;

    // Initialize all entries as invalid
    for (&table) |*e| {
        e.* = invalid();
    }

    // Arithmetic operations (0x01-0x0B)
    table[bytecode_mod.ADD] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.MUL] = entry(gas_costs.G_LOW);
    table[bytecode_mod.SUB] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.DIV] = entry(gas_costs.G_LOW);
    table[bytecode_mod.SDIV] = entry(gas_costs.G_LOW);
    table[bytecode_mod.MOD] = entry(gas_costs.G_LOW);
    table[bytecode_mod.SMOD] = entry(gas_costs.G_LOW);
    table[bytecode_mod.ADDMOD] = entry(gas_costs.G_MID);
    table[bytecode_mod.MULMOD] = entry(gas_costs.G_MID);
    table[bytecode_mod.EXP] = entry(gas_costs.G_EXP); // Base cost, dynamic per byte
    table[bytecode_mod.SIGNEXTEND] = entry(gas_costs.G_LOW);

    // Comparison operations (0x10-0x15)
    table[bytecode_mod.LT] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.GT] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.SLT] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.SGT] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.EQ] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.ISZERO] = entry(gas_costs.G_VERYLOW);

    // Bitwise operations (0x16-0x1D)
    table[bytecode_mod.AND] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.OR] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.XOR] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.NOT] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.BYTE] = entry(gas_costs.G_VERYLOW);

    // Keccak256 (0x20)
    table[bytecode_mod.KECCAK256] = entry(gas_costs.G_KECCAK256); // Base cost, dynamic per word

    // Environment information (0x30-0x3F) - Not yet implemented
    table[bytecode_mod.ADDRESS] = entry(gas_costs.G_BASE);
    table[bytecode_mod.BALANCE] = entry(gas_costs.G_HIGH);
    table[bytecode_mod.ORIGIN] = entry(gas_costs.G_BASE);
    table[bytecode_mod.CALLER] = entry(gas_costs.G_BASE);
    table[bytecode_mod.CALLVALUE] = entry(gas_costs.G_BASE);
    table[bytecode_mod.CALLDATALOAD] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.CALLDATASIZE] = entry(gas_costs.G_BASE);
    table[bytecode_mod.CALLDATACOPY] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.CODESIZE] = entry(gas_costs.G_BASE);
    table[bytecode_mod.CODECOPY] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.GASPRICE] = entry(gas_costs.G_BASE);
    table[bytecode_mod.EXTCODESIZE] = entry(gas_costs.G_HIGH);
    table[bytecode_mod.EXTCODECOPY] = entry(gas_costs.G_HIGH);

    // Block information (0x40-0x48)
    table[bytecode_mod.BLOCKHASH] = entry(gas_costs.G_HIGH);
    table[bytecode_mod.COINBASE] = entry(gas_costs.G_BASE);
    table[bytecode_mod.TIMESTAMP] = entry(gas_costs.G_BASE);
    table[bytecode_mod.NUMBER] = entry(gas_costs.G_BASE);
    table[bytecode_mod.DIFFICULTY] = entry(gas_costs.G_BASE);
    table[bytecode_mod.GASLIMIT] = entry(gas_costs.G_BASE);

    // Stack operations (0x50)
    table[bytecode_mod.POP] = entry(gas_costs.G_BASE);

    // Memory operations (0x51-0x59)
    table[bytecode_mod.MLOAD] = entry(gas_costs.G_VERYLOW); // Base cost, dynamic for expansion
    table[bytecode_mod.MSTORE] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.MSTORE8] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.MSIZE] = entry(gas_costs.G_BASE);

    // Storage operations (0x54-0x55) - Not yet implemented
    table[bytecode_mod.SLOAD] = entry(gas_costs.G_SLOAD_TANGERINE); // Spec-dependent
    table[bytecode_mod.SSTORE] = entry(gas_costs.G_ZERO); // Dynamic cost

    // Control flow (0x56-0x5B)
    table[bytecode_mod.JUMP] = entry(gas_costs.G_MID);
    table[bytecode_mod.JUMPI] = entry(gas_costs.G_HIGH);
    table[bytecode_mod.PC] = entry(gas_costs.G_BASE);
    table[bytecode_mod.GAS] = entry(gas_costs.G_BASE);
    table[bytecode_mod.JUMPDEST] = entry(gas_costs.G_JUMPDEST);

    // System operations (0x00, 0xF0-0xFF) - Partially implemented
    table[bytecode_mod.STOP] = entry(gas_costs.G_ZERO);
    table[bytecode_mod.RETURN] = entry(gas_costs.G_ZERO);
    table[bytecode_mod.SELFDESTRUCT] = entry(gas_costs.G_SELFDESTRUCT);

    // Logging (0xA0-0xA4) - Not yet implemented
    table[bytecode_mod.LOG0] = entry(gas_costs.G_LOG);
    table[bytecode_mod.LOG1] = entry(gas_costs.G_LOG);
    table[bytecode_mod.LOG2] = entry(gas_costs.G_LOG);
    table[bytecode_mod.LOG3] = entry(gas_costs.G_LOG);
    table[bytecode_mod.LOG4] = entry(gas_costs.G_LOG);

    // PUSH operations (0x60-0x7F)
    inline for (0..32) |i| {
        const opcode = bytecode_mod.PUSH1 + i;
        table[opcode] = entry(gas_costs.G_VERYLOW);
    }

    // DUP operations (0x80-0x8F)
    inline for (0..16) |i| {
        const opcode = bytecode_mod.DUP1 + i;
        table[opcode] = entry(gas_costs.G_VERYLOW);
    }

    // SWAP operations (0x90-0x9F)
    inline for (0..16) |i| {
        const opcode = bytecode_mod.SWAP1 + i;
        table[opcode] = entry(gas_costs.G_VERYLOW);
    }

    // CALL family (0xF1-0xF4, 0xFA) - Not yet implemented
    table[bytecode_mod.CALL] = entry(gas_costs.G_CALL);
    table[bytecode_mod.CALLCODE] = entry(gas_costs.G_CALL);

    // CREATE operations (0xF0, 0xF5) - Not yet implemented
    table[bytecode_mod.CREATE] = entry(gas_costs.G_CREATE);

    return table;
}

fn applyHomesteadChanges(table: *InstructionTable) void {
    // Homestead introduces DELEGATECALL (0xF4)
    table[bytecode_mod.DELEGATECALL] = entry(gas_costs.G_CALL);
}

fn applyTangerineChanges(table: *InstructionTable) void {
    // EIP-150: Gas cost changes for IO-heavy operations
    table[bytecode_mod.BALANCE].base_gas = 400;
    table[bytecode_mod.EXTCODESIZE].base_gas = 700;
    table[bytecode_mod.EXTCODECOPY].base_gas = 700;
    table[bytecode_mod.SLOAD].base_gas = gas_costs.G_SLOAD_TANGERINE;
    table[bytecode_mod.CALL].base_gas = 700;
    table[bytecode_mod.CALLCODE].base_gas = 700;
    table[bytecode_mod.DELEGATECALL].base_gas = 700;
    table[bytecode_mod.SELFDESTRUCT].base_gas = 5000;
}

fn applyByzantiumChanges(table: *InstructionTable) void {
    // Byzantium introduces RETURNDATASIZE, RETURNDATACOPY, STATICCALL, REVERT
    table[bytecode_mod.RETURNDATASIZE] = entry(gas_costs.G_BASE);
    table[bytecode_mod.RETURNDATACOPY] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.STATICCALL] = entry(gas_costs.G_CALL);
    table[bytecode_mod.REVERT] = entry(gas_costs.G_ZERO);

    // Bitwise shifts (EIP-145)
    table[bytecode_mod.SHL] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.SHR] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.SAR] = entry(gas_costs.G_VERYLOW);
}

fn applyConstantinopleChanges(table: *InstructionTable) void {
    // Constantinople introduces CREATE2, EXTCODEHASH (EIP-1014, EIP-1052)
    table[bytecode_mod.CREATE2] = entry(gas_costs.G_CREATE);
    table[bytecode_mod.EXTCODEHASH] = entry(gas_costs.G_HIGH);
}

fn applyIstanbulChanges(table: *InstructionTable) void {
    // EIP-1344: CHAINID
    table[bytecode_mod.CHAINID] = entry(gas_costs.G_BASE);

    // EIP-1884: Repricing of SLOAD, BALANCE, EXTCODEHASH
    table[bytecode_mod.BALANCE].base_gas = gas_costs.G_SLOAD_ISTANBUL;
    table[bytecode_mod.SLOAD].base_gas = gas_costs.G_SLOAD_ISTANBUL;
    table[bytecode_mod.EXTCODEHASH].base_gas = gas_costs.G_SLOAD_ISTANBUL;

    // EIP-2200: SSTORE gas metering changes (handled dynamically)
}

fn applyBerlinChanges(table: *InstructionTable) void {
    // EIP-2929: Gas cost increases for state access opcodes
    // Cold/warm access costs are handled dynamically in opcode implementations
    table[bytecode_mod.SLOAD].base_gas = gas_costs.WARM_SLOAD;

    // EIP-2930: Access lists (handled at transaction level)
}

fn applyLondonChanges(table: *InstructionTable) void {
    // EIP-3198: BASEFEE opcode
    table[bytecode_mod.BASEFEE] = entry(gas_costs.G_BASE);

    // EIP-3529: Reduced refunds (handled in gas_costs.getSstoreCost)
}

fn applyShanghaiChanges(table: *InstructionTable) void {
    // EIP-3855: PUSH0 opcode
    table[bytecode_mod.PUSH0] = entry(gas_costs.G_BASE);
}

fn applyCancunChanges(table: *InstructionTable) void {
    // EIP-1153: Transient storage opcodes
    table[bytecode_mod.TLOAD] = entry(gas_costs.WARM_SLOAD);
    table[bytecode_mod.TSTORE] = entry(gas_costs.WARM_SLOAD);

    // EIP-5656: MCOPY opcode
    table[bytecode_mod.MCOPY] = entry(gas_costs.G_VERYLOW); // Base cost, dynamic for length

    // EIP-4844: Blob transaction opcodes
    table[bytecode_mod.BLOBHASH] = entry(gas_costs.G_VERYLOW);
    table[bytecode_mod.BLOBBASEFEE] = entry(gas_costs.G_BASE);

    // EIP-6780: SELFDESTRUCT changes (behavior change, not gas cost)
}

fn applyOsakaChanges(table: *InstructionTable) void {
    // Osaka includes all Cancun opcodes
    // No new EVM opcodes in Osaka
    // ModExp precompile gas changes are handled in precompile layer
    _ = table;
}

/// Check if an opcode is valid/enabled for a given spec
pub fn isOpcodeEnabled(table: *const InstructionTable, opcode: u8) bool {
    return table[opcode].enabled;
}

/// Get base gas cost for an opcode
pub fn getBaseGasCost(table: *const InstructionTable, opcode: u8) u64 {
    return table[opcode].base_gas;
}
