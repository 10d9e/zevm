const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const arithmetic = @import("arithmetic.zig");

const opAdd = arithmetic.opAdd;
const opSub = arithmetic.opSub;
const opMul = arithmetic.opMul;
const opDiv = arithmetic.opDiv;
const opMod = arithmetic.opMod;
const opAddmod = arithmetic.opAddmod;
const opMulmod = arithmetic.opMulmod;
const opExp = arithmetic.opExp;

const expectEqual = std.testing.expectEqual;
const U = primitives.U256;
const MAX = std.math.maxInt(U);

// --- ADD tests ---

test "ADD: 5 + 3 = 8" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 5));
    stack.pushUnsafe(@as(U, 3));
    const result = opAdd(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 8), stack.popUnsafe());
    try expectEqual(@as(u64, 97), gas.getRemaining());
}

test "ADD: zero identity" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 42));
    stack.pushUnsafe(@as(U, 0));
    const result = opAdd(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 42), stack.popUnsafe());
}

test "ADD: commutative" {
    var s1 = Stack.new();
    var g1 = Gas.new(100);
    s1.pushUnsafe(@as(U, 100));
    s1.pushUnsafe(@as(U, 200));
    _ = opAdd(&s1, &g1);
    const r1 = s1.popUnsafe();

    var s2 = Stack.new();
    var g2 = Gas.new(100);
    s2.pushUnsafe(@as(U, 200));
    s2.pushUnsafe(@as(U, 100));
    _ = opAdd(&s2, &g2);
    const r2 = s2.popUnsafe();

    try expectEqual(r1, r2);
    try expectEqual(@as(U, 300), r1);
}

test "ADD: wrapping overflow MAX + 1 = 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX);
    stack.pushUnsafe(@as(U, 1));
    const result = opAdd(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "ADD: MAX + MAX = MAX - 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX);
    stack.pushUnsafe(MAX);
    const result = opAdd(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(MAX -% 1, stack.popUnsafe());
}

test "ADD: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opAdd(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
    try expectEqual(@as(usize, 0), stack.len());
    try expectEqual(@as(u64, 100), gas.getRemaining());
}

test "ADD: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(2);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(@as(U, 2));
    const result = opAdd(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
    try expectEqual(@as(usize, 2), stack.len());
}

test "ADD: gas deduction" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 10));
    stack.pushUnsafe(@as(U, 20));
    _ = opAdd(&stack, &gas);
    try expectEqual(@as(u64, 97), gas.getRemaining());
    try expectEqual(@as(u64, 3), gas.getSpent());
}

test "ADD: chained 1 + 2 + 3 = 6" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(@as(U, 2));
    stack.pushUnsafe(@as(U, 3));
    _ = opAdd(&stack, &gas); // 3 + 2 = 5
    try expectEqual(@as(usize, 2), stack.len());
    _ = opAdd(&stack, &gas); // 5 + 1 = 6
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 6), stack.popUnsafe());
    try expectEqual(@as(u64, 94), gas.getRemaining());
}

// --- DIV tests ---

test "DIV: 10 / 3 = 3" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 3)); // b (divisor)
    stack.pushUnsafe(@as(U, 10)); // a (dividend)
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 3), stack.popUnsafe());
    try expectEqual(@as(u64, 95), gas.getRemaining());
}

test "DIV: division by zero returns 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0)); // b (divisor)
    stack.pushUnsafe(@as(U, 42)); // a (dividend)
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "DIV: exact division" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 25)); // b (divisor)
    stack.pushUnsafe(@as(U, 100)); // a (dividend)
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 4), stack.popUnsafe());
}

test "DIV: dividend < divisor = 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 10)); // b (divisor)
    stack.pushUnsafe(@as(U, 3)); // a (dividend)
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "DIV: MAX / 1 = MAX" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1)); // b (divisor)
    stack.pushUnsafe(MAX); // a (dividend)
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(MAX, stack.popUnsafe());
}

test "DIV: MAX / MAX = 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX);
    stack.pushUnsafe(MAX);
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "DIV: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
    try expectEqual(@as(usize, 0), stack.len());
    try expectEqual(@as(u64, 100), gas.getRemaining());
}

test "DIV: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(4);
    stack.pushUnsafe(@as(U, 10));
    stack.pushUnsafe(@as(U, 2));
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
    try expectEqual(@as(usize, 2), stack.len());
}

