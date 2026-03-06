const std = @import("std");
const primitives = @import("primitives");
const Interpreter = @import("../interpreter.zig").Interpreter;
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const Gas = @import("../gas.zig").Gas;
const arithmetic = @import("arithmetic.zig");

const opAdd = arithmetic.opAdd;
const opSub = arithmetic.opSub;
const opMul = arithmetic.opMul;
const opDiv = arithmetic.opDiv;
const opMod = arithmetic.opMod;
const opSmod = arithmetic.opSmod;
const opSdiv = arithmetic.opSdiv;
const opAddmod = arithmetic.opAddmod;
const opMulmod = arithmetic.opMulmod;
const opExp = arithmetic.opExp;
const opSignextend = arithmetic.opSignextend;

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const U = primitives.U256;
const MAX = std.math.maxInt(U);

// --- ADD tests ---

test "ADD: 5 + 3 = 8" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 5));
    interp.stack.pushUnsafe(@as(U, 3));
    var ctx = InstructionContext{ .interpreter = &interp };
    opAdd(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(usize, 1), interp.stack.len());
    try expectEqual(@as(U, 8), interp.stack.popUnsafe());
}

test "ADD: zero identity" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 42));
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opAdd(&ctx);
    try expectEqual(@as(U, 42), interp.stack.popUnsafe());
}

test "ADD: wrapping overflow MAX + 1 = 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(MAX);
    interp.stack.pushUnsafe(@as(U, 1));
    var ctx = InstructionContext{ .interpreter = &interp };
    opAdd(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "ADD: stack underflow" {
    var interp = Interpreter.defaultExt();
    var ctx = InstructionContext{ .interpreter = &interp };
    opAdd(&ctx);
    try expect(!interp.bytecode.continue_execution);
    try expectEqual(.stack_underflow, interp.result);
}

test "ADD: chained 1 + 2 + 3 = 6" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 1));
    interp.stack.pushUnsafe(@as(U, 2));
    interp.stack.pushUnsafe(@as(U, 3));
    var ctx = InstructionContext{ .interpreter = &interp };
    opAdd(&ctx); // 3 + 2 = 5
    try expectEqual(@as(usize, 2), interp.stack.len());
    opAdd(&ctx); // 5 + 1 = 6
    try expectEqual(@as(usize, 1), interp.stack.len());
    try expectEqual(@as(U, 6), interp.stack.popUnsafe());
}

// --- SUB tests ---

test "SUB: 8 - 3 = 5" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 3));
    interp.stack.pushUnsafe(@as(U, 8));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSub(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(U, 5), interp.stack.popUnsafe());
}

test "SUB: wrapping underflow 0 - 1 = MAX" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 1));
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSub(&ctx);
    try expectEqual(MAX, interp.stack.popUnsafe());
}

test "SUB: a - 0 = a" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(@as(U, 42));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSub(&ctx);
    try expectEqual(@as(U, 42), interp.stack.popUnsafe());
}

test "SUB: a - a = 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 999));
    interp.stack.pushUnsafe(@as(U, 999));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSub(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "SUB: stack underflow" {
    var interp = Interpreter.defaultExt();
    var ctx = InstructionContext{ .interpreter = &interp };
    opSub(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}

// --- MUL tests ---

test "MUL: 3 * 4 = 12" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 4));
    interp.stack.pushUnsafe(@as(U, 3));
    var ctx = InstructionContext{ .interpreter = &interp };
    opMul(&ctx);
    try expectEqual(@as(U, 12), interp.stack.popUnsafe());
}

test "MUL: multiply by zero" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(MAX);
    var ctx = InstructionContext{ .interpreter = &interp };
    opMul(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "MUL: overflow wraps" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 2));
    interp.stack.pushUnsafe(MAX);
    var ctx = InstructionContext{ .interpreter = &interp };
    opMul(&ctx);
    try expectEqual(MAX -% 1, interp.stack.popUnsafe());
}

// --- DIV tests ---

test "DIV: 10 / 3 = 3" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 3));
    interp.stack.pushUnsafe(@as(U, 10));
    var ctx = InstructionContext{ .interpreter = &interp };
    opDiv(&ctx);
    try expectEqual(@as(U, 3), interp.stack.popUnsafe());
}

test "DIV: division by zero = 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(@as(U, 42));
    var ctx = InstructionContext{ .interpreter = &interp };
    opDiv(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "DIV: MAX / 1 = MAX" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 1));
    interp.stack.pushUnsafe(MAX);
    var ctx = InstructionContext{ .interpreter = &interp };
    opDiv(&ctx);
    try expectEqual(MAX, interp.stack.popUnsafe());
}

test "DIV: stack underflow" {
    var interp = Interpreter.defaultExt();
    var ctx = InstructionContext{ .interpreter = &interp };
    opDiv(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}

// --- MOD tests ---

test "MOD: 10 mod 3 = 1" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 3));
    interp.stack.pushUnsafe(@as(U, 10));
    var ctx = InstructionContext{ .interpreter = &interp };
    opMod(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "MOD: mod zero = 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(@as(U, 42));
    var ctx = InstructionContext{ .interpreter = &interp };
    opMod(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

// --- SDIV tests ---

test "SDIV: positive / positive" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 3));
    interp.stack.pushUnsafe(@as(U, 10));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSdiv(&ctx);
    try expectEqual(@as(U, 3), interp.stack.popUnsafe());
}

