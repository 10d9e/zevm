const std = @import("std");
const interpreter = @import("interpreter");
const bytecode = @import("bytecode");
const m = @import("main.zig");

// ---------------------------------------------------------------------------
// Reset functions
// ---------------------------------------------------------------------------

fn resetAnd() void {
    m.setup(m.gasFor(bytecode.AND));
    m.fillRandom(m.PREFILL);
}
fn resetOr() void {
    m.setup(m.gasFor(bytecode.OR));
    m.fillRandom(m.PREFILL);
}
fn resetXor() void {
    m.setup(m.gasFor(bytecode.XOR));
    m.fillRandom(m.PREFILL);
}
fn resetNot() void {
    m.setup(m.gasFor(bytecode.NOT));
    m.fillRandom(m.PREFILL);
}
fn resetByte() void {
    m.setup(m.gasFor(bytecode.BYTE));
    m.fillBytePairs(m.PREFILL / 2);
}

fn resetShl() void {
    m.setup(m.gasFor(bytecode.SHL));
    m.fillShiftPairs(m.PREFILL / 2, 255);
}
fn resetShlSmall() void {
    m.setup(m.gasFor(bytecode.SHL));
    m.fillShiftPairs(m.PREFILL / 2, 63);
}
fn resetShr() void {
    m.setup(m.gasFor(bytecode.SHR));
    m.fillShiftPairs(m.PREFILL / 2, 255);
}
fn resetShrSmall() void {
    m.setup(m.gasFor(bytecode.SHR));
    m.fillShiftPairs(m.PREFILL / 2, 63);
}
fn resetSar() void {
    m.setup(m.gasFor(bytecode.SAR));
    m.fillShiftMixedPairs(m.PREFILL / 2, 255);
}
fn resetSarNegative() void {
    m.setup(m.gasFor(bytecode.SAR));
    m.fillShiftNegPairs(m.PREFILL / 2, 255);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn register(bench: anytype, filter: []const u8) !void {
    const opcodes = interpreter.opcodes;
    const Runner = m.OpRunner;

    if (m.matchesFilter("OP_AND", filter)) try bench.add("OP_AND", Runner(opcodes.opAnd).run, .{ .hooks = .{ .before_each = resetAnd } });
    if (m.matchesFilter("OP_OR", filter)) try bench.add("OP_OR", Runner(opcodes.opOr).run, .{ .hooks = .{ .before_each = resetOr } });
    if (m.matchesFilter("OP_XOR", filter)) try bench.add("OP_XOR", Runner(opcodes.opXor).run, .{ .hooks = .{ .before_each = resetXor } });
    if (m.matchesFilter("OP_NOT", filter)) try bench.add("OP_NOT", Runner(opcodes.opNot).run, .{ .hooks = .{ .before_each = resetNot } });
    if (m.matchesFilter("OP_BYTE", filter)) try bench.add("OP_BYTE", Runner(opcodes.opByte).run, .{ .hooks = .{ .before_each = resetByte } });
    if (m.matchesFilter("OP_SHL", filter)) try bench.add("OP_SHL", Runner(opcodes.opShl).run, .{ .hooks = .{ .before_each = resetShl } });
    if (m.matchesFilter("OP_SHL (0-63)", filter)) try bench.add("OP_SHL (0-63)", Runner(opcodes.opShl).run, .{ .hooks = .{ .before_each = resetShlSmall } });
    if (m.matchesFilter("OP_SHR", filter)) try bench.add("OP_SHR", Runner(opcodes.opShr).run, .{ .hooks = .{ .before_each = resetShr } });
    if (m.matchesFilter("OP_SHR (0-63)", filter)) try bench.add("OP_SHR (0-63)", Runner(opcodes.opShr).run, .{ .hooks = .{ .before_each = resetShrSmall } });
    if (m.matchesFilter("OP_SAR", filter)) try bench.add("OP_SAR", Runner(opcodes.opSar).run, .{ .hooks = .{ .before_each = resetSar } });
    if (m.matchesFilter("OP_SAR (negative)", filter)) try bench.add("OP_SAR (negative)", Runner(opcodes.opSar).run, .{ .hooks = .{ .before_each = resetSarNegative } });
}

pub fn gasCost(name: []const u8) ?f64 {
    if (std.mem.startsWith(u8, name, "OP_AND")) return @floatFromInt(m.g_instruction_table[bytecode.AND].static_gas);
    if (std.mem.startsWith(u8, name, "OP_OR")) return @floatFromInt(m.g_instruction_table[bytecode.OR].static_gas);
    if (std.mem.startsWith(u8, name, "OP_XOR")) return @floatFromInt(m.g_instruction_table[bytecode.XOR].static_gas);
    if (std.mem.startsWith(u8, name, "OP_NOT")) return @floatFromInt(m.g_instruction_table[bytecode.NOT].static_gas);
    if (std.mem.startsWith(u8, name, "OP_BYTE")) return @floatFromInt(m.g_instruction_table[bytecode.BYTE].static_gas);
    if (std.mem.startsWith(u8, name, "OP_SHL")) return @floatFromInt(m.g_instruction_table[bytecode.SHL].static_gas);
    if (std.mem.startsWith(u8, name, "OP_SHR")) return @floatFromInt(m.g_instruction_table[bytecode.SHR].static_gas);
    if (std.mem.startsWith(u8, name, "OP_SAR")) return @floatFromInt(m.g_instruction_table[bytecode.SAR].static_gas);
    return null;
}

pub fn category(name: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, name, "OP_AND") or
        std.mem.startsWith(u8, name, "OP_OR") or
        std.mem.startsWith(u8, name, "OP_XOR") or
        std.mem.startsWith(u8, name, "OP_NOT") or
        std.mem.startsWith(u8, name, "OP_BYTE") or
        std.mem.startsWith(u8, name, "OP_SHL") or
        std.mem.startsWith(u8, name, "OP_SHR") or
        std.mem.startsWith(u8, name, "OP_SAR"))
        return "BITWISE";
    return null;
}
