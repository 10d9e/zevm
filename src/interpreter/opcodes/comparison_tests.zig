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
const expect = std.testing.expect;
const U = primitives.U256;
const MAX = U.MAX;

// --- LT tests ---

test "LT: 5 < 10" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(5));
    stack.pushUnsafe(U.from(10));
    const result = opLt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ONE));
    try expectEqual(@as(u64, 97), gas.getRemaining());
}

test "LT: 10 < 5 is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(10));
    stack.pushUnsafe(U.from(5));
    const result = opLt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ZERO));
}

test "LT: equal values" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(42));
    stack.pushUnsafe(U.from(42));
    const result = opLt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ZERO));
}

test "LT: 0 < MAX" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.ZERO);
    stack.pushUnsafe(MAX);
    const result = opLt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ONE));
}

// --- GT tests ---

test "GT: 10 > 5" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(10));
    stack.pushUnsafe(U.from(5));
    const result = opGt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ONE));
}

test "GT: 5 > 10 is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(5));
    stack.pushUnsafe(U.from(10));
    const result = opGt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ZERO));
}

test "GT: equal values" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(42));
    stack.pushUnsafe(U.from(42));
    const result = opGt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ZERO));
}

// --- SLT tests (signed comparison) ---

test "SLT: positive < positive" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(5));
    stack.pushUnsafe(U.from(10));
    const result = opSlt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ONE));
}

test "SLT: negative < positive" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const negative = U.fromNative(@as(u256, 1) << 255); // -2^255 (most negative)
    stack.pushUnsafe(negative);
    stack.pushUnsafe(U.from(1));
    const result = opSlt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ONE));
}

test "SLT: positive < negative is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const negative = U.fromNative(@as(u256, 1) << 255);
    stack.pushUnsafe(U.from(1));
    stack.pushUnsafe(negative);
    const result = opSlt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ZERO));
}

test "SLT: -1 < -2 is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const minus_one = MAX;
    const minus_two = MAX.sub(U.ONE);
    stack.pushUnsafe(minus_one);
    stack.pushUnsafe(minus_two);
    const result = opSlt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ZERO));
}

// --- SGT tests (signed comparison) ---

test "SGT: 10 > 5 (positive)" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(10));
    stack.pushUnsafe(U.from(5));
    const result = opSgt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ONE));
}

test "SGT: positive > negative" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const negative = U.fromNative(@as(u256, 1) << 255);
    stack.pushUnsafe(U.from(1));
    stack.pushUnsafe(negative);
    const result = opSgt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ONE));
}

test "SGT: negative > positive is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const negative = U.fromNative(@as(u256, 1) << 255);
    stack.pushUnsafe(negative);
    stack.pushUnsafe(U.from(1));
    const result = opSgt(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ZERO));
}

// --- EQ tests ---

test "EQ: equal values" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(42));
    stack.pushUnsafe(U.from(42));
    const result = opEq(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ONE));
}

test "EQ: different values" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(42));
    stack.pushUnsafe(U.from(43));
    const result = opEq(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ZERO));
}

test "EQ: zero equals zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.ZERO);
    stack.pushUnsafe(U.ZERO);
    const result = opEq(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ONE));
}

test "EQ: MAX equals MAX" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX);
    stack.pushUnsafe(MAX);
    const result = opEq(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ONE));
}

// --- ISZERO tests ---

test "ISZERO: zero is true" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.ZERO);
    const result = opIsZero(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ONE));
}

test "ISZERO: non-zero is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(42));
    const result = opIsZero(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ZERO));
}

test "ISZERO: MAX is false" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX);
    const result = opIsZero(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ZERO));
}

// --- Error conditions ---

test "LT: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.ONE);
    const result = opLt(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "ISZERO: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(2); // Not enough gas
    stack.pushUnsafe(U.ONE);
    const result = opIsZero(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
}
