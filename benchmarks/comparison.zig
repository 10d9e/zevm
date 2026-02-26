const std = @import("std");
const interpreter = @import("interpreter");
const bytecode = @import("bytecode");
const m = @import("main.zig");

const U256 = @import("primitives").U256;
const MAX = std.math.maxInt(U256);

// ---------------------------------------------------------------------------
// Reset functions
// ---------------------------------------------------------------------------

fn resetLt() void {
    m.setup(m.gasFor(bytecode.LT));
    m.fillRandomPairs(m.PREFILL / 2);
}
fn resetGt() void {
    m.setup(m.gasFor(bytecode.GT));
    m.fillRandomPairs(m.PREFILL / 2);
}
fn resetEq() void {
    m.setup(m.gasFor(bytecode.EQ));
    m.fillRandomPairs(m.PREFILL / 2);
}
fn resetEqSame() void {
    m.setup(m.gasFor(bytecode.EQ));
    m.fillConstantPairs(m.PREFILL / 2, MAX, MAX);
}
fn resetSlt() void {
    m.setup(m.gasFor(bytecode.SLT));
    m.fillRandomPairs(m.PREFILL / 2);
}
fn resetSltNeg() void {
    m.setup(m.gasFor(bytecode.SLT));
    m.fillNegativePairs(m.PREFILL / 2, m.g_divisor_128);
}
fn resetSgt() void {
    m.setup(m.gasFor(bytecode.SGT));
    m.fillRandomPairs(m.PREFILL / 2);
}
fn resetSgtNeg() void {
    m.setup(m.gasFor(bytecode.SGT));
    m.fillNegativePairs(m.PREFILL / 2, m.g_divisor_128);
}
fn resetIsZero() void {
    m.setup(m.gasFor(bytecode.ISZERO));
    m.fillRandom(m.PREFILL);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn register(bench: anytype, filter: []const u8) !void {
    const opcodes = interpreter.opcodes;
    const Runner = m.OpRunner;

    if (m.matchesFilter("OP_LT", filter)) try bench.add("OP_LT", Runner(opcodes.opLt).run, .{ .hooks = .{ .before_each = resetLt } });
    if (m.matchesFilter("OP_GT", filter)) try bench.add("OP_GT", Runner(opcodes.opGt).run, .{ .hooks = .{ .before_each = resetGt } });
    if (m.matchesFilter("OP_EQ", filter)) try bench.add("OP_EQ", Runner(opcodes.opEq).run, .{ .hooks = .{ .before_each = resetEq } });
    if (m.matchesFilter("OP_EQ (same)", filter)) try bench.add("OP_EQ (same)", Runner(opcodes.opEq).run, .{ .hooks = .{ .before_each = resetEqSame } });
    if (m.matchesFilter("OP_SLT", filter)) try bench.add("OP_SLT", Runner(opcodes.opSlt).run, .{ .hooks = .{ .before_each = resetSlt } });
    if (m.matchesFilter("OP_SLT (negative)", filter)) try bench.add("OP_SLT (negative)", Runner(opcodes.opSlt).run, .{ .hooks = .{ .before_each = resetSltNeg } });
    if (m.matchesFilter("OP_SGT", filter)) try bench.add("OP_SGT", Runner(opcodes.opSgt).run, .{ .hooks = .{ .before_each = resetSgt } });
    if (m.matchesFilter("OP_SGT (negative)", filter)) try bench.add("OP_SGT (negative)", Runner(opcodes.opSgt).run, .{ .hooks = .{ .before_each = resetSgtNeg } });
    if (m.matchesFilter("OP_ISZERO", filter)) try bench.add("OP_ISZERO", Runner(opcodes.opIsZero).run, .{ .hooks = .{ .before_each = resetIsZero } });
}

pub fn gasCost(name: []const u8) ?f64 {
    if (std.mem.startsWith(u8, name, "OP_ISZERO")) return @floatFromInt(m.g_instruction_table[bytecode.ISZERO].static_gas);
    if (std.mem.startsWith(u8, name, "OP_LT")) return @floatFromInt(m.g_instruction_table[bytecode.LT].static_gas);
    if (std.mem.startsWith(u8, name, "OP_GT")) return @floatFromInt(m.g_instruction_table[bytecode.GT].static_gas);
    if (std.mem.startsWith(u8, name, "OP_SLT")) return @floatFromInt(m.g_instruction_table[bytecode.SLT].static_gas);
    if (std.mem.startsWith(u8, name, "OP_SGT")) return @floatFromInt(m.g_instruction_table[bytecode.SGT].static_gas);
    if (std.mem.startsWith(u8, name, "OP_EQ")) return @floatFromInt(m.g_instruction_table[bytecode.EQ].static_gas);
    return null;
}

pub fn category(name: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, name, "OP_LT") or
        std.mem.startsWith(u8, name, "OP_GT") or
        std.mem.startsWith(u8, name, "OP_SLT") or
        std.mem.startsWith(u8, name, "OP_SGT") or
        std.mem.startsWith(u8, name, "OP_EQ") or
        std.mem.startsWith(u8, name, "OP_ISZERO"))
        return "COMPARISON";
    return null;
}