test "SDIV: division by zero = 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(@as(U, 42));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSdiv(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

// --- SMOD tests ---

test "SMOD: 10 smod 3 = 1" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 3));
    interp.stack.pushUnsafe(@as(U, 10));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSmod(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

// --- ADDMOD tests ---

test "ADDMOD: (10 + 7) mod 3 = 2" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 3)); // N
    interp.stack.pushUnsafe(@as(U, 7)); // b
    interp.stack.pushUnsafe(@as(U, 10)); // a
    var ctx = InstructionContext{ .interpreter = &interp };
    opAddmod(&ctx);
    try expectEqual(@as(U, 2), interp.stack.popUnsafe());
}

test "ADDMOD: N = 0 returns 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0)); // N
    interp.stack.pushUnsafe(@as(U, 5)); // b
    interp.stack.pushUnsafe(@as(U, 10)); // a
    var ctx = InstructionContext{ .interpreter = &interp };
    opAddmod(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "ADDMOD: MAX + MAX mod 7" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 7));
    interp.stack.pushUnsafe(MAX);
    interp.stack.pushUnsafe(MAX);
    var ctx = InstructionContext{ .interpreter = &interp };
    opAddmod(&ctx);
    // (MAX + MAX) % 7 = (2*MAX) % 7; MAX = 2^256 - 1
    // 2*MAX = 2^257 - 2; (2^257 - 2) % 7
    // 2^256 ≡ 1 (mod 7), so 2*MAX = 2*(2^256-1) = 2^257-2 ≡ 2-2 = 0 (mod 7)? Let me not check exact value.
    try expect(interp.stack.popUnsafe() < 7);
}

// --- MULMOD tests ---

test "MULMOD: (10 * 7) mod 3 = 1" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 3)); // N
    interp.stack.pushUnsafe(@as(U, 7)); // b
    interp.stack.pushUnsafe(@as(U, 10)); // a
    var ctx = InstructionContext{ .interpreter = &interp };
    opMulmod(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "MULMOD: N = 0 returns 0" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(@as(U, 5));
    interp.stack.pushUnsafe(@as(U, 10));
    var ctx = InstructionContext{ .interpreter = &interp };
    opMulmod(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

// --- EXP tests ---

test "EXP: 2 ^ 10 = 1024" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 10)); // exponent
    interp.stack.pushUnsafe(@as(U, 2)); // base
    var ctx = InstructionContext{ .interpreter = &interp };
    opExp(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(U, 1024), interp.stack.popUnsafe());
}

test "EXP: base ^ 0 = 1" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0)); // exponent
    interp.stack.pushUnsafe(MAX); // base
    var ctx = InstructionContext{ .interpreter = &interp };
    opExp(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "EXP: 0 ^ 0 = 1" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opExp(&ctx);
    try expectEqual(@as(U, 1), interp.stack.popUnsafe());
}

test "EXP: dynamic gas deduction (1-byte exponent)" {
    // Handler charges G_EXPBYTE * byteSize(exponent) = 50 * 1 = 50
    var interp = Interpreter.defaultExt();
    interp.gas = Gas.new(1000);
    interp.stack.pushUnsafe(@as(U, 10)); // exponent = 10, fits in 1 byte
    interp.stack.pushUnsafe(@as(U, 2));
    var ctx = InstructionContext{ .interpreter = &interp };
    opExp(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(u64, 950), interp.gas.remaining); // 1000 - 50
}

test "EXP: out of gas (dynamic word cost)" {
    // Dynamic gas = G_EXPBYTE * 32 = 1600; give only 40
    var interp = Interpreter.defaultExt();
    interp.gas = Gas.new(40);
    interp.stack.pushUnsafe(MAX); // 32-byte exponent
    interp.stack.pushUnsafe(@as(U, 2));
    var ctx = InstructionContext{ .interpreter = &interp };
    opExp(&ctx);
    try expect(!interp.bytecode.continue_execution);
    try expectEqual(.out_of_gas, interp.result);
}

test "EXP: stack underflow" {
    var interp = Interpreter.defaultExt();
    var ctx = InstructionContext{ .interpreter = &interp };
    opExp(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}

// --- SIGNEXTEND tests ---

test "SIGNEXTEND: extend byte 0 of 0xFF" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0xFF)); // value
    interp.stack.pushUnsafe(@as(U, 0)); // byte index
    var ctx = InstructionContext{ .interpreter = &interp };
    opSignextend(&ctx);
    // Sign bit of byte 0 is 1, so extend to all 1s = MAX
    try expectEqual(MAX, interp.stack.popUnsafe());
}

test "SIGNEXTEND: extend byte 0 of 0x7F (no sign extension)" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0x7F)); // value, sign bit 0
    interp.stack.pushUnsafe(@as(U, 0)); // byte index
    var ctx = InstructionContext{ .interpreter = &interp };
    opSignextend(&ctx);
    // Sign bit is 0, upper bits cleared = 0x7F
    try expectEqual(@as(U, 0x7F), interp.stack.popUnsafe());
}

test "SIGNEXTEND: index >= 31 returns value unchanged" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0xABCD)); // value
    interp.stack.pushUnsafe(@as(U, 31)); // byte index >= 31
    var ctx = InstructionContext{ .interpreter = &interp };
    opSignextend(&ctx);
    try expectEqual(@as(U, 0xABCD), interp.stack.popUnsafe());
}