// --- SUB tests ---

test "SUB: 8 - 3 = 5" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 3)); // b
    stack.pushUnsafe(@as(U, 8)); // a
    const result = opSub(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 5), stack.popUnsafe());
    try expectEqual(@as(u64, 97), gas.getRemaining());
}

test "SUB: wrapping underflow 0 - 1 = MAX" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1)); // b
    stack.pushUnsafe(@as(U, 0)); // a
    const result = opSub(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(MAX, stack.popUnsafe());
}

test "SUB: zero identity a - 0 = a" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0)); // b
    stack.pushUnsafe(@as(U, 42)); // a
    const result = opSub(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 42), stack.popUnsafe());
}

test "SUB: self-sub a - a = 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 999)); // b
    stack.pushUnsafe(@as(U, 999)); // a
    const result = opSub(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "SUB: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opSub(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
    try expectEqual(@as(u64, 100), gas.getRemaining());
}

test "SUB: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(2);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(@as(U, 2));
    const result = opSub(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
    try expectEqual(@as(usize, 2), stack.len());
}

// --- MUL tests ---

test "MUL: 3 * 4 = 12" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 4)); // b
    stack.pushUnsafe(@as(U, 3)); // a
    const result = opMul(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 12), stack.popUnsafe());
    try expectEqual(@as(u64, 95), gas.getRemaining());
}

test "MUL: zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0));
    stack.pushUnsafe(@as(U, 42));
    const result = opMul(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "MUL: identity a * 1 = a" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(@as(U, 42));
    const result = opMul(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 42), stack.popUnsafe());
}

test "MUL: wrapping MAX * 2 = MAX - 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 2));
    stack.pushUnsafe(MAX);
    const result = opMul(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(MAX -% 1, stack.popUnsafe());
}

test "MUL: commutative" {
    var s1 = Stack.new();
    var g1 = Gas.new(100);
    s1.pushUnsafe(@as(U, 7));
    s1.pushUnsafe(@as(U, 13));
    _ = opMul(&s1, &g1);
    const r1 = s1.popUnsafe();

    var s2 = Stack.new();
    var g2 = Gas.new(100);
    s2.pushUnsafe(@as(U, 13));
    s2.pushUnsafe(@as(U, 7));
    _ = opMul(&s2, &g2);
    const r2 = s2.popUnsafe();

    try expectEqual(r1, r2);
    try expectEqual(@as(U, 91), r1);
}

test "MUL: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opMul(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "MUL: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(4);
    stack.pushUnsafe(@as(U, 2));
    stack.pushUnsafe(@as(U, 3));
    const result = opMul(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
    try expectEqual(@as(usize, 2), stack.len());
}

// --- MOD tests ---

test "MOD: 10 % 3 = 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 3)); // b
    stack.pushUnsafe(@as(U, 10)); // a
    const result = opMod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
    try expectEqual(@as(u64, 95), gas.getRemaining());
}

test "MOD: mod by zero = 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0)); // b
    stack.pushUnsafe(@as(U, 42)); // a
    const result = opMod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "MOD: dividend < divisor" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 10)); // b
    stack.pushUnsafe(@as(U, 3)); // a
    const result = opMod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 3), stack.popUnsafe());
}

test "MOD: MAX % 2 = 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 2)); // b
    stack.pushUnsafe(MAX); // a
    const result = opMod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "MOD: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opMod(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "MOD: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(4);
    stack.pushUnsafe(@as(U, 3));
    stack.pushUnsafe(@as(U, 10));
    const result = opMod(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
}

// --- ADDMOD tests ---

test "ADDMOD: (10 + 7) % 3 = 2" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 3)); // N
    stack.pushUnsafe(@as(U, 7)); // b
    stack.pushUnsafe(@as(U, 10)); // a
    const result = opAddmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 2), stack.popUnsafe());
    try expectEqual(@as(u64, 92), gas.getRemaining());
}

