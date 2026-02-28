const std = @import("std");
const primitives = @import("primitives");
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const gas_costs = @import("../gas_costs.zig");

fn memoryCostWords(num_words: usize) u64 {
    const n: u64 = @intCast(num_words);
    const linear = std.math.mul(u64, n, gas_costs.G_MEMORY) catch return std.math.maxInt(u64);
    const quadratic = (std.math.mul(u64, n, n) catch return std.math.maxInt(u64)) / 512;
    return std.math.add(u64, linear, quadratic) catch std.math.maxInt(u64);
}

/// KECCAK256 opcode (0x20): Compute Keccak-256 hash of memory region
/// Stack: [offset, length] -> [hash]
/// Gas: 30 (G_KECCAK256, dispatch) + 6*ceil(length/32) (word cost) + memory_expansion
pub fn opKeccak256(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) { ctx.interpreter.halt(.stack_underflow); return; }

    const offset = stack.peekUnsafe(0);
    const length = stack.peekUnsafe(1);

    if (offset > std.math.maxInt(usize) or length > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog); return;
    }

    const offset_usize: usize = @intCast(offset);
    const length_usize: usize = @intCast(length);

    // Dynamic: word cost
    const num_words: u64 = (length_usize + 31) / 32;
    const word_cost = gas_costs.G_KECCAK256WORD * num_words;
    if (!ctx.interpreter.gas.spend(word_cost)) { ctx.interpreter.halt(.out_of_gas); return; }

    // Dynamic: memory expansion
    const end = std.math.add(usize, offset_usize, length_usize) catch {
        ctx.interpreter.halt(.memory_limit_oog); return;
    };
    if (length_usize > 0) {
        const current_words = (ctx.interpreter.memory.size() + 31) / 32;
        const new_words = (end + 31) / 32;
        if (new_words > current_words) {
            const expansion_cost = memoryCostWords(new_words) - memoryCostWords(current_words);
            if (!ctx.interpreter.gas.spend(expansion_cost)) { ctx.interpreter.halt(.out_of_gas); return; }
        }
        const aligned_end = ((end + 31) / 32) * 32;
        if (aligned_end > ctx.interpreter.memory.size()) {
            const old_size = ctx.interpreter.memory.size();
            ctx.interpreter.memory.buffer.resize(std.heap.c_allocator, aligned_end) catch {
                ctx.interpreter.halt(.memory_limit_oog); return;
            };
            @memset(ctx.interpreter.memory.buffer.items[old_size..aligned_end], 0);
        }
    }

    const data = if (length_usize > 0)
        ctx.interpreter.memory.buffer.items[offset_usize..end]
    else
        &[_]u8{};

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(data, &hash, .{});

    const U = primitives.U256;
    const value: U = (@as(U, std.mem.readInt(u64, hash[0..8], .big)) << 192) |
        (@as(U, std.mem.readInt(u64, hash[8..16], .big)) << 128) |
        (@as(U, std.mem.readInt(u64, hash[16..24], .big)) << 64) |
        @as(U, std.mem.readInt(u64, hash[24..32], .big));

    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = value;
}

test {
    _ = @import("keccak_tests.zig");
}
