const std = @import("std");
const primitives = @import("primitives");
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const gas_costs = @import("../gas_costs.zig");

/// ADD opcode (0x01): a + b (wrapping mod 2^256)
/// Stack: [a, b] -> [a + b]   Static gas: 3 (VERYLOW, charged by dispatch)
pub fn opAdd(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a +% b;
}

/// SUB opcode (0x03): a - b (wrapping mod 2^256)
/// Stack: [a, b] -> [a - b]   Static gas: 3 (VERYLOW)
pub fn opSub(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a -% b;
}

/// MUL opcode (0x02): a * b (wrapping mod 2^256)
/// Stack: [a, b] -> [a * b]   Static gas: 5 (LOW)
pub fn opMul(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a *% b;
}

/// DIV opcode (0x04): a / b (unsigned, division by zero returns 0)
/// Stack: [a, b] -> [a / b]   Static gas: 5 (LOW)
pub fn opDiv(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = if (b != 0) a / b else 0;
}

/// SDIV opcode (0x05): a / b (signed, division by zero returns 0)
/// Stack: [a, b] -> [a / b]   Static gas: 5 (LOW)
pub fn opSdiv(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = sdiv(a, b);
}

/// MOD opcode (0x06): a % b (unsigned, mod by zero returns 0)
/// Stack: [a, b] -> [a % b]   Static gas: 5 (LOW)
pub fn opMod(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = if (b != 0) a % b else 0;
}

/// SMOD opcode (0x07): a % b (signed, mod by zero returns 0)
/// Stack: [a, b] -> [a % b]   Static gas: 5 (LOW)
pub fn opSmod(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = smod(a, b);
}

/// ADDMOD opcode (0x08): (a + b) % N with u257 intermediate
/// Stack: [a, b, N] -> [(a + b) % N]   Static gas: 8 (MID)
pub fn opAddmod(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(3)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    const n = stack.peekUnsafe(2);
    stack.shrinkUnsafe(2);
    stack.setTopUnsafe().* = addmod(a, b, n);
}

/// MULMOD opcode (0x09): (a * b) % N with u512 intermediate
/// Stack: [a, b, N] -> [(a * b) % N]   Static gas: 8 (MID)
pub fn opMulmod(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(3)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    const n = stack.peekUnsafe(2);
    stack.shrinkUnsafe(2);
    stack.setTopUnsafe().* = mulmod(a, b, n);
}

/// EXP opcode (0x0A): base ^ exponent (mod 2^256)
/// Stack: [base, exponent] -> [base ^ exponent]
/// Static gas: 10 (G_EXP, charged by dispatch) + dynamic: G_EXPBYTE * byteSize(exponent)
/// EIP-160 (Spurious Dragon): G_EXPBYTE raised from 10 to 50.
pub fn opExp(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const exponent = stack.peekUnsafe(1);
    // Dynamic gas: G_EXPBYTE per byte of exponent (10 pre-Spurious Dragon, 50 post)
    const spec = ctx.interpreter.runtime_flags.spec_id;
    const expbyte_cost: u64 = if (primitives.isEnabledIn(spec, .spurious_dragon))
        gas_costs.G_EXPBYTE
    else
        gas_costs.G_EXPBYTE_FRONTIER;
    const dynamic_gas = expbyte_cost * byteSize(exponent);
    if (!ctx.interpreter.gas.spend(dynamic_gas)) {
        ctx.interpreter.halt(.out_of_gas);
        return;
    }
    const base = stack.peekUnsafe(0);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = expMod256(base, exponent);
}

/// SIGNEXTEND opcode (0x0B): Sign extend value from byte position
/// Stack: [byte_pos, value] -> [extended_value]   Static gas: 5 (LOW)
pub fn opSignextend(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const byte_pos = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = signextend(byte_pos, value);
}

// --- Helpers ---

/// Compute (a + b) % n using full limb arithmetic.
/// Returns 0 when n == 0 (per EVM spec).
pub fn addmod(a: primitives.U256, b: primitives.U256, n: primitives.U256) primitives.U256 {
    if (n == 0) return 0;
    const al = toLimbs(a);
    const bl = toLimbs(b);
    const nl = toLimbs(n);

    // Add a + b → 5 limbs (carry in limb 4)
    var sum: [5]u64 = undefined;
    var carry: u64 = 0;
    inline for (0..4) |i| {
        const s: u128 = @as(u128, al[i]) + bl[i] + carry;
        sum[i] = @truncate(s);
        carry = @truncate(s >> 64);
    }
    sum[4] = carry;

    // Fast path: no carry and sum < n
    if (carry == 0 and limbLessThan(.{ sum[0], sum[1], sum[2], sum[3] }, nl)) {
        return fromLimbs(.{ sum[0], sum[1], sum[2], sum[3] });
    }

    return fromLimbs(limbMod(5, sum, nl));
}

