const std = @import("std");
const m = @import("main.zig");

// ---------------------------------------------------------------------------
// Reset functions
// ---------------------------------------------------------------------------

fn resetKeccak32() void {
    m.setupMem(36); // 30 + 6*1
    m.preExpandMemory(32);
}
fn resetKeccak256() void {
    m.setupMem(78); // 30 + 6*8
    m.preExpandMemory(256);
}
fn resetKeccak1K() void {
    m.setupMem(222); // 30 + 6*32
    m.preExpandMemory(1024);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn register(bench: anytype, filter: []const u8) !void {
    if (m.matchesFilter("OP_KECCAK256 (32B)", filter)) try bench.add("OP_KECCAK256 (32B)", m.KeccakRunner(32).run, .{ .hooks = .{ .before_each = resetKeccak32 } });
    if (m.matchesFilter("OP_KECCAK256 (256B)", filter)) try bench.add("OP_KECCAK256 (256B)", m.KeccakRunner(256).run, .{ .hooks = .{ .before_each = resetKeccak256 } });
    if (m.matchesFilter("OP_KECCAK256 (1KB)", filter)) try bench.add("OP_KECCAK256 (1KB)", m.KeccakRunner(1024).run, .{ .hooks = .{ .before_each = resetKeccak1K } });
}

pub fn gasCost(name: []const u8) ?f64 {
    if (std.mem.startsWith(u8, name, "OP_KECCAK256")) {
        if (std.mem.indexOf(u8, name, "1KB")) |_| return 222.0;
        if (std.mem.indexOf(u8, name, "256B")) |_| return 78.0;
        return 36.0;
    }
    return null;
}

pub fn category(name: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, name, "OP_KECCAK"))
        return "KECCAK";
    return null;
}
