const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const precompile = @import("precompile");
const gas_costs = @import("gas_costs.zig");
const InstructionContext = @import("instruction_context.zig").InstructionContext;
const InstructionFn = @import("instruction_context.zig").InstructionFn;
const Interpreter = @import("interpreter.zig").Interpreter;
const InstructionResult = @import("instruction_result.zig").InstructionResult;
const Host = @import("host.zig").Host;
const opcodes = @import("opcodes/main.zig");

/// One entry in the dispatch table: a handler function and its static gas cost.
pub const InstructionEntry = struct {
    func: InstructionFn,
    static_gas: u64,

    pub fn unknown() InstructionEntry {
        return .{ .func = opUnknown, .static_gas = 0 };
    }
};

/// 256-entry dispatch table indexed by opcode byte.
pub const InstructionTable = [256]InstructionEntry;

/// Full protocol configuration for one hardfork: dispatch table + precompile set.
pub const ProtocolSchedule = struct {
    spec: primitives.SpecId,
    instructions: InstructionTable,
    precompiles: precompile.Precompiles,

    pub fn forSpec(spec: primitives.SpecId) ProtocolSchedule {
        return .{
            .spec = spec,
            .instructions = makeInstructionTable(spec),
            .precompiles = makePrecompiles(spec),
        };
    }
};

/// Execute one opcode: read opcode at PC, advance PC, charge static gas, call handler.
pub fn step(interp: *Interpreter, table: *const InstructionTable) void {
    const op = interp.bytecode.opcode();
    interp.bytecode.relativeJump(1);
    const ins = table[op];
    if (!interp.gas.spend(ins.static_gas)) {
        interp.halt(.out_of_gas);
        return;
    }
    var ctx = InstructionContext{ .interpreter = interp };
    ins.func(&ctx);
}

/// Run the interpreter until execution halts.
pub fn run(interp: *Interpreter, table: *const InstructionTable) InstructionResult {
    while (interp.bytecode.isNotEnd()) {
        step(interp, table);
    }
    return interp.result;
}

/// Execute one opcode with a host for state access.
pub fn stepWithHost(interp: *Interpreter, table: *const InstructionTable, host: *Host) void {
    const op = interp.bytecode.opcode();
    interp.bytecode.relativeJump(1);
    const ins = table[op];
    if (!interp.gas.spend(ins.static_gas)) {
        interp.halt(.out_of_gas);
        return;
    }
    var ctx = InstructionContext{ .interpreter = interp, .host = host };
    ins.func(&ctx);
}

/// Run the interpreter until execution halts, with full host access.
pub fn runWithHost(interp: *Interpreter, table: *const InstructionTable, host: *Host) InstructionResult {
    while (interp.bytecode.isNotEnd()) {
        stepWithHost(interp, table, host);
    }
    return interp.result;
}

/// Default sub-call runner stored in Host. Derives the instruction table from the
/// sub-interpreter's spec so there is no circular dependency between host.zig and
/// protocol_schedule.zig.
pub fn runSubCallDefault(host: *Host, sub_interp: *Interpreter) void {
    const spec = sub_interp.runtime_flags.spec_id;
    const table = makeInstructionTable(spec);
    _ = runWithHost(sub_interp, &table, host);
}

/// Handler for unknown/disabled opcodes.
fn opUnknown(ctx: *InstructionContext) void {
    ctx.interpreter.halt(.invalid_opcode);
}

// ---------------------------------------------------------------------------
// Instruction table construction
// ---------------------------------------------------------------------------

fn entry(func: InstructionFn, static_gas: u64) InstructionEntry {
    return .{ .func = func, .static_gas = static_gas };
}