/// Compute (a * b) % n using schoolbook 256x256→512 multiply + Knuth division.
/// O(1) fixed operations. Uses only u64 hardware division via div128by64.
/// Returns 0 when n == 0 (per EVM spec).
pub fn mulmod(a: primitives.U256, b: primitives.U256, n: primitives.U256) primitives.U256 {
    if (n == 0) return 0;
    if (a == 0 or b == 0) return 0;
    const nl = toLimbs(n);
    const product = mulFull(a, b);
    // Fast path: product fits in 256 bits
    if (product[4] | product[5] | product[6] | product[7] == 0) {
        const pl = [4]u64{ product[0], product[1], product[2], product[3] };
        if (limbLessThan(pl, nl)) return fromLimbs(pl);
        return fromLimbs(limbMod(4, pl, nl));
    }
    return fromLimbs(limbMod(8, product, nl));
}

/// Decompose u256 into 4 little-endian u64 limbs.
pub inline fn toLimbs(v: primitives.U256) [4]u64 {
    return .{
        @truncate(v),
        @truncate(v >> 64),
        @truncate(v >> 128),
        @truncate(v >> 192),
    };
}

/// Reassemble 4 little-endian u64 limbs into u256.
pub inline fn fromLimbs(limbs: [4]u64) primitives.U256 {
    return @as(primitives.U256, limbs[0]) |
        (@as(primitives.U256, limbs[1]) << 64) |
        (@as(primitives.U256, limbs[2]) << 128) |
        (@as(primitives.U256, limbs[3]) << 192);
}

/// 128÷64 division using 2 u64 divisions (Hacker's Delight "divlu").
/// Precondition: hi < d, d has MSB set (i.e., d >= 2^63).
/// Returns quotient and remainder, both u64.
pub inline fn div128by64(hi: u64, lo: u64, d: u64) struct { q: u64, r: u64 } {
    const dh: u64 = d >> 32;
    const dl: u64 = d & 0xFFFFFFFF;
    const lo_hi: u64 = lo >> 32;
    const lo_lo: u64 = lo & 0xFFFFFFFF;

    // First quotient digit (high 32 bits of q)
    var q1: u64 = hi / dh;
    var r1: u64 = hi - q1 * dh;
    // Refine: while q1 >= 2^32 or q1*dl > r1:lo_hi
    while (q1 >= (1 << 32) or q1 * dl > ((r1 << 32) | lo_hi)) {
        q1 -= 1;
        r1 += dh;
        if (r1 >= (1 << 32)) break;
    }

    // New partial remainder
    const rem1: u128 = ((@as(u128, hi) << 32) | lo_hi) -% @as(u128, q1) * d;
    const rem1_64: u64 = @truncate(rem1);

    // Second quotient digit (low 32 bits of q)
    var q0: u64 = rem1_64 / dh;
    var r0: u64 = rem1_64 - q0 * dh;
    while (q0 >= (1 << 32) or q0 * dl > ((r0 << 32) | lo_lo)) {
        q0 -= 1;
        r0 += dh;
        if (r0 >= (1 << 32)) break;
    }

    const rem0: u128 = ((@as(u128, rem1_64) << 32) | lo_lo) -% @as(u128, q0) * d;

    return .{ .q = (q1 << 32) | q0, .r = @truncate(rem0) };
}

/// Compare two [4]u64 limb arrays (little-endian). Returns true if a < b.
pub inline fn limbLessThan(a: [4]u64, b: [4]u64) bool {
    var i: usize = 4;
    while (i > 0) {
        i -= 1;
        if (a[i] != b[i]) return a[i] < b[i];
    }
    return false;
}

/// Schoolbook 4x4 multiplication: a * b → 8 little-endian u64 limbs (512 bits).
pub fn mulFull(a: primitives.U256, b: primitives.U256) [8]u64 {
    const al = toLimbs(a);
    const bl = toLimbs(b);
    var result = [_]u64{0} ** 8;

    inline for (0..4) |i| {
        var carry: u128 = 0;
        inline for (0..4) |j| {
            const prod: u128 = @as(u128, al[i]) * @as(u128, bl[j]) + result[i + j] + carry;
            result[i + j] = @truncate(prod);
            carry = prod >> 64;
        }
        result[i + 4] = @truncate(carry);
    }

    return result;
}

