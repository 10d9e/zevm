const std = @import("std");
const interpreter = @import("interpreter");
const bytecode = @import("bytecode");
const m = @import("main.zig");

// ---------------------------------------------------------------------------
// Reset functions
// ---------------------------------------------------------------------------

fn resetPop() void {
    m.setup(m.gasFor(bytecode.POP));
    m.fillRandom(m.OPS_PER_BATCH);
}

fn resetPush0() void {
    m.setup(m.gasFor(bytecode.PUSH0));
}

fn resetPush1() void {
    m.setup(m.gasFor(bytecode.PUSH1));
    m.g_pc = 0;
}

fn resetPush8() void {
    m.setup(m.gasFor(bytecode.PUSH8));
    m.g_pc = 0;
}

fn resetPush16() void {
    m.setup(m.gasFor(bytecode.PUSH16));
    m.g_pc = 0;
}

fn resetPush24() void {
    m.setup(m.gasFor(bytecode.PUSH24));
    m.g_pc = 0;
}

fn resetPush32() void {
    m.setup(m.gasFor(bytecode.PUSH32));
    m.g_pc = 0;
}

fn resetDup1() void {
    m.setup(m.gasFor(bytecode.DUP1));
    m.fillRandom(16);
}

fn resetDup16() void {
    m.setup(m.gasFor(bytecode.DUP16));
    m.fillRandom(16);
}

fn resetSwap1() void {
    m.setup(m.gasFor(bytecode.SWAP1));
    m.fillRandom(17);
}

fn resetSwap16() void {
    m.setup(m.gasFor(bytecode.SWAP16));
    m.fillRandom(17);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn register(bench: anytype, filter: []const u8) !void {
    const opcodes = interpreter.opcodes;
    const Runner = m.OpRunner;

    if (m.matchesFilter("OP_POP", filter)) try bench.add("OP_POP", Runner(opcodes.opPop).run, .{ .hooks = .{ .before_each = resetPop } });
    if (m.matchesFilter("OP_PUSH0", filter)) try bench.add("OP_PUSH0", Runner(opcodes.opPush0).run, .{ .hooks = .{ .before_each = resetPush0 } });
    if (m.matchesFilter("OP_PUSH1", filter)) try bench.add("OP_PUSH1", m.PushRunner(1).run, .{ .hooks = .{ .before_each = resetPush1 } });
    if (m.matchesFilter("OP_PUSH8", filter)) try bench.add("OP_PUSH8", m.PushRunner(8).run, .{ .hooks = .{ .before_each = resetPush8 } });
    if (m.matchesFilter("OP_PUSH16", filter)) try bench.add("OP_PUSH16", m.PushRunner(16).run, .{ .hooks = .{ .before_each = resetPush16 } });
    if (m.matchesFilter("OP_PUSH24", filter)) try bench.add("OP_PUSH24", m.PushRunner(24).run, .{ .hooks = .{ .before_each = resetPush24 } });
    if (m.matchesFilter("OP_PUSH32", filter)) try bench.add("OP_PUSH32", m.PushRunner(32).run, .{ .hooks = .{ .before_each = resetPush32 } });
    if (m.matchesFilter("OP_DUP1", filter)) try bench.add("OP_DUP1", m.DupRunner(1).run, .{ .hooks = .{ .before_each = resetDup1 } });
    if (m.matchesFilter("OP_DUP16", filter)) try bench.add("OP_DUP16", m.DupRunner(16).run, .{ .hooks = .{ .before_each = resetDup16 } });
    if (m.matchesFilter("OP_SWAP1", filter)) try bench.add("OP_SWAP1", m.SwapRunner(1).run, .{ .hooks = .{ .before_each = resetSwap1 } });
    if (m.matchesFilter("OP_SWAP16", filter)) try bench.add("OP_SWAP16", m.SwapRunner(16).run, .{ .hooks = .{ .before_each = resetSwap16 } });
}

pub fn gasCost(name: []const u8) ?f64 {
    if (std.mem.startsWith(u8, name, "OP_POP")) return @floatFromInt(m.g_instruction_table[bytecode.POP].base_gas);
    if (std.mem.startsWith(u8, name, "OP_PUSH0")) return @floatFromInt(m.g_instruction_table[bytecode.PUSH0].base_gas);
    if (std.mem.startsWith(u8, name, "OP_PUSH32")) return @floatFromInt(m.g_instruction_table[bytecode.PUSH32].base_gas);
    if (std.mem.startsWith(u8, name, "OP_PUSH24")) return @floatFromInt(m.g_instruction_table[bytecode.PUSH24].base_gas);
    if (std.mem.startsWith(u8, name, "OP_PUSH16")) return @floatFromInt(m.g_instruction_table[bytecode.PUSH16].base_gas);
    if (std.mem.startsWith(u8, name, "OP_PUSH8")) return @floatFromInt(m.g_instruction_table[bytecode.PUSH8].base_gas);
    if (std.mem.startsWith(u8, name, "OP_PUSH1")) return @floatFromInt(m.g_instruction_table[bytecode.PUSH1].base_gas);
    if (std.mem.startsWith(u8, name, "OP_DUP1")) return @floatFromInt(m.g_instruction_table[bytecode.DUP1].base_gas);
    if (std.mem.startsWith(u8, name, "OP_DUP16")) return @floatFromInt(m.g_instruction_table[bytecode.DUP16].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SWAP1")) return @floatFromInt(m.g_instruction_table[bytecode.SWAP1].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SWAP16")) return @floatFromInt(m.g_instruction_table[bytecode.SWAP16].base_gas);
    return null;
}

pub fn category(name: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, name, "OP_POP") or
        std.mem.startsWith(u8, name, "OP_PUSH") or
        std.mem.startsWith(u8, name, "OP_DUP") or
        std.mem.startsWith(u8, name, "OP_SWAP"))
        return "STACK";
    return null;
}
