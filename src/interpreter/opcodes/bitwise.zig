const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;

const U256 = primitives.U256;

pub const GAS_VERYLOW: u64 = 3;

/// AND opcode (0x16): a & b
/// Stack: [a, b] -> [a & b]   Gas: 3 (VERYLOW)
pub inline fn opAnd(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a.bitAnd(b);
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
    stack.setTopUnsafe().* = a.bitOr(b);
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
    stack.setTopUnsafe().* = a.bitXor(b);
    return .continue_;
}

/// NOT opcode (0x19): ~a
/// Stack: [a] -> [~a]   Gas: 3 (VERYLOW)
pub inline fn opNot(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(1)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const ptr = stack.setTopUnsafe();
    ptr.* = ptr.*.bitNot();
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
    stack.setTopUnsafe().* = U256.getByte(i, x);
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
    stack.setTopUnsafe().* = U256.shl(shift, value);
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
    stack.setTopUnsafe().* = U256.shr(shift, value);
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
    stack.setTopUnsafe().* = U256.sar(shift, value);
    return .continue_;
}

test {
    _ = @import("bitwise_tests.zig");
}