test "ADDMOD: N=0 returns 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0)); // N
    stack.pushUnsafe(@as(U, 7)); // b
    stack.pushUnsafe(@as(U, 10)); // a
    const result = opAddmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "ADDMOD: MAX + 1 carry" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 2)); // N
    stack.pushUnsafe(@as(U, 1)); // b
    stack.pushUnsafe(MAX); // a
    // (MAX + 1) % 2 = 2^256 % 2 = 0
    const result = opAddmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "ADDMOD: MAX + MAX" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX); // N = MAX
    stack.pushUnsafe(MAX); // b
    stack.pushUnsafe(MAX); // a
    // (MAX + MAX) % MAX = (2*MAX) % MAX = 0
    const result = opAddmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "ADDMOD: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(@as(U, 2));
    const result = opAddmod(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
    try expectEqual(@as(usize, 2), stack.len());
}

test "ADDMOD: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(7);
    stack.pushUnsafe(@as(U, 3));
    stack.pushUnsafe(@as(U, 7));
    stack.pushUnsafe(@as(U, 10));
    const result = opAddmod(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
    try expectEqual(@as(usize, 3), stack.len());
}

// --- MULMOD tests ---

test "MULMOD: (10 * 7) % 3 = 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 3)); // N
    stack.pushUnsafe(@as(U, 7)); // b
    stack.pushUnsafe(@as(U, 10)); // a
    const result = opMulmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 1), stack.popUnsafe());
    try expectEqual(@as(u64, 92), gas.getRemaining());
}

test "MULMOD: N=0 returns 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0)); // N
    stack.pushUnsafe(@as(U, 7)); // b
    stack.pushUnsafe(@as(U, 10)); // a
    const result = opMulmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "MULMOD: MAX * MAX % MAX = 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX); // N
    stack.pushUnsafe(MAX); // b
    stack.pushUnsafe(MAX); // a
    const result = opMulmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "MULMOD: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(@as(U, 2));
    const result = opMulmod(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "MULMOD: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(7);
    stack.pushUnsafe(@as(U, 3));
    stack.pushUnsafe(@as(U, 7));
    stack.pushUnsafe(@as(U, 10));
    const result = opMulmod(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
}

// --- EXP tests ---

test "EXP: 2 ^ 10 = 1024" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    stack.pushUnsafe(@as(U, 10)); // exponent
    stack.pushUnsafe(@as(U, 2)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1024), stack.popUnsafe());
    // gas: 10 + 50*1 = 60 (exponent 10 fits in 1 byte)
    try expectEqual(@as(u64, 940), gas.getRemaining());
}

test "EXP: a ^ 0 = 1" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    stack.pushUnsafe(@as(U, 0)); // exponent
    stack.pushUnsafe(@as(U, 42)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
    // gas: 10 + 50*0 = 10 (exponent 0 = 0 bytes)
    try expectEqual(@as(u64, 990), gas.getRemaining());
}

test "EXP: 0 ^ 0 = 1" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    stack.pushUnsafe(@as(U, 0)); // exponent
    stack.pushUnsafe(@as(U, 0)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "EXP: a ^ 1 = a" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    stack.pushUnsafe(@as(U, 1)); // exponent
    stack.pushUnsafe(@as(U, 42)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 42), stack.popUnsafe());
}