/// Generalized M-limb mod 4-limb using Knuth's Algorithm D with div128by64.
/// M is the number of dividend limbs (4, 5, or 8). Uses only u64 hardware division.
pub fn limbMod(comptime M: comptime_int, a: [M]u64, b: [4]u64) [4]u64 {
    // Find highest non-zero limb in divisor
    var n: usize = 0;
    for (0..4) |i| {
        if (b[3 - i] != 0) {
            n = 4 - i;
            break;
        }
    }
    if (n == 0) return [_]u64{0} ** 4; // divisor is zero

    // Single-limb divisor fast path: chain of div128by64 calls
    if (n == 1) {
        const d = b[0];
        const shift: u6 = @intCast(@clz(d));
        const d_norm = d << shift;

        // Shift entire dividend by `shift` bits
        var u_shifted: [M + 1]u64 = [_]u64{0} ** (M + 1);
        if (shift == 0) {
            for (0..M) |i| u_shifted[i] = a[i];
        } else {
            var carry: u64 = 0;
            for (0..M) |i| {
                u_shifted[i] = (a[i] << shift) | carry;
                carry = a[i] >> @intCast(@as(u7, 64) - shift);
            }
            u_shifted[M] = carry;
        }

        // Chain divide from most significant limb
        var rem: u64 = 0;
        var i: usize = M;
        // If shift produced an extra limb
        if (u_shifted[M] != 0) {
            rem = u_shifted[M];
        }
        while (i > 0) {
            i -= 1;
            const dv = div128by64(rem, u_shifted[i], d_norm);
            rem = dv.r;
        }

        // Denormalize remainder
        rem >>= shift;
        return .{ rem, 0, 0, 0 };
    }

    // Normalize: shift divisor so MSB of top limb is set
    const shift: u6 = @intCast(@clz(b[n - 1]));

    // Shift divisor
    var v = [_]u64{0} ** 4;
    if (shift == 0) {
        for (0..n) |i| v[i] = b[i];
    } else {
        var carry: u64 = 0;
        for (0..n) |i| {
            v[i] = (b[i] << shift) | carry;
            carry = b[i] >> @intCast(@as(u7, 64) - shift);
        }
    }

    // Shift dividend (need M+1 limbs for overflow)
    var u: [M + 1]u64 = [_]u64{0} ** (M + 1);
    if (shift == 0) {
        for (0..M) |i| u[i] = a[i];
    } else {
        var carry: u64 = 0;
        for (0..M) |i| {
            u[i] = (a[i] << shift) | carry;
            carry = a[i] >> @intCast(@as(u7, 64) - shift);
        }
        u[M] = carry;
    }

    const m = M - n; // Number of quotient limbs

    // Knuth's Algorithm D division loop
    var j: usize = m + 1;
    while (j > 0) {
        j -= 1;

        // Estimate quotient digit using div128by64
        var q_hat: u64 = undefined;
        var r_hat: u64 = undefined;
        if (u[j + n] >= v[n - 1]) {
            q_hat = std.math.maxInt(u64);
            r_hat = u[j + n - 1] +% v[n - 1];
            if (r_hat >= v[n - 1]) {
                if (r_hat < u[j + n - 1]) {
                    // Overflowed, skip refinement
                } else if (n >= 2) {
                    const prod_check: u128 = @as(u128, q_hat) * v[n - 2];
                    const rhs: u128 = (@as(u128, r_hat) << 64) | u[j + n - 2];
                    if (prod_check > rhs) {
                        q_hat -= 1;
                    }
                }
            }
        } else {
            const dv = div128by64(u[j + n], u[j + n - 1], v[n - 1]);
            q_hat = dv.q;
            r_hat = dv.r;

            if (n >= 2) {
                while (true) {
                    const prod_check: u128 = @as(u128, q_hat) * v[n - 2];
                    const rhs: u128 = (@as(u128, r_hat) << 64) | u[j + n - 2];
                    if (prod_check <= rhs) break;
                    q_hat -= 1;
                    const new_r = @addWithOverflow(r_hat, v[n - 1]);
                    r_hat = new_r[0];
                    if (new_r[1] != 0) break;
                }
            }
        }

        // Multiply and subtract: u[j..j+n] -= q_hat * v[0..n]
        var carry: u128 = 0;
        var borrow: u128 = 0;
        for (0..n) |i| {
            const prod: u128 = @as(u128, q_hat) * v[i] + carry;
            carry = prod >> 64;
            const sub_val: u128 = (prod & 0xFFFFFFFFFFFFFFFF) + borrow;
            const diff: u128 = @as(u128, u[j + i]) + (@as(u128, 1) << 64) - sub_val;
            u[j + i] = @truncate(diff);
            borrow = 1 - (diff >> 64);
        }

        const sub_final: u128 = carry + borrow;
        const diff_final: u128 = @as(u128, u[j + n]) + (@as(u128, 1) << 64) - sub_final;
        u[j + n] = @truncate(diff_final);
        const final_borrow: u64 = @intCast(1 - (diff_final >> 64));

        // Add back if over-subtracted
        if (final_borrow != 0) {
            var add_carry: u64 = 0;
            for (0..n) |i| {
                const s: u128 = @as(u128, u[j + i]) + v[i] + add_carry;
                u[j + i] = @truncate(s);
                add_carry = @intCast(s >> 64);
            }
            u[j + n] +%= add_carry;
        }
    }

    // Denormalize remainder
    var r_limbs = [_]u64{0} ** 4;
    if (shift == 0) {
        for (0..n) |i| r_limbs[i] = u[i];
    } else {
        for (0..n - 1) |i| {
            r_limbs[i] = (u[i] >> shift) | (u[i + 1] << @intCast(@as(u7, 64) - shift));
        }
        r_limbs[n - 1] = u[n - 1] >> shift;
    }

    return r_limbs;
}

