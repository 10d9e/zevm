const std = @import("std");
const primitives = @import("primitives");
const Interpreter = @import("../interpreter.zig").Interpreter;
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
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
const expect = std.testing.expect;
const U = primitives.U256;
const MAX = std.math.maxInt(U);

// --- AND tests ---

test "AND: basic" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0xFF));
    interp.stack.pushUnsafe(@as(U, 0x0F));
    var ctx = InstructionContext{ .interpreter = &interp };
    opAnd(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(U, 0x0F), interp.stack.popUnsafe());
}

test "AND: identity with MAX" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 42));
    interp.stack.pushUnsafe(MAX);
    var ctx = InstructionContext{ .interpreter = &interp };
    opAnd(&ctx);
    try expectEqual(@as(U, 42), interp.stack.popUnsafe());
}

test "AND: zero annihilator" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 12345));
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opAnd(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "AND: stack underflow" {
    var interp = Interpreter.defaultExt();
    var ctx = InstructionContext{ .interpreter = &interp };
    opAnd(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}

// --- OR tests ---

test "OR: basic" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0xF0));
    interp.stack.pushUnsafe(@as(U, 0x0F));
    var ctx = InstructionContext{ .interpreter = &interp };
    opOr(&ctx);
    try expectEqual(@as(U, 0xFF), interp.stack.popUnsafe());
}

test "OR: identity with zero" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 42));
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opOr(&ctx);
    try expectEqual(@as(U, 42), interp.stack.popUnsafe());
}

// --- XOR tests ---

test "XOR: basic" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0xFF));
    interp.stack.pushUnsafe(@as(U, 0x0F));
    var ctx = InstructionContext{ .interpreter = &interp };
    opXor(&ctx);
    try expectEqual(@as(U, 0xF0), interp.stack.popUnsafe());
}

test "XOR: self = 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 12345));
    interp.stack.pushUnsafe(@as(U, 12345));
    var ctx = InstructionContext{ .interpreter = &interp };
    opXor(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

// --- NOT tests ---

test "NOT: ~0 = MAX" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opNot(&ctx);
    try expectEqual(MAX, interp.stack.popUnsafe());
}

test "NOT: ~MAX = 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(MAX);
    var ctx = InstructionContext{ .interpreter = &interp };
    opNot(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "NOT: double negation" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0xDEADBEEF));
    var ctx = InstructionContext{ .interpreter = &interp };
    opNot(&ctx);
    opNot(&ctx);
    try expectEqual(@as(U, 0xDEADBEEF), interp.stack.popUnsafe());
}

// --- BYTE tests ---

test "BYTE: extract byte 31 (least significant)" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0xABCDEF));
    interp.stack.pushUnsafe(@as(U, 31));
    var ctx = InstructionContext{ .interpreter = &interp };
    opByte(&ctx);
    try expectEqual(@as(U, 0xEF), interp.stack.popUnsafe());
}

test "BYTE: index >= 32 returns 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0xDEAD));
    interp.stack.pushUnsafe(@as(U, 32));
    var ctx = InstructionContext{ .interpreter = &interp };
    opByte(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "BYTE: index 0 extracts most significant byte" {
    var interp = Interpreter.defaultExt();
    // Value with 0xAB in position 0 (byte 31 from right = byte 0 from left)
    const value: U = @as(U, 0xAB) << 248;
    interp.stack.pushUnsafe(value);
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opByte(&ctx);
    try expectEqual(@as(U, 0xAB), interp.stack.popUnsafe());
}

// --- SHL tests ---

test "SHL: 1 << 4 = 16" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 1));
    interp.stack.pushUnsafe(@as(U, 4));
    var ctx = InstructionContext{ .interpreter = &interp };
    opShl(&ctx);
    try expectEqual(@as(U, 16), interp.stack.popUnsafe());
}

test "SHL: shift >= 256 = 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0xDEAD));
    interp.stack.pushUnsafe(@as(U, 256));
    var ctx = InstructionContext{ .interpreter = &interp };
    opShl(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

// --- SHR tests ---

test "SHR: 16 >> 4 = 1" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 16));
    interp.stack.pushUnsafe(@as(U, 4));
    var ctx = InstructionContext{ .interpreter = &interp };
    opShr(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "SHR: shift >= 256 = 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(MAX);
    interp.stack.pushUnsafe(@as(U, 256));
    var ctx = InstructionContext{ .interpreter = &interp };
    opShr(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

// --- SAR tests ---

test "SAR: positive value right shift" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0x100));
    interp.stack.pushUnsafe(@as(U, 4));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSar(&ctx);
    try expectEqual(@as(U, 0x10), interp.stack.popUnsafe());
}

test "SAR: negative value preserves sign (arithmetic)" {
    var interp = Interpreter.defaultExt();
    // MAX = all 1s (negative in two's complement)
    interp.stack.pushUnsafe(MAX);
    interp.stack.pushUnsafe(@as(U, 4));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSar(&ctx);
    // Arithmetic shift right of -1 by 4 = -1 (all 1s)
    try expectEqual(MAX, interp.stack.popUnsafe());
}

test "SAR: shift >= 256 negative = MAX" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(MAX); // negative
    interp.stack.pushUnsafe(@as(U, 256));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSar(&ctx);
    try expectEqual(MAX, interp.stack.popUnsafe());
}

test "SAR: shift >= 256 positive = 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 1)); // positive
    interp.stack.pushUnsafe(@as(U, 256));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSar(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}
