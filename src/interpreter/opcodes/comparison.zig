const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;

pub const GAS_VERYLOW: u64 = 3;

/// LT opcode (0x10): a < b (unsigned)
/// Stack: [a, b] -> [a < b ? 1 : 0]   Gas: 3 (VERYLOW)
pub inline fn opLt(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = if (a < b) 1 else 0;
    return .continue_;
}

/// GT opcode (0x11): a > b (unsigned)
/// Stack: [a, b] -> [a > b ? 1 : 0]   Gas: 3 (VERYLOW)
pub inline fn opGt(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = if (a > b) 1 else 0;
    return .continue_;
}

/// SLT opcode (0x12): a < b (signed)
/// Stack: [a, b] -> [a < b ? 1 : 0]   Gas: 3 (VERYLOW)
pub inline fn opSlt(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);

    // Interpret as signed by checking MSB
    const a_negative = (a >> 255) == 1;
    const b_negative = (b >> 255) == 1;

    const result: primitives.U256 = if (a_negative == b_negative)
        (if (a < b) @as(primitives.U256, 1) else 0)
    else if (a_negative)
        1 // negative < positive
    else
        0;

    stack.setTopUnsafe().* = result;
    return .continue_;
}

/// SGT opcode (0x13): a > b (signed)
/// Stack: [a, b] -> [a > b ? 1 : 0]   Gas: 3 (VERYLOW)
pub inline fn opSgt(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);

    // Interpret as signed by checking MSB
    const a_negative = (a >> 255) == 1;
    const b_negative = (b >> 255) == 1;

    const result: primitives.U256 = if (a_negative == b_negative)
        (if (a > b) @as(primitives.U256, 1) else 0)
    else if (b_negative)
        1 // positive > negative
    else
        0;

    stack.setTopUnsafe().* = result;
    return .continue_;
}

/// EQ opcode (0x14): a == b
/// Stack: [a, b] -> [a == b ? 1 : 0]   Gas: 3 (VERYLOW)
pub inline fn opEq(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = if (a == b) 1 else 0;
    return .continue_;
}

/// ISZERO opcode (0x15): a == 0
/// Stack: [a] -> [a == 0 ? 1 : 0]   Gas: 3 (VERYLOW)
pub inline fn opIsZero(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(1)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const ptr = stack.setTopUnsafe();
    ptr.* = if (ptr.* == 0) 1 else 0;
    return .continue_;
}

test {
    _ = @import("comparison_tests.zig");
}