/// 512-bit mod 256-bit (wrapper around limbMod).
pub fn mod512by256(a: [8]u64, b: [4]u64) primitives.U256 {
    return fromLimbs(limbMod(8, a, b));
}

/// Square-and-multiply modular exponentiation (mod 2^256).
pub fn expMod256(base: primitives.U256, exp: primitives.U256) primitives.U256 {
    if (exp == 0) return 1;
    var result: primitives.U256 = 1;
    var b = base;
    var e = exp;
    while (e != 0) {
        if (e & 1 == 1) {
            result = result *% b;
        }
        e >>= 1;
        if (e != 0) {
            b = b *% b;
        }
    }
    return result;
}

/// Number of bytes needed to represent x (0 returns 0).
pub fn byteSize(x: primitives.U256) u64 {
    if (x == 0) return 0;
    return (256 - @as(u64, @clz(x)) + 7) / 8;
}

/// Signed division: a / b in two's complement.
/// Returns 0 when b == 0 (per EVM spec).
/// Special case: MIN / -1 = MIN (overflow wraps).
pub fn sdiv(a: primitives.U256, b: primitives.U256) primitives.U256 {
    if (b == 0) return 0;

    const sign_bit: primitives.U256 = 1 << 255;
    const a_negative = (a & sign_bit) != 0;
    const b_negative = (b & sign_bit) != 0;

    const abs_a = if (a_negative) (~a) +% 1 else a;
    const abs_b = if (b_negative) (~b) +% 1 else b;

    const abs_result = abs_a / abs_b;

    const result_negative = a_negative != b_negative;
    return if (result_negative) (~abs_result) +% 1 else abs_result;
}

/// Signed modulo: a % b in two's complement.
/// Returns 0 when b == 0 (per EVM spec).
/// Result has the same sign as dividend a.
pub fn smod(a: primitives.U256, b: primitives.U256) primitives.U256 {
    if (b == 0) return 0;

    const sign_bit: primitives.U256 = 1 << 255;
    const a_negative = (a & sign_bit) != 0;
    const b_negative = (b & sign_bit) != 0;

    const abs_a = if (a_negative) (~a) +% 1 else a;
    const abs_b = if (b_negative) (~b) +% 1 else b;

    const abs_result = abs_a % abs_b;

    return if (a_negative) (~abs_result) +% 1 else abs_result;
}

/// Sign extend value from byte position.
pub fn signextend(byte_pos: primitives.U256, value: primitives.U256) primitives.U256 {
    if (byte_pos >= 31) return value;

    const byte_pos_usize: usize = @intCast(byte_pos);
    const bit_pos = (byte_pos_usize * 8) + 7;
    const sign_bit: primitives.U256 = @as(primitives.U256, 1) << @intCast(bit_pos);

    if ((value & sign_bit) != 0) {
        const mask = (~@as(primitives.U256, 0)) << @intCast(bit_pos);
        return value | mask;
    } else {
        const mask = (@as(primitives.U256, 1) << @intCast(bit_pos + 1)) -% 1;
        return value & mask;
    }
}

test {
    _ = @import("arithmetic_tests.zig");
}
