const std = @import("std");
const primitives = @import("primitives");
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const gas_costs = @import("../gas_costs.zig");

// ---------------------------------------------------------------------------
// Memory expansion helper
// ---------------------------------------------------------------------------

fn memoryCostWords(num_words: usize) u64 {
    const n: u64 = @intCast(num_words);
    const linear = std.math.mul(u64, n, gas_costs.G_MEMORY) catch return std.math.maxInt(u64);
    const quadratic = (std.math.mul(u64, n, n) catch return std.math.maxInt(u64)) / 512;
    return std.math.add(u64, linear, quadratic) catch std.math.maxInt(u64);
}

fn expandMemory(ctx: *InstructionContext, new_size: usize) bool {
    if (new_size == 0) return true;
    const current = ctx.interpreter.memory.size();
    if (new_size <= current) return true;
    const current_words = (current + 31) / 32;
    const new_words = (std.math.add(usize, new_size, 31) catch return false) / 32;
    if (new_words > current_words) {
        const cost = memoryCostWords(new_words) - memoryCostWords(current_words);
        if (!ctx.interpreter.gas.spend(cost)) return false;
    }
    const aligned_size = new_words * 32;
    const old_size = ctx.interpreter.memory.size();
    ctx.interpreter.memory.buffer.resize(std.heap.c_allocator, aligned_size) catch return false;
    @memset(ctx.interpreter.memory.buffer.items[old_size..aligned_size], 0);
    return true;
}

// ---------------------------------------------------------------------------
// RETURN / REVERT / INVALID
// ---------------------------------------------------------------------------

/// RETURN (0xF3): Stop execution, return data from memory.
/// Stack: [offset, size] -> []   Gas: 0 static + memory_expansion
pub fn opReturn(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }

    const offset = stack.peekUnsafe(0);
    const size = stack.peekUnsafe(1);
    stack.shrinkUnsafe(2);

    if (size == 0) {
        ctx.interpreter.return_data.data = &[_]u8{};
        ctx.interpreter.halt(.@"return");
        return;
    }

    if (offset > std.math.maxInt(usize) or size > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog);
        return;
    }

    const offset_u: usize = @intCast(offset);
    const size_u: usize = @intCast(size);

    const return_end = std.math.add(usize, offset_u, size_u) catch {
        ctx.interpreter.halt(.memory_limit_oog);
        return;
    };
    if (!expandMemory(ctx, return_end)) {
        ctx.interpreter.halt(.out_of_gas);
        return;
    }

    ctx.interpreter.return_data.data = ctx.interpreter.memory.buffer.items[offset_u..return_end];
    ctx.interpreter.halt(.@"return");
}

/// REVERT (0xFD): Stop execution and revert state, return data from memory.
/// Stack: [offset, size] -> []   Gas: 0 static + memory_expansion (Byzantium+)
pub fn opRevert(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }

    const offset = stack.peekUnsafe(0);
    const size = stack.peekUnsafe(1);
    stack.shrinkUnsafe(2);

    if (size == 0) {
        ctx.interpreter.return_data.data = &[_]u8{};
        ctx.interpreter.halt(.revert);
        return;
    }

    if (offset > std.math.maxInt(usize) or size > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog);
        return;
    }

    const offset_u: usize = @intCast(offset);
    const size_u: usize = @intCast(size);

    const revert_end = std.math.add(usize, offset_u, size_u) catch {
        ctx.interpreter.halt(.memory_limit_oog);
        return;
    };
    if (!expandMemory(ctx, revert_end)) {
        ctx.interpreter.halt(.out_of_gas);
        return;
    }

    ctx.interpreter.return_data.data = ctx.interpreter.memory.buffer.items[offset_u..revert_end];
    ctx.interpreter.halt(.revert);
}

/// INVALID (0xFE): Designated invalid instruction. Consumes all remaining gas.
/// Stack: [] -> []   Gas: all remaining
pub fn opInvalid(ctx: *InstructionContext) void {
    ctx.interpreter.gas.spendAll();
    ctx.interpreter.halt(.invalid_opcode);
}
