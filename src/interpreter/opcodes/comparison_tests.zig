const std = @import("std");
const primitives = @import("primitives");
const Interpreter = @import("../interpreter.zig").Interpreter;
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
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
const MAX = std.math.maxInt(U);

// --- LT tests ---

test "LT: 5 < 10" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 10)); // right operand (goes to second)
    interp.stack.pushUnsafe(@as(U, 5)); // left operand (top → µs[0])
    var ctx = InstructionContext{ .interpreter = &interp };
    opLt(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "LT: 10 < 5 is false" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 5)); // right operand
    interp.stack.pushUnsafe(@as(U, 10)); // left operand (top)
    var ctx = InstructionContext{ .interpreter = &interp };
    opLt(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "LT: equal values = false" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 42));
    interp.stack.pushUnsafe(@as(U, 42));
    var ctx = InstructionContext{ .interpreter = &interp };
    opLt(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "LT: 0 < MAX" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(MAX); // right operand
    interp.stack.pushUnsafe(@as(U, 0)); // left operand (top)
    var ctx = InstructionContext{ .interpreter = &interp };
    opLt(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "LT: stack underflow" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 1));
    var ctx = InstructionContext{ .interpreter = &interp };
    opLt(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}

// --- GT tests ---

test "GT: 10 > 5" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 5)); // right operand
    interp.stack.pushUnsafe(@as(U, 10)); // left operand (top)
    var ctx = InstructionContext{ .interpreter = &interp };
    opGt(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "GT: 5 > 10 is false" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 10)); // right operand
    interp.stack.pushUnsafe(@as(U, 5)); // left operand (top)
    var ctx = InstructionContext{ .interpreter = &interp };
    opGt(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "GT: equal values = false" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 42));
    interp.stack.pushUnsafe(@as(U, 42));
    var ctx = InstructionContext{ .interpreter = &interp };
    opGt(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

// --- SLT tests (signed comparison) ---

test "SLT: positive < positive" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 10)); // right operand
    interp.stack.pushUnsafe(@as(U, 5)); // left operand (top)
    var ctx = InstructionContext{ .interpreter = &interp };
    opSlt(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "SLT: negative < positive" {
    var interp = Interpreter.defaultExt();
    const negative: U = @as(U, 1) << 255; // most negative
    interp.stack.pushUnsafe(@as(U, 1)); // right operand
    interp.stack.pushUnsafe(negative); // left operand (top)
    var ctx = InstructionContext{ .interpreter = &interp };
    opSlt(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "SLT: positive < negative is false" {
    var interp = Interpreter.defaultExt();
    const negative: U = @as(U, 1) << 255;
    interp.stack.pushUnsafe(negative); // right operand
    interp.stack.pushUnsafe(@as(U, 1)); // left operand (top)
    var ctx = InstructionContext{ .interpreter = &interp };
    opSlt(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "SLT: -1 < -2 is false (both negative)" {
    var interp = Interpreter.defaultExt();
    const minus_one: U = MAX;
    const minus_two: U = MAX - 1;
    interp.stack.pushUnsafe(minus_two); // right operand
    interp.stack.pushUnsafe(minus_one); // left operand (top)
    var ctx = InstructionContext{ .interpreter = &interp };
    opSlt(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

// --- SGT tests ---

test "SGT: 10 > 5" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 5)); // right operand
    interp.stack.pushUnsafe(@as(U, 10)); // left operand (top)
    var ctx = InstructionContext{ .interpreter = &interp };
    opSgt(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "SGT: positive > negative" {
    var interp = Interpreter.defaultExt();
    const negative: U = @as(U, 1) << 255;
    interp.stack.pushUnsafe(negative); // right operand
    interp.stack.pushUnsafe(@as(U, 1)); // left operand (top)
    var ctx = InstructionContext{ .interpreter = &interp };
    opSgt(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "SGT: negative > positive is false" {
    var interp = Interpreter.defaultExt();
    const negative: U = @as(U, 1) << 255;
    interp.stack.pushUnsafe(@as(U, 1)); // right operand
    interp.stack.pushUnsafe(negative); // left operand (top)
    var ctx = InstructionContext{ .interpreter = &interp };
    opSgt(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

// --- EQ tests ---

test "EQ: equal values" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 42));
    interp.stack.pushUnsafe(@as(U, 42));
    var ctx = InstructionContext{ .interpreter = &interp };
    opEq(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "EQ: different values" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 42));
    interp.stack.pushUnsafe(@as(U, 43));
    var ctx = InstructionContext{ .interpreter = &interp };
    opEq(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "EQ: zero == zero" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opEq(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "EQ: MAX == MAX" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(MAX);
    interp.stack.pushUnsafe(MAX);
    var ctx = InstructionContext{ .interpreter = &interp };
    opEq(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

// --- ISZERO tests ---

test "ISZERO: zero = 1" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opIsZero(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "ISZERO: non-zero = 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 42));
    var ctx = InstructionContext{ .interpreter = &interp };
    opIsZero(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "ISZERO: MAX = 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(MAX);
    var ctx = InstructionContext{ .interpreter = &interp };
    opIsZero(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "ISZERO: stack underflow" {
    var interp = Interpreter.defaultExt();
    var ctx = InstructionContext{ .interpreter = &interp };
    opIsZero(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}
