const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;

const U256 = primitives.U256;

pub const GAS_VERYLOW: u64 = 3;

/// LT opcode (0x10): a < b (unsigned)
/// Stack: [a, b] -> [a < b ? 1 : 0]   Gas: 3 (VERYLOW)
pub inline fn opLt(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a.ltU256(b);
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
    stack.setTopUnsafe().* = a.gtU256(b);
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
    stack.setTopUnsafe().* = a.sltU256(b);
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
    stack.setTopUnsafe().* = a.sgtU256(b);
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
    stack.setTopUnsafe().* = a.eqlU256(b);
    return .continue_;
}

/// ISZERO opcode (0x15): a == 0
/// Stack: [a] -> [a == 0 ? 1 : 0]   Gas: 3 (VERYLOW)
pub inline fn opIsZero(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(1)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const ptr = stack.setTopUnsafe();
    ptr.* = ptr.*.isZeroU256();
    return .continue_;
}

test {
    _ = @import("comparison_tests.zig");
}