test "EXP: 0 ^ n = 0 (n > 0)" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    stack.pushUnsafe(@as(U, 5)); // exponent
    stack.pushUnsafe(@as(U, 0)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "EXP: 2 ^ 256 = 0 (wrapping)" {
    var stack = Stack.new();
    var gas = Gas.new(10000);
    stack.pushUnsafe(@as(U, 256)); // exponent
    stack.pushUnsafe(@as(U, 2)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
    // gas: 10 + 50*2 = 110 (exponent 256 = 0x100, 2 bytes)
    try expectEqual(@as(u64, 9890), gas.getRemaining());
}

test "EXP: gas cost with 32-byte exponent" {
    var stack = Stack.new();
    var gas = Gas.new(10000);
    stack.pushUnsafe(MAX); // exponent = MAX (32 bytes)
    stack.pushUnsafe(@as(U, 2)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    // gas: 10 + 50*32 = 1610
    try expectEqual(@as(u64, 8390), gas.getRemaining());
}

test "EXP: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
    try expectEqual(@as(u64, 1000), gas.getRemaining());
}

test "EXP: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(50);
    stack.pushUnsafe(MAX); // exponent = MAX (32 bytes, needs 1610 gas)
    stack.pushUnsafe(@as(U, 2));
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
    try expectEqual(@as(usize, 2), stack.len());
}

// --- Helper function tests ---

test "byteSize" {
    try expectEqual(@as(u64, 0), arithmetic.byteSize(0));
    try expectEqual(@as(u64, 1), arithmetic.byteSize(1));
    try expectEqual(@as(u64, 1), arithmetic.byteSize(255));
    try expectEqual(@as(u64, 2), arithmetic.byteSize(256));
    try expectEqual(@as(u64, 32), arithmetic.byteSize(MAX));
}

test "addmod helper" {
    try expectEqual(@as(U, 2), arithmetic.addmod(10, 7, 3));
    try expectEqual(@as(U, 0), arithmetic.addmod(10, 7, 0));
    // MAX + 1 = 2^256, handled by overflow detection
    try expectEqual(@as(U, 0), arithmetic.addmod(MAX, 1, 2));
}

test "mulmod helper" {
    try expectEqual(@as(U, 1), arithmetic.mulmod(10, 7, 3));
    try expectEqual(@as(U, 0), arithmetic.mulmod(10, 7, 0));
    try expectEqual(@as(U, 0), arithmetic.mulmod(MAX, MAX, MAX));
}

// --- toLimbs / fromLimbs round-trip tests ---

test "toLimbs/fromLimbs: zero" {
    const limbs = arithmetic.toLimbs(0);
    try expectEqual([4]u64{ 0, 0, 0, 0 }, limbs);
    try expectEqual(@as(U, 0), arithmetic.fromLimbs(limbs));
}

test "toLimbs/fromLimbs: one" {
    const limbs = arithmetic.toLimbs(1);
    try expectEqual([4]u64{ 1, 0, 0, 0 }, limbs);
    try expectEqual(@as(U, 1), arithmetic.fromLimbs(limbs));
}

test "toLimbs/fromLimbs: MAX" {
    const limbs = arithmetic.toLimbs(MAX);
    const max64 = std.math.maxInt(u64);
    try expectEqual([4]u64{ max64, max64, max64, max64 }, limbs);
    try expectEqual(MAX, arithmetic.fromLimbs(limbs));
}

test "toLimbs/fromLimbs: powers of 2^64" {
    // 2^64
    const v1: U = @as(U, 1) << 64;
    const l1 = arithmetic.toLimbs(v1);
    try expectEqual([4]u64{ 0, 1, 0, 0 }, l1);
    try expectEqual(v1, arithmetic.fromLimbs(l1));

    // 2^128
    const v2: U = @as(U, 1) << 128;
    const l2 = arithmetic.toLimbs(v2);
    try expectEqual([4]u64{ 0, 0, 1, 0 }, l2);
    try expectEqual(v2, arithmetic.fromLimbs(l2));

    // 2^192
    const v3: U = @as(U, 1) << 192;
    const l3 = arithmetic.toLimbs(v3);
    try expectEqual([4]u64{ 0, 0, 0, 1 }, l3);
    try expectEqual(v3, arithmetic.fromLimbs(l3));
}

// --- mulFull tests ---

test "mulFull: small values 3 * 4 = 12" {
    const result = arithmetic.mulFull(3, 4);
    try expectEqual(@as(u64, 12), result[0]);
    for (1..8) |i| {
        try expectEqual(@as(u64, 0), result[i]);
    }
}

test "mulFull: MAX * MAX" {
    // MAX * MAX = (2^256 - 1)^2 = 2^512 - 2^257 + 1
    // In 512-bit limbs: low 256 bits = 1, high 256 bits = MAX - 1
    const result = arithmetic.mulFull(MAX, MAX);
    // Low limbs: 0x0000...0001
    try expectEqual(@as(u64, 1), result[0]);
    try expectEqual(@as(u64, 0), result[1]);
    try expectEqual(@as(u64, 0), result[2]);
    try expectEqual(@as(u64, 0), result[3]);
    // High limbs: MAX - 1 = 0xFFFF...FFFE
    const max64 = std.math.maxInt(u64);
    try expectEqual(max64 - 1, result[4]);
    try expectEqual(max64, result[5]);
    try expectEqual(max64, result[6]);
    try expectEqual(max64, result[7]);
}

test "mulFull: MAX * 2" {
    // MAX * 2 = 2^257 - 2 → low 256 = MAX - 1, high limbs = [1, 0, 0, 0]
    const result = arithmetic.mulFull(MAX, 2);
    const max64 = std.math.maxInt(u64);
    try expectEqual(max64 - 1, result[0]);
    try expectEqual(max64, result[1]);
    try expectEqual(max64, result[2]);
    try expectEqual(max64, result[3]);
    try expectEqual(@as(u64, 1), result[4]);
    try expectEqual(@as(u64, 0), result[5]);
    try expectEqual(@as(u64, 0), result[6]);
    try expectEqual(@as(u64, 0), result[7]);
}

// --- mod512by256 tests ---

test "mod512by256: divisor is 1" {
    // Any value mod 1 = 0
    const product = arithmetic.mulFull(MAX, MAX);
    try expectEqual(@as(U, 0), arithmetic.mod512by256(product, arithmetic.toLimbs(1)));
}

test "mod512by256: divisor is power of 2" {
    // (MAX * 2) mod (2^128) = (2^257 - 2) mod 2^128
    // low 128 bits of (2^257 - 2) = MAX_128 - 1 = 2^128 - 2
    const product = arithmetic.mulFull(MAX, 2);
    const mod: U = @as(U, 1) << 128;
    const expected: U = mod - 2;
    try expectEqual(expected, arithmetic.mod512by256(product, arithmetic.toLimbs(mod)));
}

// --- Additional mulmod edge cases ---

test "mulmod: (MAX-1) * (MAX-1) % MAX" {
    // (MAX-1)^2 = MAX^2 - 2*MAX + 1
    // MAX^2 mod MAX = 0, so result = (-2*MAX + 1) mod MAX = 1
    try expectEqual(@as(U, 1), arithmetic.mulmod(MAX - 1, MAX - 1, MAX));
}

test "mulmod: prime modulus" {
    // Use a known prime and verify against known result
    // 7 * 13 = 91; 91 mod 17 = 91 - 5*17 = 91 - 85 = 6
    try expectEqual(@as(U, 6), arithmetic.mulmod(7, 13, 17));
}

test "mulmod: small * large" {
    // 2 * MAX = 2^257 - 2; mod (MAX) = (2^257 - 2) mod (2^256 - 1)
    // 2^257 - 2 = 2*(2^256 - 1) = 2*MAX, so 2*MAX mod MAX = 0
    try expectEqual(@as(U, 0), arithmetic.mulmod(2, MAX, MAX));
}

test "mulmod: a=0 returns 0" {
    try expectEqual(@as(U, 0), arithmetic.mulmod(0, MAX, 7));
}

test "mulmod: b=0 returns 0" {
    try expectEqual(@as(U, 0), arithmetic.mulmod(MAX, 0, 7));
}

test "mulmod: n=1 returns 0" {
    try expectEqual(@as(U, 0), arithmetic.mulmod(42, 99, 1));
}

test "mulmod: product fits in 256 bits" {
    // 100 * 200 = 20000; 20000 mod 7 = 2857*7 + 1 = 1
    try expectEqual(@as(U, 1), arithmetic.mulmod(100, 200, 7));
}

// --- Additional addmod edge cases ---

test "addmod: both inputs larger than n" {
    // (100 + 200) % 7 = 300 % 7 = 6
    try expectEqual(@as(U, 6), arithmetic.addmod(100, 200, 7));
}

test "addmod: carry case with large n" {
    // MAX + MAX = 2^257 - 2; mod (MAX - 1) = (2^257 - 2) mod (2^256 - 2)
    // = 2*(2^256 - 1) mod (2^256 - 2) = 2*MAX mod (MAX - 1)
    // MAX mod (MAX-1) = 1, so 2*MAX mod (MAX-1) = 2
    const n = MAX - 1;
    try expectEqual(@as(U, 2), arithmetic.addmod(MAX, MAX, n));
}

test "addmod: n=1 always returns 0" {
    try expectEqual(@as(U, 0), arithmetic.addmod(42, 99, 1));
    try expectEqual(@as(U, 0), arithmetic.addmod(MAX, MAX, 1));
}

// --- div128by64 tests ---

test "div128by64: basic small division" {
    // 12 / (1 << 63) with hi=0 → q=0, r=12 after normalization
    // Use a pre-normalized divisor (MSB set): d = 1 << 63
    const d: u64 = @as(u64, 1) << 63;
    const result = arithmetic.div128by64(0, 12, d);
    try expectEqual(@as(u64, 0), result.q);
    try expectEqual(@as(u64, 12), result.r);
}

test "div128by64: known value" {
    // (1 << 64) / (1 << 63) = 2 remainder 0
    // hi=1, lo=0, d=1<<63 → but precondition is hi < d
    // So use hi=0, lo=2*(1<<63)=0 with carry... let's pick a concrete example.
    // 0x0000000000000001:0000000000000000 / 0x8000000000000000 = 2, r=0
    // hi=1, lo=0, d=0x8000000000000000. hi < d? 1 < 0x80...0? Yes.
    const d: u64 = @as(u64, 1) << 63;
    const result = arithmetic.div128by64(1, 0, d);
    try expectEqual(@as(u64, 2), result.q);
    try expectEqual(@as(u64, 0), result.r);
}

test "div128by64: max dividend below overflow" {
    // hi = d-1, lo = MAX64, d = 1<<63
    // This is (d-1)*2^64 + MAX64 divided by d
    const d: u64 = @as(u64, 1) << 63;
    const max64 = std.math.maxInt(u64);
    const result = arithmetic.div128by64(d - 1, max64, d);
    // Quotient should be MAX64 (since (d-1)*2^64 + MAX64 = d*MAX64 + (MAX64 - d + 1)... let's verify)
    // (d-1)*2^64 + (2^64-1) = d*2^64 - 2^64 + 2^64 - 1 = d*2^64 - 1
    // d*2^64 - 1 = d*(2^64-1) + d - 1, so q = 2^64-1, r = d-1
    try expectEqual(max64, result.q);
    try expectEqual(d - 1, result.r);
}

test "div128by64: divisor all ones" {
    const max64 = std.math.maxInt(u64);
    const d = max64; // MSB is set
    // (max64-1):max64 / max64
    // = (max64-1)*2^64 + max64 / max64
    // = (max64^2 - 2^64 + max64) / max64 ... let's compute directly
    // Numerator: (max64-1)*2^64 + max64 = max64*(2^64) - 2^64 + max64 = max64*(max64+1) - (max64+1) = (max64-1)*(max64+1) = max64^2 - 1
    // max64^2 - 1 / max64 = max64 - 1 remainder max64 - 1 ... wait
    // Actually max64^2 / max64 = max64, remainder 0. max64^2 - 1 / max64 = max64 - 1 remainder max64 - (max64-1)*max64 ...
    // Let me just compute: (max64-1) * 2^64 + max64. We know 2^64 = max64 + 1.
    // = (max64-1)*(max64+1) + max64 = max64^2 - 1 + max64 = max64^2 + max64 - 1
    // Divide by max64: q = max64 + 1 = 2^64? No, that overflows. Let me reconsider.
    // hi must be < d. hi = max64-1 < max64 = d. OK.
    // Actually (max64-1)*2^64 + max64 = max64*(max64-1+1) + max64 - (max64-1) = ... let me just trust the algorithm.
    const result = arithmetic.div128by64(max64 - 1, max64, d);
    // Verify: q * d + r = (hi << 64) | lo
    const check: u128 = @as(u128, result.q) * d + result.r;
    const expected: u128 = (@as(u128, max64 - 1) << 64) | max64;
    try expectEqual(expected, check);
}

// --- limbLessThan tests ---

test "limbLessThan: equal values" {
    try expectEqual(false, arithmetic.limbLessThan(.{ 1, 2, 3, 4 }, .{ 1, 2, 3, 4 }));
}

test "limbLessThan: less in high limb" {
    try expectEqual(true, arithmetic.limbLessThan(.{ 1, 2, 3, 4 }, .{ 1, 2, 3, 5 }));
}

test "limbLessThan: greater in high limb" {
    try expectEqual(false, arithmetic.limbLessThan(.{ 1, 2, 3, 5 }, .{ 1, 2, 3, 4 }));
}

test "limbLessThan: less in low limb" {
    try expectEqual(true, arithmetic.limbLessThan(.{ 0, 0, 0, 0 }, .{ 1, 0, 0, 0 }));
}

test "expMod256 helper" {
    try expectEqual(@as(U, 1), arithmetic.expMod256(2, 0));
    try expectEqual(@as(U, 1024), arithmetic.expMod256(2, 10));
    try expectEqual(@as(U, 0), arithmetic.expMod256(2, 256));
    try expectEqual(@as(U, 1), arithmetic.expMod256(1, MAX));
}
