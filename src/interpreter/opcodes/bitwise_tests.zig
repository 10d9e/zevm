const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const bitwise = @import("bitwise.zig");

const opAnd = bitwise.opAnd;
const opOr = bitwise.opOr;
const opXor = bitwise.opXor;
const opNot = bitwise.opNot;
const opByte = bitwise.opByte;
const opShl = bitwise.opShl;
const opShr = bitwise.opShr;
const opSar = bitwise.opSar;

const expectEqual = std.testing.expectEqual;
const U = primitives.U256;
const MAX = U.MAX;

// --- AND tests ---

test "AND: basic operation" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(0xFF));
    stack.pushUnsafe(U.from(0x0F));
    const result = opAnd(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0x0F), stack.popUnsafe());
    try expectEqual(@as(u64, 97), gas.getRemaining());
}

test "AND: identity with MAX" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(42));
    stack.pushUnsafe(MAX);
    const result = opAnd(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(42), stack.popUnsafe());
}

test "AND: zero annihilator" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(12345));
    stack.pushUnsafe(U.from(0));
    const result = opAnd(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0), stack.popUnsafe());
}

test "AND: commutative" {
    var s1 = Stack.new();
    var g1 = Gas.new(100);
    s1.pushUnsafe(U.from(0xABCD));
    s1.pushUnsafe(U.from(0x1234));
    _ = opAnd(&s1, &g1);
    const r1 = s1.popUnsafe();

    var s2 = Stack.new();
    var g2 = Gas.new(100);
    s2.pushUnsafe(U.from(0x1234));
    s2.pushUnsafe(U.from(0xABCD));
    _ = opAnd(&s2, &g2);
    const r2 = s2.popUnsafe();

    try expectEqual(r1, r2);
}

// --- OR tests ---

test "OR: basic operation" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(0xF0));
    stack.pushUnsafe(U.from(0x0F));
    const result = opOr(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0xFF), stack.popUnsafe());
}

test "OR: identity with zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(42));
    stack.pushUnsafe(U.from(0));
    const result = opOr(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(42), stack.popUnsafe());
}

test "OR: absorbing with MAX" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(12345));
    stack.pushUnsafe(MAX);
    const result = opOr(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(MAX, stack.popUnsafe());
}

// --- XOR tests ---

test "XOR: basic operation" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(0xFF));
    stack.pushUnsafe(U.from(0xF0));
    const result = opXor(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0x0F), stack.popUnsafe());
}

test "XOR: self is zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(42));
    stack.pushUnsafe(U.from(42));
    const result = opXor(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0), stack.popUnsafe());
}

test "XOR: identity with zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(12345));
    stack.pushUnsafe(U.from(0));
    const result = opXor(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(12345), stack.popUnsafe());
}

// --- NOT tests ---

test "NOT: basic operation" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(0));
    const result = opNot(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(MAX, stack.popUnsafe());
}

test "NOT: double negation" {
    const value = U.from(12345);
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(value);
    _ = opNot(&stack, &gas);
    _ = opNot(&stack, &gas);
    try expectEqual(value, stack.popUnsafe());
}

test "NOT: MAX becomes zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX);
    const result = opNot(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0), stack.popUnsafe());
}

// --- BYTE tests ---

test "BYTE: extract first byte" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(0xABCDEF));
    stack.pushUnsafe(U.from(31)); // Byte 31 (rightmost)
    const result = opByte(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0xEF), stack.popUnsafe());
}

test "BYTE: extract middle byte" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(0xABCDEF));
    stack.pushUnsafe(U.from(30)); // Byte 30
    const result = opByte(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0xCD), stack.popUnsafe());
}

test "BYTE: out of range returns zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(0xABCDEF));
    stack.pushUnsafe(U.from(32)); // Out of range
    const result = opByte(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0), stack.popUnsafe());
}

// --- SHL tests ---

test "SHL: shift left by 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(5));
    stack.pushUnsafe(U.from(1));
    const result = opShl(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(10), stack.popUnsafe());
}

test "SHL: shift left by 8" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(0xFF));
    stack.pushUnsafe(U.from(8));
    const result = opShl(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0xFF00), stack.popUnsafe());
}

test "SHL: shift by 256 or more returns zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(12345));
    stack.pushUnsafe(U.from(256));
    const result = opShl(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0), stack.popUnsafe());
}

test "SHL: shift by zero is identity" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(42));
    stack.pushUnsafe(U.from(0));
    const result = opShl(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(42), stack.popUnsafe());
}

// --- SHR tests ---

test "SHR: shift right by 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(10));
    stack.pushUnsafe(U.from(1));
    const result = opShr(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(5), stack.popUnsafe());
}

test "SHR: shift right by 8" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(0xFF00));
    stack.pushUnsafe(U.from(8));
    const result = opShr(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0xFF), stack.popUnsafe());
}

test "SHR: shift by 256 or more returns zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(12345));
    stack.pushUnsafe(U.from(256));
    const result = opShr(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0), stack.popUnsafe());
}

// --- SAR tests ---

test "SAR: positive number shift right" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(10));
    stack.pushUnsafe(U.from(1));
    const result = opSar(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(5), stack.popUnsafe());
}

test "SAR: negative number shift right (sign extension)" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const negative_one = MAX; // -1 in two's complement
    stack.pushUnsafe(negative_one);
    stack.pushUnsafe(U.from(4));
    const result = opSar(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(negative_one, stack.popUnsafe()); // Should remain -1
}

test "SAR: negative number large shift" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const negative_value = U.fromNative((@as(u256, 1) << 255) | 0xFFFF); // Negative number
    stack.pushUnsafe(negative_value);
    stack.pushUnsafe(U.from(256)); // Shift >= 256
    const result = opSar(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(MAX, stack.popUnsafe()); // Should be all 1s
}

test "SAR: positive number large shift" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(12345));
    stack.pushUnsafe(U.from(300)); // Shift >= 256
    const result = opSar(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(U.from(0), stack.popUnsafe());
}

// --- Error conditions ---

test "AND: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(1));
    const result = opAnd(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "NOT: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(2); // Not enough gas
    stack.pushUnsafe(U.from(1));
    const result = opNot(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
}
