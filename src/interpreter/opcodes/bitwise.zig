const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;

pub const GAS_VERYLOW: u64 = 3;

/// AND opcode (0x16): a & b
/// Stack: [a, b] -> [a & b]   Gas: 3 (VERYLOW)
pub inline fn opAnd(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a & b;
    return .continue_;
}

/// OR opcode (0x17): a | b
/// Stack: [a, b] -> [a | b]   Gas: 3 (VERYLOW)
pub inline fn opOr(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a | b;
    return .continue_;
}

/// XOR opcode (0x18): a ^ b
/// Stack: [a, b] -> [a ^ b]   Gas: 3 (VERYLOW)
pub inline fn opXor(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a ^ b;
    return .continue_;
}

/// NOT opcode (0x19): ~a
/// Stack: [a] -> [~a]   Gas: 3 (VERYLOW)
pub inline fn opNot(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(1)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const ptr = stack.setTopUnsafe();
    ptr.* = ~ptr.*;
    return .continue_;
}

/// BYTE opcode (0x1A): Extract byte from word
/// Stack: [i, x] -> [byte_i(x)]   Gas: 3 (VERYLOW)
/// Extracts the i-th byte (0 = most significant) from x
pub inline fn opByte(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const i = stack.peekUnsafe(0);
    const x = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);

    // If i >= 32, result is 0
    const result = if (i < 32)
        (x >> @intCast((31 - i) * 8)) & 0xFF
    else
        0;

    stack.setTopUnsafe().* = result;
    return .continue_;
}

/// SHL opcode (0x1B): Shift left
/// Stack: [shift, value] -> [value << shift]   Gas: 3 (VERYLOW)
pub inline fn opShl(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const shift = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);

    const result = if (shift < 256)
        value << @intCast(shift)
    else
        0;

    stack.setTopUnsafe().* = result;
    return .continue_;
}

/// SHR opcode (0x1C): Logical shift right
/// Stack: [shift, value] -> [value >> shift]   Gas: 3 (VERYLOW)
pub inline fn opShr(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const shift = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);

    const result = if (shift < 256)
        value >> @intCast(shift)
    else
        0;

    stack.setTopUnsafe().* = result;
    return .continue_;
}

/// SAR opcode (0x1D): Arithmetic shift right (with sign extension)
/// Stack: [shift, value] -> [value >> shift (signed)]   Gas: 3 (VERYLOW)
pub inline fn opSar(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const shift = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);

    // Check if value is negative (MSB set)
    const is_negative = (value >> 255) == 1;
    const MAX: primitives.U256 = std.math.maxInt(primitives.U256);

    const result = if (shift >= 256) blk: {
        // Shift >= 256 means all bits shift out
        break :blk if (is_negative) MAX else 0;
    } else if (shift == 0) blk: {
        break :blk value;
    } else if (is_negative) blk: {
        // For negative numbers, we need to fill with 1s from the left
        const shift_amt: u8 = @intCast(shift);
        const shifted = value >> shift_amt;
        const mask = MAX << @intCast(@as(u9, 256) - shift_amt);
        break :blk shifted | mask;
    } else blk: {
        // Positive number: standard logical shift
        break :blk value >> @intCast(shift);
    };

    stack.setTopUnsafe().* = result;
    return .continue_;
}

test {
    _ = @import("bitwise_tests.zig");
}
