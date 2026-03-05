const std = @import("std");
const primitives = @import("primitives");
const InstructionContext = @import("../instruction_context.zig").InstructionContext;

/// LT opcode (0x10): a < b (unsigned)
/// Stack: [a, b] -> [a < b ? 1 : 0]   Static gas: 3 (VERYLOW, charged by dispatch)
pub fn opLt(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = if (a < b) 1 else 0;
}

/// GT opcode (0x11): a > b (unsigned)
/// Stack: [a, b] -> [a > b ? 1 : 0]   Static gas: 3 (VERYLOW)
pub fn opGt(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = if (a > b) 1 else 0;
}

/// SLT opcode (0x12): a < b (signed)
/// Stack: [a, b] -> [a < b ? 1 : 0]   Static gas: 3 (VERYLOW)
pub fn opSlt(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);

    const a_negative = (a >> 255) == 1;
    const b_negative = (b >> 255) == 1;

    const result: primitives.U256 = if (a_negative == b_negative)
        (if (a < b) @as(primitives.U256, 1) else 0)
    else if (a_negative)
        1
    else
        0;

    stack.setTopUnsafe().* = result;
}

/// SGT opcode (0x13): a > b (signed)
/// Stack: [a, b] -> [a > b ? 1 : 0]   Static gas: 3 (VERYLOW)
pub fn opSgt(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);

    const a_negative = (a >> 255) == 1;
    const b_negative = (b >> 255) == 1;

    const result: primitives.U256 = if (a_negative == b_negative)
        (if (a > b) @as(primitives.U256, 1) else 0)
    else if (b_negative)
        1
    else
        0;

    stack.setTopUnsafe().* = result;
}

/// EQ opcode (0x14): a == b
/// Stack: [a, b] -> [a == b ? 1 : 0]   Static gas: 3 (VERYLOW)
pub fn opEq(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = if (a == b) 1 else 0;
}

/// ISZERO opcode (0x15): a == 0
/// Stack: [a] -> [a == 0 ? 1 : 0]   Static gas: 3 (VERYLOW)
pub fn opIsZero(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const ptr = stack.setTopUnsafe();
    ptr.* = if (ptr.* == 0) 1 else 0;
}

test {
    _ = @import("comparison_tests.zig");
}
