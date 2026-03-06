const std = @import("std");
const primitives = @import("primitives");
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const gas_costs = @import("../gas_costs.zig");

fn memoryCostWords(num_words: usize) u64 {
    const n: u64 = @intCast(num_words);
    // Use saturating arithmetic: a huge offset must yield OOG, not a panic.
    const linear = std.math.mul(u64, n, gas_costs.G_MEMORY) catch return std.math.maxInt(u64);
    const quadratic = (std.math.mul(u64, n, n) catch return std.math.maxInt(u64)) / 512;
    return std.math.add(u64, linear, quadratic) catch std.math.maxInt(u64);
}

fn memoryExpansionCost(current_size: usize, new_size: usize) u64 {
    if (new_size <= current_size) return 0;
    const current_words = (current_size + 31) / 32;
    const new_words = (std.math.add(usize, new_size, 31) catch return std.math.maxInt(u64)) / 32;
    return memoryCostWords(new_words) - memoryCostWords(current_words);
}

fn expandMemory(ctx: *InstructionContext, new_size: usize) bool {
    const expansion_cost = memoryExpansionCost(ctx.interpreter.memory.size(), new_size);
    if (!ctx.interpreter.gas.spend(expansion_cost)) return false;
    // EVM memory is always a multiple of 32 bytes; new bytes must be zero-initialized.
    const new_words = (std.math.add(usize, new_size, 31) catch return false) / 32;
    const aligned_size = new_words * 32;
    if (aligned_size > ctx.interpreter.memory.size()) {
        const old_size = ctx.interpreter.memory.size();
        ctx.interpreter.memory.buffer.resize(std.heap.c_allocator, aligned_size) catch return false;
        @memset(ctx.interpreter.memory.buffer.items[old_size..aligned_size], 0);
    }
    return true;
}

/// MLOAD opcode (0x51): Load word from memory
/// Stack: [offset] -> [value]   Gas: 3 (G_VERYLOW, dispatch) + memory_expansion
pub fn opMload(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }

    const offset = stack.peekUnsafe(0);
    if (offset > std.math.maxInt(usize) - 32) {
        ctx.interpreter.halt(.memory_limit_oog);
        return;
    }

    const offset_usize: usize = @intCast(offset);
    const new_size = offset_usize + 32;

    if (!expandMemory(ctx, new_size)) {
        ctx.interpreter.halt(.out_of_gas);
        return;
    }

    const U = primitives.U256;
    const slice = ctx.interpreter.memory.buffer.items[offset_usize..][0..32];
    const value: U = (@as(U, std.mem.readInt(u64, slice[0..8], .big)) << 192) |
        (@as(U, std.mem.readInt(u64, slice[8..16], .big)) << 128) |
        (@as(U, std.mem.readInt(u64, slice[16..24], .big)) << 64) |
        @as(U, std.mem.readInt(u64, slice[24..32], .big));

    stack.setTopUnsafe().* = value;
}

/// MSTORE opcode (0x52): Store word to memory
/// Stack: [offset, value] -> []   Gas: 3 (G_VERYLOW, dispatch) + memory_expansion
pub fn opMstore(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }

    const offset = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(2);

    if (offset > std.math.maxInt(usize) - 32) {
        ctx.interpreter.halt(.memory_limit_oog);
        return;
    }

    const offset_usize: usize = @intCast(offset);
    const new_size = offset_usize + 32;

    if (!expandMemory(ctx, new_size)) {
        ctx.interpreter.halt(.out_of_gas);
        return;
    }

    const dest = ctx.interpreter.memory.buffer.items[offset_usize..][0..32];
    std.mem.writeInt(u64, dest[0..8], @truncate(value >> 192), .big);
    std.mem.writeInt(u64, dest[8..16], @truncate(value >> 128), .big);
    std.mem.writeInt(u64, dest[16..24], @truncate(value >> 64), .big);
    std.mem.writeInt(u64, dest[24..32], @truncate(value), .big);
}

/// MSTORE8 opcode (0x53): Store byte to memory
/// Stack: [offset, value] -> []   Gas: 3 (G_VERYLOW, dispatch) + memory_expansion
pub fn opMstore8(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }

    const offset = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(2);

    if (offset > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog);
        return;
    }

    const offset_usize: usize = @intCast(offset);
    const new_size = offset_usize + 1;

    if (!expandMemory(ctx, new_size)) {
        ctx.interpreter.halt(.out_of_gas);
        return;
    }

    ctx.interpreter.memory.buffer.items[offset_usize] = @intCast(value & 0xFF);
}

/// MSIZE opcode (0x59): Get memory size in bytes
/// Stack: [] -> [size]   Gas: 2 (G_BASE, charged by dispatch)
pub fn opMsize(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) {
        ctx.interpreter.halt(.stack_overflow);
        return;
    }
    stack.pushUnsafe(ctx.interpreter.memory.size());
}

/// MCOPY opcode (0x5E): Copy memory region (Cancun+)
/// Stack: [dest, src, length] -> []   Gas: 3 (G_VERYLOW, dispatch) + copy_cost + memory_expansion
pub fn opMcopy(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(3)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }

    const dest = stack.peekUnsafe(0);
    const src = stack.peekUnsafe(1);
    const length = stack.peekUnsafe(2);
    stack.shrinkUnsafe(3);

    // Zero-length MCOPY is a no-op (no copy cost, no memory expansion) even for huge offsets.
    if (length == 0) return;

    if (dest > std.math.maxInt(usize) or src > std.math.maxInt(usize) or length > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog);
        return;
    }

    const dest_usize: usize = @intCast(dest);
    const src_usize: usize = @intCast(src);
    const length_usize: usize = @intCast(length);

    // Dynamic: copy cost (3 gas per word)
    const num_words = (std.math.add(usize, length_usize, 31) catch {
        ctx.interpreter.halt(.memory_limit_oog);
        return;
    }) / 32;
    const copy_cost: u64 = gas_costs.G_COPY * @as(u64, @intCast(num_words));
    if (!ctx.interpreter.gas.spend(copy_cost)) {
        ctx.interpreter.halt(.out_of_gas);
        return;
    }

    // Dynamic: memory expansion to cover both src and dest regions
    {
        const dest_end = std.math.add(usize, dest_usize, length_usize) catch {
            ctx.interpreter.halt(.memory_limit_oog);
            return;
        };
        const src_end = std.math.add(usize, src_usize, length_usize) catch {
            ctx.interpreter.halt(.memory_limit_oog);
            return;
        };
        const max_end = @max(dest_end, src_end);
        if (!expandMemory(ctx, max_end)) {
            ctx.interpreter.halt(.out_of_gas);
            return;
        }

        // Use memmove semantics: copyBackwards when dest > src to handle overlap correctly.
        const mem = ctx.interpreter.memory.buffer.items;
        if (dest_usize > src_usize) {
            std.mem.copyBackwards(u8, mem[dest_usize..][0..length_usize], mem[src_usize..][0..length_usize]);
        } else {
            std.mem.copyForwards(u8, mem[dest_usize..][0..length_usize], mem[src_usize..][0..length_usize]);
        }
    }
}

test {
    _ = @import("memory_tests.zig");
}
