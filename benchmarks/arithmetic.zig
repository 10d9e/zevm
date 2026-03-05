const std = @import("std");
const interpreter = @import("interpreter");
const bytecode = @import("bytecode");
const m = @import("main.zig");

const gas_costs = interpreter.gas_costs;
const U256 = @import("primitives").U256;
const MAX = std.math.maxInt(U256);

// ---------------------------------------------------------------------------
// Reset functions
// ---------------------------------------------------------------------------

fn resetAdd() void {
    m.setup(m.gasFor(bytecode.ADD));
    m.fillRandom(m.PREFILL);
}

fn resetSub() void {
    m.setup(m.gasFor(bytecode.SUB));
    m.fillRandom(m.PREFILL);
}
fn resetSubBorrow() void {
    m.setup(m.gasFor(bytecode.SUB));
    m.fillConstantPairs(m.PREFILL / 2, 0, 1);
}

fn resetMul() void {
    m.setup(m.gasFor(bytecode.MUL));
    m.fillRandom(m.PREFILL);
}
fn resetMulSmall() void {
    m.setup(m.gasFor(bytecode.MUL));
    m.fillPairs(m.PREFILL / 2, m.g_divisor_64);
}

fn resetDiv() void {
    m.setup(m.gasFor(bytecode.DIV));
    m.fillPairs(m.PREFILL / 2, m.g_divisor_128);
}
fn resetDivFull() void {
    m.setup(m.gasFor(bytecode.DIV));
    m.fillRandomPairs(m.PREFILL / 2);
}
fn resetDivSmall() void {
    m.setup(m.gasFor(bytecode.DIV));
    m.fillPairs(m.PREFILL / 2, m.g_divisor_64);
}
fn resetDivZero() void {
    m.setup(m.gasFor(bytecode.DIV));
    m.fillPairs(m.PREFILL / 2, 0);
}

fn resetSdiv() void {
    m.setup(m.gasFor(bytecode.SDIV));
    m.fillPairs(m.PREFILL / 2, m.g_divisor_128);
}
fn resetSdivNegative() void {
    m.setup(m.gasFor(bytecode.SDIV));
    m.fillNegativePairs(m.PREFILL / 2, m.g_divisor_128);
}
fn resetSdivBothNeg() void {
    m.setup(m.gasFor(bytecode.SDIV));
    m.fillBothNegPairs(m.PREFILL / 2, m.g_divisor_128);
}

fn resetMod() void {
    m.setup(m.gasFor(bytecode.MOD));
    m.fillPairs(m.PREFILL / 2, m.g_divisor_128);
}
fn resetModSmall() void {
    m.setup(m.gasFor(bytecode.MOD));
    m.fillPairs(m.PREFILL / 2, m.g_divisor_64);
}
fn resetModZero() void {
    m.setup(m.gasFor(bytecode.MOD));
    m.fillPairs(m.PREFILL / 2, 0);
}

fn resetSmod() void {
    m.setup(m.gasFor(bytecode.SMOD));
    m.fillPairs(m.PREFILL / 2, m.g_divisor_128);
}
fn resetSmodNegative() void {
    m.setup(m.gasFor(bytecode.SMOD));
    m.fillNegativePairs(m.PREFILL / 2, m.g_divisor_128);
}

fn resetSignextend() void {
    m.setup(m.gasFor(bytecode.SIGNEXTEND));
    m.fillSignextendPairs(m.PREFILL / 2, 15);
}
fn resetSignextendLow() void {
    m.setup(m.gasFor(bytecode.SIGNEXTEND));
    m.fillSignextendPairs(m.PREFILL / 2, 3);
}
fn resetSignextendHigh() void {
    m.ensureInit();
    m.g_stack.clear();
    const gas_cost = m.gasFor(bytecode.SIGNEXTEND);
    m.g_gas = interpreter.Gas.new(m.OPS_PER_BATCH * gas_cost + 1000);
    for (0..m.PREFILL / 2) |i| {
        m.g_stack.pushUnsafe(m.g_values[i & (m.NUM_VALUES - 1)]);
        m.g_stack.pushUnsafe(@as(U256, 28 + (i & 3)));
    }
}

fn resetAddmod() void {
    m.setup(m.gasFor(bytecode.ADDMOD));
    m.fillRandomTriples(m.PREFILL);
}
fn resetAddmodOverflow() void {
    m.setup(m.gasFor(bytecode.ADDMOD));
    m.fillFixedTriples(m.PREFILL, MAX, MAX);
}