pub fn makeInstructionTable(spec: primitives.SpecId) InstructionTable {
    var table = makeFrontierTable();

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

fn makeFrontierTable() InstructionTable {
    var table = [_]InstructionEntry{InstructionEntry.unknown()} ** 256;

    // System
    table[bytecode_mod.STOP] = entry(opcodes.opStop, gas_costs.G_ZERO);

    // Arithmetic
    table[bytecode_mod.ADD] = entry(opcodes.opAdd, gas_costs.G_VERYLOW);
    table[bytecode_mod.MUL] = entry(opcodes.opMul, gas_costs.G_LOW);
    table[bytecode_mod.SUB] = entry(opcodes.opSub, gas_costs.G_VERYLOW);
    table[bytecode_mod.DIV] = entry(opcodes.opDiv, gas_costs.G_LOW);
    table[bytecode_mod.SDIV] = entry(opcodes.opSdiv, gas_costs.G_LOW);
    table[bytecode_mod.MOD] = entry(opcodes.opMod, gas_costs.G_LOW);
    table[bytecode_mod.SMOD] = entry(opcodes.opSmod, gas_costs.G_LOW);
    table[bytecode_mod.ADDMOD] = entry(opcodes.opAddmod, gas_costs.G_MID);
    table[bytecode_mod.MULMOD] = entry(opcodes.opMulmod, gas_costs.G_MID);
    table[bytecode_mod.EXP] = entry(opcodes.opExp, gas_costs.G_EXP);
    table[bytecode_mod.SIGNEXTEND] = entry(opcodes.opSignextend, gas_costs.G_LOW);

    // Comparison
    table[bytecode_mod.LT] = entry(opcodes.opLt, gas_costs.G_VERYLOW);
    table[bytecode_mod.GT] = entry(opcodes.opGt, gas_costs.G_VERYLOW);
    table[bytecode_mod.SLT] = entry(opcodes.opSlt, gas_costs.G_VERYLOW);
    table[bytecode_mod.SGT] = entry(opcodes.opSgt, gas_costs.G_VERYLOW);
    table[bytecode_mod.EQ] = entry(opcodes.opEq, gas_costs.G_VERYLOW);
    table[bytecode_mod.ISZERO] = entry(opcodes.opIsZero, gas_costs.G_VERYLOW);

    // Bitwise
    table[bytecode_mod.AND] = entry(opcodes.opAnd, gas_costs.G_VERYLOW);
    table[bytecode_mod.OR] = entry(opcodes.opOr, gas_costs.G_VERYLOW);
    table[bytecode_mod.XOR] = entry(opcodes.opXor, gas_costs.G_VERYLOW);
    table[bytecode_mod.NOT] = entry(opcodes.opNot, gas_costs.G_VERYLOW);
    table[bytecode_mod.BYTE] = entry(opcodes.opByte, gas_costs.G_VERYLOW);

    // Keccak256
    table[bytecode_mod.KECCAK256] = entry(opcodes.opKeccak256, gas_costs.G_KECCAK256);

    // Stack
    table[bytecode_mod.POP] = entry(opcodes.opPop, gas_costs.G_BASE);

    // Memory
    table[bytecode_mod.MLOAD] = entry(opcodes.opMload, gas_costs.G_VERYLOW);
    table[bytecode_mod.MSTORE] = entry(opcodes.opMstore, gas_costs.G_VERYLOW);
    table[bytecode_mod.MSTORE8] = entry(opcodes.opMstore8, gas_costs.G_VERYLOW);
    table[bytecode_mod.MSIZE] = entry(opcodes.opMsize, gas_costs.G_BASE);

    // Control flow
    table[bytecode_mod.JUMP] = entry(opcodes.opJump, gas_costs.G_MID);
    table[bytecode_mod.JUMPI] = entry(opcodes.opJumpi, gas_costs.G_HIGH);
    table[bytecode_mod.PC] = entry(opcodes.opPc, gas_costs.G_BASE);
    table[bytecode_mod.GAS] = entry(opcodes.opGas, gas_costs.G_BASE);
    table[bytecode_mod.JUMPDEST] = entry(opcodes.opJumpdest, gas_costs.G_JUMPDEST);

    // PUSH1..PUSH32
    inline for (0..32) |i| {
        table[bytecode_mod.PUSH1 + i] = entry(opcodes.makePushFn(i + 1), gas_costs.G_VERYLOW);
    }

    // DUP1..DUP16
    inline for (0..16) |i| {
        table[bytecode_mod.DUP1 + i] = entry(opcodes.makeDupFn(i + 1), gas_costs.G_VERYLOW);
    }

    // SWAP1..SWAP16
    inline for (0..16) |i| {
        table[bytecode_mod.SWAP1 + i] = entry(opcodes.makeSwapFn(i + 1), gas_costs.G_VERYLOW);
    }

    // Environment: no-host opcodes (interpreter.input fields)
    table[bytecode_mod.ADDRESS] = entry(opcodes.opAddress, gas_costs.G_BASE);
    table[bytecode_mod.CALLER] = entry(opcodes.opCaller, gas_costs.G_BASE);
    table[bytecode_mod.CALLVALUE] = entry(opcodes.opCallvalue, gas_costs.G_BASE);
    table[bytecode_mod.CALLDATASIZE] = entry(opcodes.opCalldatasize, gas_costs.G_BASE);
    table[bytecode_mod.CALLDATALOAD] = entry(opcodes.opCalldataload, gas_costs.G_VERYLOW);
    table[bytecode_mod.CALLDATACOPY] = entry(opcodes.opCalldatacopy, gas_costs.G_VERYLOW);
    table[bytecode_mod.CODESIZE] = entry(opcodes.opCodesize, gas_costs.G_BASE);
    table[bytecode_mod.CODECOPY] = entry(opcodes.opCodecopy, gas_costs.G_VERYLOW);
    table[bytecode_mod.RETURNDATASIZE] = entry(opcodes.opReturndatasize, gas_costs.G_BASE);
    table[bytecode_mod.RETURNDATACOPY] = entry(opcodes.opReturndatacopy, gas_costs.G_VERYLOW);

    // Environment: host-requiring opcodes
    table[bytecode_mod.ORIGIN] = entry(opcodes.opOrigin, gas_costs.G_BASE);
    table[bytecode_mod.GASPRICE] = entry(opcodes.opGasprice, gas_costs.G_BASE);
    table[bytecode_mod.EXTCODESIZE] = entry(opcodes.opExtcodesize, 700);
    table[bytecode_mod.EXTCODECOPY] = entry(opcodes.opExtcodecopy, 700);
    table[bytecode_mod.BLOCKHASH] = entry(opcodes.opBlockhash, 20);
    table[bytecode_mod.COINBASE] = entry(opcodes.opCoinbase, gas_costs.G_BASE);
    table[bytecode_mod.TIMESTAMP] = entry(opcodes.opTimestamp, gas_costs.G_BASE);
    table[bytecode_mod.NUMBER] = entry(opcodes.opNumber, gas_costs.G_BASE);
    table[bytecode_mod.DIFFICULTY] = entry(opcodes.opDifficulty, gas_costs.G_BASE);
    table[bytecode_mod.GASLIMIT] = entry(opcodes.opGaslimit, gas_costs.G_BASE);
    table[bytecode_mod.BALANCE] = entry(opcodes.opBalance, 400);

    // Storage
    table[bytecode_mod.SLOAD] = entry(opcodes.opSload, gas_costs.G_SLOAD_TANGERINE);
    table[bytecode_mod.SSTORE] = entry(opcodes.opSstore, 0);

    // Logs
    table[bytecode_mod.LOG0] = entry(opcodes.opLog0, gas_costs.G_LOG);
    table[bytecode_mod.LOG1] = entry(opcodes.opLog1, gas_costs.G_LOG);
    table[bytecode_mod.LOG2] = entry(opcodes.opLog2, gas_costs.G_LOG);
    table[bytecode_mod.LOG3] = entry(opcodes.opLog3, gas_costs.G_LOG);
    table[bytecode_mod.LOG4] = entry(opcodes.opLog4, gas_costs.G_LOG);

    // System
    table[bytecode_mod.RETURN] = entry(opcodes.opReturn, 0);
    table[bytecode_mod.INVALID] = entry(opcodes.opInvalid, 0);
    table[bytecode_mod.SELFDESTRUCT] = entry(opcodes.opSelfdestruct, gas_costs.G_SELFDESTRUCT);

    // Calls (all-dynamic gas, static_gas=0)
    table[bytecode_mod.CALL] = entry(opcodes.opCall, 0);
    table[bytecode_mod.CALLCODE] = entry(opcodes.opCallcode, 0);

    // CREATE / CREATE2 (stubs)
    table[bytecode_mod.CREATE] = entry(opcodes.opCreate, gas_costs.G_CREATE);
    table[bytecode_mod.CREATE2] = entry(opcodes.opCreate2, gas_costs.G_CREATE);

    return table;
}

fn applyHomesteadChanges(table: *InstructionTable) void {
    // DELEGATECALL added in Homestead
    table[bytecode_mod.DELEGATECALL] = entry(opcodes.opDelegatecall, 0);
}

fn applyTangerineChanges(table: *InstructionTable) void {
    // EIP-150: repricing
    table[bytecode_mod.SLOAD].static_gas = gas_costs.G_SLOAD_TANGERINE;
    table[bytecode_mod.EXTCODESIZE].static_gas = 700;
    table[bytecode_mod.EXTCODECOPY].static_gas = 700;
    table[bytecode_mod.BALANCE].static_gas = 400;
}

fn applyByzantiumChanges(table: *InstructionTable) void {
    // EIP-145: Bitwise shifts
    table[bytecode_mod.SHL] = entry(opcodes.opShl, gas_costs.G_VERYLOW);
    table[bytecode_mod.SHR] = entry(opcodes.opShr, gas_costs.G_VERYLOW);
    table[bytecode_mod.SAR] = entry(opcodes.opSar, gas_costs.G_VERYLOW);
    // EIP-140: REVERT
    table[bytecode_mod.REVERT] = entry(opcodes.opRevert, 0);
    // EIP-211: RETURNDATASIZE / RETURNDATACOPY (already in Frontier table but enabled here)
    // They're already registered; no gas change needed.
    // STATICCALL added
    table[bytecode_mod.STATICCALL] = entry(opcodes.opStaticcall, 0);
}

fn applyConstantinopleChanges(table: *InstructionTable) void {
    // EXTCODEHASH added
    table[bytecode_mod.EXTCODEHASH] = entry(opcodes.opExtcodehash, 400);
    // CREATE2 repriced (it was a stub, keep as stub)
    // SHL/SHR/SAR already in Byzantium
}

fn applyIstanbulChanges(table: *InstructionTable) void {
    // EIP-1344: CHAINID
    table[bytecode_mod.CHAINID] = entry(opcodes.opChainid, gas_costs.G_BASE);
    // EIP-1884: Repricing
    table[bytecode_mod.SLOAD].static_gas = gas_costs.G_SLOAD_ISTANBUL;
    table[bytecode_mod.BALANCE].static_gas = 700;
    table[bytecode_mod.EXTCODEHASH].static_gas = 700;
    // EIP-1884: SELFBALANCE
    table[bytecode_mod.SELFBALANCE] = entry(opcodes.opSelfbalance, gas_costs.G_LOW);
}

fn applyBerlinChanges(table: *InstructionTable) void {
    // EIP-2929: cold/warm account and storage access; all gas is now dynamic
    table[bytecode_mod.SLOAD].static_gas = 0;
    table[bytecode_mod.BALANCE].static_gas = 0;
    table[bytecode_mod.EXTCODESIZE].static_gas = 0;
    table[bytecode_mod.EXTCODECOPY].static_gas = 0;
    table[bytecode_mod.EXTCODEHASH].static_gas = 0;
}

fn applyLondonChanges(table: *InstructionTable) void {
    // EIP-3198: BASEFEE
    table[bytecode_mod.BASEFEE] = entry(opcodes.opBasefee, gas_costs.G_BASE);
}

fn applyShanghaiChanges(table: *InstructionTable) void {
    // EIP-3855: PUSH0
    table[bytecode_mod.PUSH0] = entry(opcodes.opPush0, gas_costs.G_BASE);
}

fn applyCancunChanges(table: *InstructionTable) void {
    // EIP-5656: MCOPY
    table[bytecode_mod.MCOPY] = entry(opcodes.opMcopy, gas_costs.G_VERYLOW);
    // EIP-1153: Transient storage
    table[bytecode_mod.TLOAD] = entry(opcodes.opTload, gas_costs.WARM_SLOAD);
    table[bytecode_mod.TSTORE] = entry(opcodes.opTstore, gas_costs.WARM_SLOAD);
    // EIP-4844: Blob opcodes
    table[bytecode_mod.BLOBHASH] = entry(opcodes.opBlobhash, gas_costs.G_VERYLOW);
    table[bytecode_mod.BLOBBASEFEE] = entry(opcodes.opBlobbasefee, gas_costs.G_BASE);
}

fn applyOsakaChanges(table: *InstructionTable) void {
    _ = table;
    // No new EVM opcodes in Osaka
}

// ---------------------------------------------------------------------------
// Precompile set construction
// ---------------------------------------------------------------------------

pub fn makePrecompiles(spec: primitives.SpecId) precompile.Precompiles {
    const precompile_spec = precompile.PrecompileSpecId.fromSpec(spec);
    return precompile.Precompiles.forSpec(precompile_spec);
}
