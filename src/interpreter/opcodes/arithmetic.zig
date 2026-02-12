const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;

pub const U256 = primitives.U256;

pub const GAS_VERYLOW: u64 = 3;
pub const GAS_LOW: u64 = 5;
pub const GAS_MID: u64 = 8;
pub const GAS_EXP: u64 = 10;
pub const GAS_EXP_BYTE: u64 = 50;

/// ADD opcode (0x01): a + b (wrapping mod 2^256)
/// Stack: [a, b] -> [a + b]   Gas: 3 (VERYLOW)
pub inline fn opAdd(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a.add(b);
    return .continue_;
}

/// DIV opcode (0x04): a / b (unsigned, division by zero returns 0)
/// Stack: [a, b] -> [a / b]   Gas: 5 (LOW)
pub inline fn opDiv(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_LOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a.div(b);
    return .continue_;
}

/// SUB opcode (0x03): a - b (wrapping mod 2^256)
/// Stack: [a, b] -> [a - b]   Gas: 3 (VERYLOW)
pub inline fn opSub(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a.sub(b);
    return .continue_;
}

/// MUL opcode (0x02): a * b (wrapping mod 2^256)
/// Stack: [a, b] -> [a * b]   Gas: 5 (LOW)
pub inline fn opMul(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_LOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a.mul(b);
    return .continue_;
}

/// MOD opcode (0x06): a % b (unsigned, mod by zero returns 0)
/// Stack: [a, b] -> [a % b]   Gas: 5 (LOW)
pub inline fn opMod(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_LOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a.mod(b);
    return .continue_;
}

/// ADDMOD opcode (0x08): (a + b) % N with u257 intermediate
/// Stack: [a, b, N] -> [(a + b) % N]   Gas: 8 (MID)
pub inline fn opAddmod(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(3)) return .stack_underflow;
    if (!gas.spend(GAS_MID)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    const n = stack.peekUnsafe(2);
    stack.shrinkUnsafe(2);
    stack.setTopUnsafe().* = U256.addmod(a, b, n);
    return .continue_;
}

/// MULMOD opcode (0x09): (a * b) % N with u512 intermediate
/// Stack: [a, b, N] -> [(a * b) % N]   Gas: 8 (MID)
pub inline fn opMulmod(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(3)) return .stack_underflow;
    if (!gas.spend(GAS_MID)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    const n = stack.peekUnsafe(2);
    stack.shrinkUnsafe(2);
    stack.setTopUnsafe().* = U256.mulmod(a, b, n);
    return .continue_;
}

/// EXP opcode (0x0A): base ^ exponent (mod 2^256)
/// Stack: [base, exponent] -> [base ^ exponent]
/// Gas: 10 + 50 * byteSize(exponent)
pub inline fn opExp(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    const exponent = stack.peekUnsafe(1);
    const gas_cost = GAS_EXP + GAS_EXP_BYTE * exponent.byteSize();
    if (!gas.spend(gas_cost)) return .out_of_gas;
    const base = stack.peekUnsafe(0);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = U256.exp(base, exponent);
    return .continue_;
}

/// SDIV opcode (0x05): a / b (signed, division by zero returns 0)
/// Stack: [a, b] -> [a / b]   Gas: 5 (LOW)
pub inline fn opSdiv(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_LOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = U256.sdiv(a, b);
    return .continue_;
}

/// SMOD opcode (0x07): a % b (signed, mod by zero returns 0)
/// Stack: [a, b] -> [a % b]   Gas: 5 (LOW)
pub inline fn opSmod(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_LOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = U256.smod(a, b);
    return .continue_;
}

/// SIGNEXTEND opcode (0x0B): Sign extend value from byte position
/// Stack: [byte_pos, value] -> [extended_value]   Gas: 5 (LOW)
pub inline fn opSignextend(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_LOW)) return .out_of_gas;
    const byte_pos = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = U256.signextend(byte_pos, value);
    return .continue_;
}

// --- Legacy public helpers (delegate to U256 methods) ---

pub inline fn addmod(a: U256, b: U256, n: U256) U256 {
    return U256.addmod(a, b, n);
}

pub inline fn mulmod(a: U256, b: U256, n: U256) U256 {
    return U256.mulmod(a, b, n);
}

pub inline fn toLimbs(v: U256) [4]u64 {
    return v.toLimbs();
}

pub inline fn fromLimbs(limbs: [4]u64) U256 {
    return U256.fromLimbs(limbs);
}

pub inline fn div128by64(hi: u64, lo: u64, d: u64) struct { q: u64, r: u64 } {
    return U256.div128by64(hi, lo, d);
}

pub inline fn limbLessThan(a: [4]u64, b: [4]u64) bool {
    return U256.limbLessThan(a, b);
}

pub inline fn mulFull(a: U256, b: U256) [8]u64 {
    return U256.mulFull(a, b);
}

pub fn limbMod(comptime M: comptime_int, a: [M]u64, b: [4]u64) [4]u64 {
    return U256.limbMod(M, a, b);
}

pub fn mod512by256(a: [8]u64, b: [4]u64) U256 {
    return U256.fromLimbs(U256.limbMod(8, a, b));
}

pub inline fn expMod256(base: U256, exp_val: U256) U256 {
    return U256.exp(base, exp_val);
}

pub inline fn byteSize(x: U256) u64 {
    return x.byteSize();
}

pub inline fn sdiv(a: U256, b: U256) U256 {
    return U256.sdiv(a, b);
}

pub inline fn smod(a: U256, b: U256) U256 {
    return U256.smod(a, b);
}

pub inline fn signextend(byte_pos: U256, value: U256) U256 {
    return U256.signextend(byte_pos, value);
}

test {
    _ = @import("arithmetic_tests.zig");
}
