const std = @import("std");
const interpreter = @import("interpreter");
const bytecode = @import("bytecode");
const m = @import("main.zig");

const U256 = @import("primitives").U256;

// ---------------------------------------------------------------------------
// Memory-specific fill helpers
// ---------------------------------------------------------------------------

fn fillMloadChain() void {
    const num_slots = m.MEM_SIZE / 32;
    for (0..num_slots) |i| {
        const next_offset = ((i + 1) % num_slots) * 32;
        var bytes: [32]u8 = [_]u8{0} ** 32;
        bytes[31] = @truncate(next_offset);
        bytes[30] = @truncate(next_offset >> 8);
        @memcpy(m.g_memory.buffer.items[i * 32 ..][0..32], &bytes);
    }
    m.g_stack.pushUnsafe(@as(U256, 0));
}

fn fillMstoreOffsets(count: usize) void {
    for (0..count) |i| {
        m.g_stack.pushUnsafe(m.g_values[i & (m.NUM_VALUES - 1)]);
        m.g_stack.pushUnsafe(@as(U256, (i * 32) % (m.MEM_SIZE - 32)));
    }
}

fn fillMstore8Offsets(count: usize) void {
    for (0..count) |i| {
        m.g_stack.pushUnsafe(m.g_values[i & (m.NUM_VALUES - 1)]);
        m.g_stack.pushUnsafe(@as(U256, i % m.MEM_SIZE));
    }
}

// ---------------------------------------------------------------------------
// Reset functions
// ---------------------------------------------------------------------------

fn resetMload() void {
    m.setupMem(m.gasFor(bytecode.MLOAD));
    m.preExpandMemory(m.MEM_SIZE);
    fillMloadChain();
}

fn resetMstore() void {
    m.setupMem(m.gasFor(bytecode.MSTORE));
    m.preExpandMemory(m.MEM_SIZE);
    fillMstoreOffsets(m.PREFILL / 2);
}

fn resetMstore8() void {
    m.setupMem(m.gasFor(bytecode.MSTORE8));
    m.preExpandMemory(m.MEM_SIZE);
    fillMstore8Offsets(m.PREFILL / 2);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn register(bench: anytype, filter: []const u8) !void {
    const opcodes = interpreter.opcodes;
    const Runner = m.MemOpRunner;

    if (m.matchesFilter("OP_MLOAD", filter)) try bench.add("OP_MLOAD", Runner(opcodes.opMload).run, .{ .hooks = .{ .before_each = resetMload } });
    if (m.matchesFilter("OP_MSTORE", filter)) try bench.add("OP_MSTORE", Runner(opcodes.opMstore).run, .{ .hooks = .{ .before_each = resetMstore } });
    if (m.matchesFilter("OP_MSTORE8", filter)) try bench.add("OP_MSTORE8", Runner(opcodes.opMstore8).run, .{ .hooks = .{ .before_each = resetMstore8 } });
}

pub fn gasCost(name: []const u8) ?f64 {
    if (std.mem.startsWith(u8, name, "OP_MSTORE8")) return @floatFromInt(m.g_instruction_table[bytecode.MSTORE8].static_gas);
    if (std.mem.startsWith(u8, name, "OP_MSTORE")) return @floatFromInt(m.g_instruction_table[bytecode.MSTORE].static_gas);
    if (std.mem.startsWith(u8, name, "OP_MLOAD")) return @floatFromInt(m.g_instruction_table[bytecode.MLOAD].static_gas);
    return null;
}

pub fn category(name: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, name, "OP_MLOAD") or
        std.mem.startsWith(u8, name, "OP_MSTORE"))
        return "MEMORY";
    return null;
}