fn resetMulmod() void {
    m.setup(m.gasFor(bytecode.MULMOD));
    m.fillRandomTriples(m.PREFILL);
}
fn resetMulmodMax() void {
    m.setup(m.gasFor(bytecode.MULMOD));
    m.fillFixedTriples(m.PREFILL, MAX, MAX);
}

fn resetExpSmall() void {
    const gas_cost = m.gasFor(bytecode.EXP) + gas_costs.G_EXPBYTE;
    m.setup(gas_cost);
    m.fillExpSmall(m.PREFILL / 2);
}
fn resetExpLarge() void {
    const gas_cost = m.gasFor(bytecode.EXP) + gas_costs.G_EXPBYTE * 32;
    m.setup(gas_cost);
    m.fillExpLarge(m.PREFILL / 2);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn register(bench: anytype, filter: []const u8) !void {
    const opcodes = interpreter.opcodes;
    const Runner = m.OpRunner;

    if (m.matchesFilter("OP_ADD", filter)) try bench.add("OP_ADD", Runner(opcodes.opAdd).run, .{ .hooks = .{ .before_each = resetAdd } });
    if (m.matchesFilter("OP_SUB", filter)) try bench.add("OP_SUB", Runner(opcodes.opSub).run, .{ .hooks = .{ .before_each = resetSub } });
    if (m.matchesFilter("OP_SUB (borrow)", filter)) try bench.add("OP_SUB (borrow)", Runner(opcodes.opSub).run, .{ .hooks = .{ .before_each = resetSubBorrow } });
    if (m.matchesFilter("OP_MUL", filter)) try bench.add("OP_MUL", Runner(opcodes.opMul).run, .{ .hooks = .{ .before_each = resetMul } });
    if (m.matchesFilter("OP_MUL (256x64)", filter)) try bench.add("OP_MUL (256x64)", Runner(opcodes.opMul).run, .{ .hooks = .{ .before_each = resetMulSmall } });
    if (m.matchesFilter("OP_DIV", filter)) try bench.add("OP_DIV", Runner(opcodes.opDiv).run, .{ .hooks = .{ .before_each = resetDiv } });
    if (m.matchesFilter("OP_DIV (256/256)", filter)) try bench.add("OP_DIV (256/256)", Runner(opcodes.opDiv).run, .{ .hooks = .{ .before_each = resetDivFull } });
    if (m.matchesFilter("OP_DIV (256/64)", filter)) try bench.add("OP_DIV (256/64)", Runner(opcodes.opDiv).run, .{ .hooks = .{ .before_each = resetDivSmall } });
    if (m.matchesFilter("OP_DIV (zero)", filter)) try bench.add("OP_DIV (zero)", Runner(opcodes.opDiv).run, .{ .hooks = .{ .before_each = resetDivZero } });
    if (m.matchesFilter("OP_SDIV", filter)) try bench.add("OP_SDIV", Runner(opcodes.opSdiv).run, .{ .hooks = .{ .before_each = resetSdiv } });
    if (m.matchesFilter("OP_SDIV (neg/pos)", filter)) try bench.add("OP_SDIV (neg/pos)", Runner(opcodes.opSdiv).run, .{ .hooks = .{ .before_each = resetSdivNegative } });
    if (m.matchesFilter("OP_SDIV (neg/neg)", filter)) try bench.add("OP_SDIV (neg/neg)", Runner(opcodes.opSdiv).run, .{ .hooks = .{ .before_each = resetSdivBothNeg } });
    if (m.matchesFilter("OP_MOD", filter)) try bench.add("OP_MOD", Runner(opcodes.opMod).run, .{ .hooks = .{ .before_each = resetMod } });
    if (m.matchesFilter("OP_MOD (256/64)", filter)) try bench.add("OP_MOD (256/64)", Runner(opcodes.opMod).run, .{ .hooks = .{ .before_each = resetModSmall } });
    if (m.matchesFilter("OP_MOD (zero)", filter)) try bench.add("OP_MOD (zero)", Runner(opcodes.opMod).run, .{ .hooks = .{ .before_each = resetModZero } });
    if (m.matchesFilter("OP_SMOD", filter)) try bench.add("OP_SMOD", Runner(opcodes.opSmod).run, .{ .hooks = .{ .before_each = resetSmod } });
    if (m.matchesFilter("OP_SMOD (neg div)", filter)) try bench.add("OP_SMOD (neg div)", Runner(opcodes.opSmod).run, .{ .hooks = .{ .before_each = resetSmodNegative } });
    if (m.matchesFilter("OP_SIGNEXTEND", filter)) try bench.add("OP_SIGNEXTEND", Runner(opcodes.opSignextend).run, .{ .hooks = .{ .before_each = resetSignextend } });
    if (m.matchesFilter("OP_SIGNEXTEND (0-3)", filter)) try bench.add("OP_SIGNEXTEND (0-3)", Runner(opcodes.opSignextend).run, .{ .hooks = .{ .before_each = resetSignextendLow } });
    if (m.matchesFilter("OP_SIGNEXTEND (28-31)", filter)) try bench.add("OP_SIGNEXTEND (28-31)", Runner(opcodes.opSignextend).run, .{ .hooks = .{ .before_each = resetSignextendHigh } });
    if (m.matchesFilter("OP_ADDMOD", filter)) try bench.add("OP_ADDMOD", Runner(opcodes.opAddmod).run, .{ .hooks = .{ .before_each = resetAddmod } });
    if (m.matchesFilter("OP_ADDMOD (MAX)", filter)) try bench.add("OP_ADDMOD (MAX)", Runner(opcodes.opAddmod).run, .{ .hooks = .{ .before_each = resetAddmodOverflow } });
    if (m.matchesFilter("OP_MULMOD", filter)) try bench.add("OP_MULMOD", Runner(opcodes.opMulmod).run, .{ .hooks = .{ .before_each = resetMulmod } });
    if (m.matchesFilter("OP_MULMOD (MAX)", filter)) try bench.add("OP_MULMOD (MAX)", Runner(opcodes.opMulmod).run, .{ .hooks = .{ .before_each = resetMulmodMax } });
    if (m.matchesFilter("OP_EXP (1B)", filter)) try bench.add("OP_EXP (1B)", Runner(opcodes.opExp).run, .{ .hooks = .{ .before_each = resetExpSmall } });
    if (m.matchesFilter("OP_EXP (32B)", filter)) try bench.add("OP_EXP (32B)", Runner(opcodes.opExp).run, .{ .hooks = .{ .before_each = resetExpLarge } });
}

pub fn gasCost(name: []const u8) ?f64 {
    if (std.mem.startsWith(u8, name, "OP_ADDMOD")) return @floatFromInt(m.g_instruction_table[bytecode.ADDMOD].base_gas);
    if (std.mem.startsWith(u8, name, "OP_ADD")) return @floatFromInt(m.g_instruction_table[bytecode.ADD].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SUB")) return @floatFromInt(m.g_instruction_table[bytecode.SUB].base_gas);
    if (std.mem.startsWith(u8, name, "OP_MULMOD")) return @floatFromInt(m.g_instruction_table[bytecode.MULMOD].base_gas);
    if (std.mem.startsWith(u8, name, "OP_MUL")) return @floatFromInt(m.g_instruction_table[bytecode.MUL].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SDIV")) return @floatFromInt(m.g_instruction_table[bytecode.SDIV].base_gas);
    if (std.mem.startsWith(u8, name, "OP_DIV")) return @floatFromInt(m.g_instruction_table[bytecode.DIV].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SMOD")) return @floatFromInt(m.g_instruction_table[bytecode.SMOD].base_gas);
    if (std.mem.startsWith(u8, name, "OP_MOD")) return @floatFromInt(m.g_instruction_table[bytecode.MOD].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SIGNEXTEND")) return @floatFromInt(m.g_instruction_table[bytecode.SIGNEXTEND].base_gas);
    if (std.mem.startsWith(u8, name, "OP_EXP")) {
        const base_gas: f64 = @floatFromInt(m.g_instruction_table[bytecode.EXP].base_gas);
        const exp_byte_gas: f64 = @floatFromInt(gas_costs.G_EXPBYTE);
        if (std.mem.indexOf(u8, name, "32B")) |_| return base_gas + exp_byte_gas * 32.0;
        return base_gas + exp_byte_gas;
    }
    return null;
}

pub fn category(name: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, name, "OP_ADD") or
        std.mem.startsWith(u8, name, "OP_SUB") or
        std.mem.startsWith(u8, name, "OP_MUL") or
        std.mem.startsWith(u8, name, "OP_DIV") or
        std.mem.startsWith(u8, name, "OP_SDIV") or
        std.mem.startsWith(u8, name, "OP_MOD") or
        std.mem.startsWith(u8, name, "OP_SMOD") or
        std.mem.startsWith(u8, name, "OP_SIGNEXTEND") or
        std.mem.startsWith(u8, name, "OP_EXP"))
        return "ARITHMETIC";
    return null;
}
