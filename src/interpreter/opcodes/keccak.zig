const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const Memory = @import("../memory.zig").Memory;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const gas_costs = @import("../gas_costs.zig");

/// KECCAK256 opcode (0x20): Compute Keccak-256 hash
/// Stack: [offset, length] -> [hash]   Gas: 30 + 6 * num_words
pub inline fn opKeccak256(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;

    const offset = stack.peekUnsafe(0);
    const length = stack.peekUnsafe(1);

    // Check if values are too large
    if (offset > std.math.maxInt(usize) or length > std.math.maxInt(usize)) {
        return .memory_limit_oog;
    }

    const offset_usize: usize = @intCast(offset);
    const length_usize: usize = @intCast(length);

    // Calculate gas cost
    const num_words = gas_costs.toWordSize(length_usize);
    const hash_cost = gas_costs.G_KECCAK256 + (gas_costs.G_KECCAK256WORD * num_words);
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

    // Convert hash to U256 (big-endian, 4 bulk u64 reads)
    const U = primitives.U256;
    const value: U = (@as(U, std.mem.readInt(u64, hash[0..8], .big)) << 192) |
        (@as(U, std.mem.readInt(u64, hash[8..16], .big)) << 128) |
        (@as(U, std.mem.readInt(u64, hash[16..24], .big)) << 64) |
        @as(U, std.mem.readInt(u64, hash[24..32], .big));

    // Replace top 2 stack items with hash result
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = value;

    return .continue_;
}

test {
    _ = @import("keccak_tests.zig");
}
