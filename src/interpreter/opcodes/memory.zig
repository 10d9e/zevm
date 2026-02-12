const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const Memory = @import("../memory.zig").Memory;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;

pub const GAS_VERYLOW: u64 = 3;
pub const GAS_BASE: u64 = 2;
pub const GAS_MEMORY: u64 = 3;

/// Calculate memory expansion cost
fn memoryExpansionCost(current_words: usize, new_words: usize) u64 {
    if (new_words <= current_words) return 0;
    const new_cost = memoryCost(new_words);
    const current_cost = memoryCost(current_words);
    return new_cost - current_cost;
}

fn memoryCost(num_words: usize) u64 {
    const linear = num_words * GAS_MEMORY;
    const quadratic = (num_words * num_words) / 512;
    return @intCast(linear + quadratic);
}

fn toWordSize(size: usize) usize {
    return (size + 31) / 32;
}

/// MLOAD opcode (0x51): Load word from memory
/// Stack: [offset] -> [value]   Gas: 3 + memory_expansion
pub inline fn opMload(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult {
    if (!stack.hasItems(1)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;

    const offset = stack.peekUnsafe(0);

    // Check if offset is too large
    const offset_u64 = offset.toU64() orelse return .memory_limit_oog;
    if (offset_u64 > std.math.maxInt(usize) - 32) return .memory_limit_oog;
    const offset_usize: usize = @intCast(offset_u64);
    const new_size = offset_usize + 32;

    // Calculate memory expansion cost
    const current_words = toWordSize(memory.size());
    const new_words = toWordSize(new_size);
    const expansion_cost = memoryExpansionCost(current_words, new_words);
    if (!gas.spend(expansion_cost)) return .out_of_gas;

    // Expand memory if needed
    if (new_size > memory.size()) {
        memory.buffer.resize(std.heap.c_allocator, new_size) catch return .memory_limit_oog;
    }

    // Read 32 bytes from memory as U256 (big-endian)
    const slice = memory.buffer.items[offset_usize..][0..32];
    const value = primitives.U256.fromBytes(slice.*);

    stack.setTopUnsafe().* = value;
    return .continue_;
}

/// MSTORE opcode (0x52): Store word to memory
/// Stack: [offset, value] -> []   Gas: 3 + memory_expansion
pub inline fn opMstore(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;

    const offset = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(2);

    // Check if offset is too large
    const offset_u64 = offset.toU64() orelse return .memory_limit_oog;
    if (offset_u64 > std.math.maxInt(usize) - 32) return .memory_limit_oog;
    const offset_usize: usize = @intCast(offset_u64);
    const new_size = offset_usize + 32;

    // Calculate memory expansion cost
    const current_words = toWordSize(memory.size());
    const new_words = toWordSize(new_size);
    const expansion_cost = memoryExpansionCost(current_words, new_words);
    if (!gas.spend(expansion_cost)) return .out_of_gas;

    // Expand memory if needed
    if (new_size > memory.size()) {
        memory.buffer.resize(std.heap.c_allocator, new_size) catch return .memory_limit_oog;
    }

    // Write 32 bytes to memory (big-endian)
    const dest = memory.buffer.items[offset_usize..][0..32];
    dest.* = value.toBytes();

    return .continue_;
}

/// MSTORE8 opcode (0x53): Store byte to memory
/// Stack: [offset, value] -> []   Gas: 3 + memory_expansion
pub inline fn opMstore8(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;

    const offset = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(2);

    // Check if offset is too large
    const offset_u64 = offset.toU64() orelse return .memory_limit_oog;
    const offset_usize: usize = @intCast(offset_u64);
    const new_size = offset_usize + 1;

    // Calculate memory expansion cost
    const current_words = toWordSize(memory.size());
    const new_words = toWordSize(new_size);
    const expansion_cost = memoryExpansionCost(current_words, new_words);
    if (!gas.spend(expansion_cost)) return .out_of_gas;

    // Expand memory if needed
    if (new_size > memory.size()) {
        memory.buffer.resize(std.heap.c_allocator, new_size) catch return .memory_limit_oog;
    }

    // Write lowest byte
    memory.buffer.items[offset_usize] = @truncate(value.val);

    return .continue_;
}

/// MSIZE opcode (0x59): Get memory size
/// Stack: [] -> [size]   Gas: 2
pub inline fn opMsize(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult {
    if (!stack.hasSpace(1)) return .stack_overflow;
    if (!gas.spend(GAS_BASE)) return .out_of_gas;
    stack.pushUnsafe(primitives.U256.from(memory.size()));
    return .continue_;
}

/// MCOPY opcode (0x5E): Copy memory (Cancun+)
/// Stack: [dest, src, length] -> []   Gas: 3 + copy_cost + memory_expansion
pub inline fn opMcopy(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult {
    if (!stack.hasItems(3)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;

    const dest = stack.peekUnsafe(0);
    const src = stack.peekUnsafe(1);
    const length = stack.peekUnsafe(2);
    stack.shrinkUnsafe(3);

    // Check if values are too large
    const dest_u64 = dest.toU64() orelse return .memory_limit_oog;
    const src_u64 = src.toU64() orelse return .memory_limit_oog;
    const length_u64 = length.toU64() orelse return .memory_limit_oog;
    const dest_usize: usize = @intCast(dest_u64);
    const src_usize: usize = @intCast(src_u64);
    const length_usize: usize = @intCast(length_u64);

    // Calculate copy cost: 3 gas per word
    const num_words = toWordSize(length_usize);
    const copy_cost = 3 * num_words;
    if (!gas.spend(@intCast(copy_cost))) return .out_of_gas;

    // Calculate memory expansion cost
    const dest_end = dest_usize + length_usize;
    const src_end = src_usize + length_usize;
    const max_end = @max(dest_end, src_end);
    const current_words = toWordSize(memory.size());
    const new_words = toWordSize(max_end);
    const expansion_cost = memoryExpansionCost(current_words, new_words);
    if (!gas.spend(expansion_cost)) return .out_of_gas;

    // Expand memory if needed
    if (max_end > memory.size()) {
        memory.buffer.resize(std.heap.c_allocator, max_end) catch return .memory_limit_oog;
    }

    // Copy memory (handle overlapping regions correctly)
    if (length_usize > 0) {
        std.mem.copyForwards(u8, memory.buffer.items[dest_usize..][0..length_usize], memory.buffer.items[src_usize..][0..length_usize]);
    }

    return .continue_;
}

test {
    _ = @import("memory_tests.zig");
}
