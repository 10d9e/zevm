const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const Memory = @import("../memory.zig").Memory;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;

pub const GAS_KECCAK256: u64 = 30;
pub const GAS_KECCAK256WORD: u64 = 6;

fn toWordSize(size: usize) usize {
    return (size + 31) / 32;
}

/// KECCAK256 opcode (0x20): Compute Keccak-256 hash
/// Stack: [offset, length] -> [hash]   Gas: 30 + 6 * num_words
pub inline fn opKeccak256(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;

    const offset = stack.peekUnsafe(0);
    const length = stack.peekUnsafe(1);

    // Check if values are too large
    const offset_u64 = offset.toU64() orelse return .memory_limit_oog;
    const length_u64 = length.toU64() orelse return .memory_limit_oog;
    const offset_usize: usize = @intCast(offset_u64);
    const length_usize: usize = @intCast(length_u64);

    // Calculate gas cost
    const num_words = toWordSize(length_usize);
    const hash_cost = GAS_KECCAK256 + (GAS_KECCAK256WORD * num_words);
    if (!gas.spend(@intCast(hash_cost))) return .out_of_gas;

    // Check memory expansion
    const end = offset_usize + length_usize;
    if (end > memory.size()) {
        // Memory expansion cost is already charged by memory access opcodes
        // But we need to ensure memory is large enough
        return .memory_limit_oog;
    }

    // Get data from memory
    const data = memory.buffer.items[offset_usize..end];

    // Compute Keccak-256 hash
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(data, &hash, .{});

    // Convert hash to U256 (big-endian)
    const value = primitives.U256.fromBytes(hash);

    // Replace top 2 stack items with hash result
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = value;

    return .continue_;
}

test {
    _ = @import("keccak_tests.zig");
}
