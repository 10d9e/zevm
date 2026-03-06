const std = @import("std");
const primitives = @import("primitives");
const InstructionContext = @import("../instruction_context.zig").InstructionContext;

/// AND opcode (0x16): a & b
/// Stack: [a, b] -> [a & b]   Static gas: 3 (VERYLOW, charged by dispatch)
pub fn opAnd(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a & b;
}

/// OR opcode (0x17): a | b
/// Stack: [a, b] -> [a | b]   Static gas: 3 (VERYLOW)
pub fn opOr(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a | b;
}

/// XOR opcode (0x18): a ^ b
/// Stack: [a, b] -> [a ^ b]   Static gas: 3 (VERYLOW)
pub fn opXor(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a ^ b;
}

/// NOT opcode (0x19): ~a
/// Stack: [a] -> [~a]   Static gas: 3 (VERYLOW)
pub fn opNot(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const ptr = stack.setTopUnsafe();
    ptr.* = ~ptr.*;
}

/// BYTE opcode (0x1A): Extract byte from word
/// Stack: [i, x] -> [byte_i(x)]   Static gas: 3 (VERYLOW)
pub fn opByte(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const i = stack.peekUnsafe(0);
    const x = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);

    const result = if (i < 32)
        (x >> @intCast((31 - i) * 8)) & 0xFF
    else
        0;

    stack.setTopUnsafe().* = result;
}

/// SHL opcode (0x1B): Shift left
/// Stack: [shift, value] -> [value << shift]   Static gas: 3 (VERYLOW)
pub fn opShl(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const shift = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);

    stack.setTopUnsafe().* = if (shift < 256) value << @intCast(shift) else 0;
}

/// SHR opcode (0x1C): Logical shift right
/// Stack: [shift, value] -> [value >> shift]   Static gas: 3 (VERYLOW)
pub fn opShr(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const shift = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);

    stack.setTopUnsafe().* = if (shift < 256) value >> @intCast(shift) else 0;
}

/// CLZ opcode (0x1E): Count leading zeros in 256-bit value (EIP-7939, Osaka+)
/// Stack: [x] -> [@clz(x)]   Static gas: 3 (VERYLOW, charged by dispatch)
pub fn opClz(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const ptr = stack.setTopUnsafe();
    ptr.* = @as(primitives.U256, @clz(ptr.*));
}

/// SAR opcode (0x1D): Arithmetic shift right (with sign extension)
/// Stack: [shift, value] -> [value >> shift (signed)]   Static gas: 3 (VERYLOW)
pub fn opSar(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const shift = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);

    const is_negative = (value >> 255) == 1;
    const MAX: primitives.U256 = std.math.maxInt(primitives.U256);

    const result = if (shift >= 256) blk: {
        break :blk if (is_negative) MAX else 0;
    } else if (shift == 0) blk: {
        break :blk value;
    } else if (is_negative) blk: {
        const shifted = value >> @intCast(shift);
        const mask = MAX << @intCast(256 - shift);
        break :blk shifted | mask;
    } else blk: {
        break :blk value >> @intCast(shift);
    };

    stack.setTopUnsafe().* = result;
}

test {
    _ = @import("bitwise_tests.zig");
}
