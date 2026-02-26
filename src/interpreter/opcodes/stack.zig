const std = @import("std");
const primitives = @import("primitives");
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const InstructionFn = @import("../instruction_context.zig").InstructionFn;

/// POP opcode (0x50): Remove top item from stack
/// Stack: [a] -> []   Gas: 2 (G_BASE, charged by dispatch)
pub fn opPop(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) { ctx.interpreter.halt(.stack_underflow); return; }
    stack.shrinkUnsafe(1);
}

/// PUSH0 opcode (0x5F): Push 0 onto stack (Shanghai+)
/// Stack: [] -> [0]   Gas: 2 (G_BASE, charged by dispatch)
pub fn opPush0(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(0);
}

/// Comptime PUSH generator for PUSH1..PUSH32.
/// Reads n immediate bytes at current PC, pushes as big-endian U256, advances PC by n.
/// Static gas (G_VERYLOW) is charged by the dispatch loop.
pub fn makePushFn(comptime n: u8) InstructionFn {
    return struct {
        fn op(ctx: *InstructionContext) void {
            const stack = &ctx.interpreter.stack;
            if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }

            // Read n immediate bytes (zero-padded at end if near code boundary)
            const imm = ctx.interpreter.bytecode.readImmediates(n);

            // Right-align in 32-byte buffer then decode as big-endian U256
            var buf: [32]u8 = .{0} ** 32;
            @memcpy(buf[32 - n ..], &imm);

            const U = primitives.U256;
            const value: U = (@as(U, std.mem.readInt(u64, buf[0..8], .big)) << 192) |
                (@as(U, std.mem.readInt(u64, buf[8..16], .big)) << 128) |
                (@as(U, std.mem.readInt(u64, buf[16..24], .big)) << 64) |
                @as(U, std.mem.readInt(u64, buf[24..32], .big));

            stack.pushUnsafe(value);
            ctx.interpreter.bytecode.relativeJump(n);
        }
    }.op;
}

/// Comptime DUP generator for DUP1..DUP16.
/// Duplicates the nth stack item (1-indexed from top).
/// Static gas (G_VERYLOW) is charged by the dispatch loop.
pub fn makeDupFn(comptime n: u8) InstructionFn {
    return struct {
        fn op(ctx: *InstructionContext) void {
            const stack = &ctx.interpreter.stack;
            if (!stack.hasItems(n)) { ctx.interpreter.halt(.stack_underflow); return; }
            if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
            stack.dupUnsafe(n);
        }
    }.op;
}

/// Comptime SWAP generator for SWAP1..SWAP16.
/// Swaps top of stack with the (n+1)th item.
/// Static gas (G_VERYLOW) is charged by the dispatch loop.
pub fn makeSwapFn(comptime n: u8) InstructionFn {
    return struct {
        fn op(ctx: *InstructionContext) void {
            const stack = &ctx.interpreter.stack;
            if (!stack.hasItems(n + 1)) { ctx.interpreter.halt(.stack_underflow); return; }
            stack.swapUnsafe(n);
        }
    }.op;
}

test {
    _ = @import("stack_tests.zig");
}
