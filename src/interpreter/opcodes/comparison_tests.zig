const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const comparison = @import("comparison.zig");

const opLt = comparison.opLt;
const opGt = comparison.opGt;
const opSlt = comparison.opSlt;
const opSgt = comparison.opSgt;
const opEq = comparison.opEq;
const opIsZero = comparison.opIsZero;

const expectEqual = std.testing.expectEqual;
const U = primitives.U256;
const MAX = std.math.maxInt(U);

// --- LT tests ---

test "LT: 5 < 10" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 10));
    stack.pushUnsafe(@as(U, 5));
    const result = opLt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
    try expectEqual(@as(u64, 97), gas.getRemaining());
}

test "LT: 10 < 5 is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 5));
    stack.pushUnsafe(@as(U, 10));
    const result = opLt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "LT: equal values" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 42));
    stack.pushUnsafe(@as(U, 42));
    const result = opLt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "LT: 0 < MAX" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX);
    stack.pushUnsafe(@as(U, 0));
    const result = opLt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

// --- GT tests ---

test "GT: 10 > 5" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 5));
    stack.pushUnsafe(@as(U, 10));
    const result = opGt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "GT: 5 > 10 is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 10));
    stack.pushUnsafe(@as(U, 5));
    const result = opGt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "GT: equal values" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 42));
    stack.pushUnsafe(@as(U, 42));
    const result = opGt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

// --- SLT tests (signed comparison) ---

test "SLT: positive < positive" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 10));
    stack.pushUnsafe(@as(U, 5));
    const result = opSlt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "SLT: negative < positive" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const negative: U = (@as(U, 1) << 255); // -2^255 (most negative)
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(negative);
    const result = opSlt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "SLT: positive < negative is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const negative: U = (@as(U, 1) << 255);
    stack.pushUnsafe(negative);
    stack.pushUnsafe(@as(U, 1));
    const result = opSlt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "SLT: -1 < -2 is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const minus_one: U = MAX;
    const minus_two: U = MAX - 1;
    stack.pushUnsafe(minus_two);
    stack.pushUnsafe(minus_one);
    const result = opSlt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

// --- SGT tests (signed comparison) ---

test "SGT: 10 > 5 (positive)" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 5));
    stack.pushUnsafe(@as(U, 10));
    const result = opSgt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "SGT: positive > negative" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const negative: U = (@as(U, 1) << 255);
    stack.pushUnsafe(negative);
    stack.pushUnsafe(@as(U, 1));
    const result = opSgt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "SGT: negative > positive is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const negative: U = (@as(U, 1) << 255);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(negative);
    const result = opSgt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

// --- EQ tests ---

test "EQ: equal values" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 42));
    stack.pushUnsafe(@as(U, 42));
    const result = opEq(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "EQ: different values" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 42));
    stack.pushUnsafe(@as(U, 43));
    const result = opEq(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "EQ: zero equals zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0));
    stack.pushUnsafe(@as(U, 0));
    const result = opEq(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "EQ: MAX equals MAX" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX);
    stack.pushUnsafe(MAX);
    const result = opEq(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

// --- ISZERO tests ---

test "ISZERO: zero is true" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0));
    const result = opIsZero(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "ISZERO: non-zero is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 42));
    const result = opIsZero(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "ISZERO: MAX is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX);
    const result = opIsZero(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

// --- Error conditions ---

test "LT: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1));
    const result = opLt(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "ISZERO: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(2); // Not enough gas
    stack.pushUnsafe(@as(U, 1));
    const result = opIsZero(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
}
