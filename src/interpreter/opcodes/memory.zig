const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const Memory = @import("../memory.zig").Memory;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const gas_costs = @import("../gas_costs.zig");

fn memoryExpansionCost(current_words: usize, new_words: usize) u64 {
    if (new_words <= current_words) return 0;
    const new_cost = memoryCost(new_words);
    const current_cost = memoryCost(current_words);
    return new_cost - current_cost;
}

fn memoryCost(num_words: usize) u64 {
    const linear = num_words * gas_costs.G_MEMORY;
    const quadratic = (num_words * num_words) / 512;
    return @intCast(linear + quadratic);
}

fn toWordSize(size: usize) usize {
    return (std.math.add(usize, size, 31) catch return std.math.maxInt(usize)) / 32;
}

/// MLOAD opcode (0x51): Load word from memory
/// Stack: [offset] -> [value]   Gas: 3 + memory_expansion
pub inline fn opMload(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult {
    if (!stack.hasItems(1)) return .stack_underflow;
    if (!gas.spend(gas_costs.G_VERYLOW)) return .out_of_gas;

    const offset = stack.peekUnsafe(0);

    // Check if offset is too large
    if (offset > std.math.maxInt(usize) - 32) {
        return .memory_limit_oog;
    }

    const offset_usize: usize = @intCast(offset);
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

    // Read 32 bytes from memory as U256 (big-endian, 4 bulk u64 reads)
    const U = primitives.U256;
    const slice = memory.buffer.items[offset_usize..][0..32];
    const value: U = (@as(U, std.mem.readInt(u64, slice[0..8], .big)) << 192) |
        (@as(U, std.mem.readInt(u64, slice[8..16], .big)) << 128) |
        (@as(U, std.mem.readInt(u64, slice[16..24], .big)) << 64) |
        @as(U, std.mem.readInt(u64, slice[24..32], .big));

    stack.setTopUnsafe().* = value;
    return .continue_;
}

/// MSTORE opcode (0x52): Store word to memory
/// Stack: [offset, value] -> []   Gas: 3 + memory_expansion
pub inline fn opMstore(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(gas_costs.G_VERYLOW)) return .out_of_gas;

    const offset = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(2);

    // Check if offset is too large
    if (offset > std.math.maxInt(usize) - 32) {
        return .memory_limit_oog;
    }

    const offset_usize: usize = @intCast(offset);
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

    // Write 32 bytes to memory (big-endian, 4 bulk u64 writes)
    const dest = memory.buffer.items[offset_usize..][0..32];
    std.mem.writeInt(u64, dest[0..8], @truncate(value >> 192), .big);
    std.mem.writeInt(u64, dest[8..16], @truncate(value >> 128), .big);
    std.mem.writeInt(u64, dest[16..24], @truncate(value >> 64), .big);
    std.mem.writeInt(u64, dest[24..32], @truncate(value), .big);

    return .continue_;
}

/// MSTORE8 opcode (0x53): Store byte to memory
/// Stack: [offset, value] -> []   Gas: 3 + memory_expansion
pub inline fn opMstore8(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(gas_costs.G_VERYLOW)) return .out_of_gas;

    const offset = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(2);

    // Check if offset is too large
    if (offset > std.math.maxInt(usize)) {
        return .memory_limit_oog;
    }

    const offset_usize: usize = @intCast(offset);
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
    memory.buffer.items[offset_usize] = @intCast(value & 0xFF);

    return .continue_;
}

/// MSIZE opcode (0x59): Get memory size
/// Stack: [] -> [size]   Gas: 2
pub inline fn opMsize(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult {
    if (!stack.hasSpace(1)) return .stack_overflow;
    if (!gas.spend(gas_costs.G_BASE)) return .out_of_gas;
    stack.pushUnsafe(memory.size());
    return .continue_;
}

/// MCOPY opcode (0x5E): Copy memory (Cancun+)
/// Stack: [dest, src, length] -> []   Gas: 3 + copy_cost + memory_expansion
pub inline fn opMcopy(stack: *Stack, gas: *Gas, memory: *Memory) InstructionResult {
    if (!stack.hasItems(3)) return .stack_underflow;
    if (!gas.spend(gas_costs.G_VERYLOW)) return .out_of_gas;

    const dest = stack.peekUnsafe(0);
    const src = stack.peekUnsafe(1);
    const length = stack.peekUnsafe(2);
    stack.shrinkUnsafe(3);

    // Check if values are too large
    if (dest > std.math.maxInt(usize) or src > std.math.maxInt(usize) or length > std.math.maxInt(usize)) {
        return .memory_limit_oog;
    }

    const dest_usize: usize = @intCast(dest);
    const src_usize: usize = @intCast(src);
    const length_usize: usize = @intCast(length);

    // Calculate copy cost: 3 gas per word
    const num_words = toWordSize(length_usize);
    const copy_cost = gas_costs.G_COPY * num_words;
    if (!gas.spend(@intCast(copy_cost))) return .out_of_gas;

    // Calculate memory expansion cost
    const dest_end = std.math.add(usize, dest_usize, length_usize) catch return .memory_limit_oog;
    const src_end = std.math.add(usize, src_usize, length_usize) catch return .memory_limit_oog;
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
