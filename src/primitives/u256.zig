const std = @import("std");

/// EVM 256-bit unsigned integer type.
/// C ABI compatible at FFI boundary via @bitCast to [4]u64.
pub const U256 = struct {
    val: u256,

    // --- Constants ---

    pub const ZERO = U256{ .val = 0 };
    pub const ONE = U256{ .val = 1 };
    pub const MAX = U256{ .val = std.math.maxInt(u256) };

    // --- Bridge ---

    pub inline fn toNative(self: U256) u256 {
        return self.val;
    }

    pub inline fn fromNative(v: u256) U256 {
        return .{ .val = v };
    }

    // --- Construction ---

    pub inline fn from(v: u64) U256 {
        return .{ .val = v };
    }

    pub inline fn fromU128(v: u128) U256 {
        return .{ .val = v };
    }

    /// Create from 32-byte big-endian representation (EVM convention).
    pub inline fn fromBytes(bytes: [32]u8) U256 {
        return .{ .val = @byteSwap(@as(u256, @bitCast(bytes))) };
    }

    pub inline fn fromLimbs(limbs: [4]u64) U256 {
        return .{ .val = @bitCast(limbs) };
    }

    // --- Conversion ---

    /// Convert to 32-byte big-endian representation (EVM convention).
    pub inline fn toBytes(self: U256) [32]u8 {
        return @bitCast(@byteSwap(self.val));
    }

    pub inline fn toLimbs(self: U256) [4]u64 {
        return @bitCast(self.val);
    }

    pub inline fn toU64(self: U256) ?u64 {
        if (self.val > std.math.maxInt(u64)) return null;
        return @truncate(self.val);
    }

    // --- Arithmetic ---

    pub inline fn add(a: U256, b: U256) U256 {
        return .{ .val = a.val +% b.val };
    }

    pub inline fn sub(a: U256, b: U256) U256 {
        return .{ .val = a.val -% b.val };
    }

    pub inline fn mul(a: U256, b: U256) U256 {
        return .{ .val = a.val *% b.val };
    }

    pub inline fn div(a: U256, b: U256) U256 {
        return if (b.val != 0) .{ .val = a.val / b.val } else ZERO;
    }

    pub inline fn mod(a: U256, b: U256) U256 {
        return if (b.val != 0) .{ .val = a.val % b.val } else ZERO;
    }

    pub fn sdiv(a: U256, b: U256) U256 {
        if (b.val == 0) return ZERO;
        const sign_bit: u256 = 1 << 255;
        const a_neg = (a.val & sign_bit) != 0;
        const b_neg = (b.val & sign_bit) != 0;
        const abs_a = if (a_neg) (~a.val) +% 1 else a.val;
        const abs_b = if (b_neg) (~b.val) +% 1 else b.val;
        const abs_result = abs_a / abs_b;
        return .{ .val = if (a_neg != b_neg) (~abs_result) +% 1 else abs_result };
    }

    pub fn smod(a: U256, b: U256) U256 {
        if (b.val == 0) return ZERO;
        const sign_bit: u256 = 1 << 255;
        const a_neg = (a.val & sign_bit) != 0;
        const b_neg = (b.val & sign_bit) != 0;
        const abs_a = if (a_neg) (~a.val) +% 1 else a.val;
        const abs_b = if (b_neg) (~b.val) +% 1 else b.val;
        const abs_result = abs_a % abs_b;
        return .{ .val = if (a_neg) (~abs_result) +% 1 else abs_result };
    }

    /// ADDMOD: (a + b) % n with 257-bit intermediate.
    pub fn addmod(a: U256, b: U256, n: U256) U256 {
        if (n.val == 0) return ZERO;
        const al: [4]u64 = @bitCast(a.val);
        const bl: [4]u64 = @bitCast(b.val);
        const nl: [4]u64 = @bitCast(n.val);

        var sum: [5]u64 = undefined;
        var carry: u64 = 0;
        inline for (0..4) |i| {
            const s: u128 = @as(u128, al[i]) + bl[i] + carry;
            sum[i] = @truncate(s);
            carry = @truncate(s >> 64);
        }
        sum[4] = carry;

        if (carry == 0 and limbLessThan(.{ sum[0], sum[1], sum[2], sum[3] }, nl)) {
            return .{ .val = @bitCast([4]u64{ sum[0], sum[1], sum[2], sum[3] }) };
        }
        return .{ .val = @bitCast(limbMod(5, sum, nl)) };
    }

    /// MULMOD: (a * b) % n with 512-bit intermediate.
    pub fn mulmod(a: U256, b: U256, n: U256) U256 {
        if (n.val == 0) {
            return ZERO;
        }
        if (a.val == 0 or b.val == 0) {
            return ZERO;
        }

        const nl: [4]u64 = @bitCast(n.val);
        const product = mulFull(a, b);

        if (product[4] | product[5] | product[6] | product[7] == 0) {
            const pl = [4]u64{ product[0], product[1], product[2], product[3] };
            if (limbLessThan(pl, nl)) return .{ .val = @bitCast(pl) };
            return .{ .val = @bitCast(limbMod(4, pl, nl)) };
        }

        return .{ .val = @bitCast(limbMod(8, product, nl)) };
    }

    /// EXP: square-and-multiply (mod 2^256).
    pub fn exp(base: U256, exponent: U256) U256 {
        var e = exponent.val;
        if (e == 0) return ONE;
        var result: u256 = 1;
        var b = base.val;
        while (e != 0) {
            if (e & 1 == 1) result = result *% b;
            e >>= 1;
            if (e != 0) b = b *% b;
        }
        return .{ .val = result };
    }

    /// SIGNEXTEND: Sign extend value from byte position.
    pub fn signextend(byte_pos: U256, value: U256) U256 {
        if (byte_pos.val >= 31) return value;
        const bit_pos: u8 = @intCast(byte_pos.val * 8 + 7);
        const sign_bit: u256 = @as(u256, 1) << @intCast(bit_pos);
        if ((value.val & sign_bit) != 0) {
            return .{ .val = value.val | (~@as(u256, 0) << @intCast(bit_pos)) };
        } else {
            return .{ .val = value.val & ((@as(u256, 1) << @intCast(bit_pos + 1)) -% 1) };
        }
    }

    // --- Bitwise ---

    pub inline fn bitAnd(a: U256, b: U256) U256 {
        return .{ .val = a.val & b.val };
    }

    pub inline fn bitOr(a: U256, b: U256) U256 {
        return .{ .val = a.val | b.val };
    }

    pub inline fn bitXor(a: U256, b: U256) U256 {
        return .{ .val = a.val ^ b.val };
    }

    pub inline fn bitNot(a: U256) U256 {
        return .{ .val = ~a.val };
    }

    pub inline fn getByte(i: U256, x: U256) U256 {
        return if (i.val < 32) .{ .val = (x.val >> @intCast((31 - i.val) * 8)) & 0xFF } else ZERO;
    }

    pub inline fn shl(shift: U256, value: U256) U256 {
        return if (shift.val < 256) .{ .val = value.val << @intCast(shift.val) } else ZERO;
    }

    pub inline fn shr(shift: U256, value: U256) U256 {
        return if (shift.val < 256) .{ .val = value.val >> @intCast(shift.val) } else ZERO;
    }

    pub fn sar(shift: U256, value: U256) U256 {
        const is_negative = (value.val >> 255) == 1;
        if (shift.val >= 256) return if (is_negative) MAX else ZERO;
        const sn: u8 = @intCast(shift.val);
        if (sn == 0) return value;
        const shifted = value.val >> @intCast(sn);
        if (is_negative) {
            const mask = ~@as(u256, 0) << @intCast(@as(u9, 256) - sn);
            return .{ .val = shifted | mask };
        }
        return .{ .val = shifted };
    }

    // --- Comparison (bool) ---

    pub inline fn lt(a: U256, b: U256) bool {
        return a.val < b.val;
    }

    pub inline fn gt(a: U256, b: U256) bool {
        return a.val > b.val;
    }

    pub inline fn slt(a: U256, b: U256) bool {
        const a_neg = (a.val >> 255) == 1;
        const b_neg = (b.val >> 255) == 1;
        if (a_neg == b_neg) return a.val < b.val;
        return a_neg;
    }

    pub inline fn sgt(a: U256, b: U256) bool {
        const a_neg = (a.val >> 255) == 1;
        const b_neg = (b.val >> 255) == 1;
        if (a_neg == b_neg) return a.val > b.val;
        return b_neg;
    }

    pub inline fn eql(a: U256, b: U256) bool {
        return a.val == b.val;
    }

    pub inline fn isZero(a: U256) bool {
        return a.val == 0;
    }

    // --- Comparison (U256 result for EVM stack pushes) ---

    pub inline fn ltU256(a: U256, b: U256) U256 {
        return .{ .val = @intFromBool(a.val < b.val) };
    }

    pub inline fn gtU256(a: U256, b: U256) U256 {
        return .{ .val = @intFromBool(a.val > b.val) };
    }

    pub inline fn sltU256(a: U256, b: U256) U256 {
        return .{ .val = @intFromBool(slt(a, b)) };
    }

    pub inline fn sgtU256(a: U256, b: U256) U256 {
        return .{ .val = @intFromBool(sgt(a, b)) };
    }

    pub inline fn eqlU256(a: U256, b: U256) U256 {
        return .{ .val = @intFromBool(a.val == b.val) };
    }

    pub inline fn isZeroU256(a: U256) U256 {
        return .{ .val = @intFromBool(a.val == 0) };
    }

    // --- Utility ---

    pub fn clz(self: U256) u9 {
        return @clz(self.val);
    }

    pub fn byteSize(self: U256) u64 {
        if (self.val == 0) return 0;
        return (256 - @as(u64, @clz(self.val)) + 7) / 8;
    }

    pub inline fn isNegative(self: U256) bool {
        return (self.val >> 255) == 1;
    }

    pub inline fn negate(self: U256) U256 {
        return .{ .val = (~self.val) +% 1 };
    }

    pub inline fn shlBy(self: U256, comptime n: u9) U256 {
        return .{ .val = self.val << n };
    }

    pub inline fn shrBy(self: U256, comptime n: u9) U256 {
        return .{ .val = self.val >> n };
    }

    /// std.fmt integration for debug printing
    pub fn format(self: *const U256, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try std.fmt.format(writer, "{}", .{self.val});
    }

    // --- Internal limb arithmetic helpers (for addmod/mulmod) ---

    pub inline fn limbLessThan(a: [4]u64, b: [4]u64) bool {
        var i: usize = 4;
        while (i > 0) {
            i -= 1;
            if (a[i] != b[i]) return a[i] < b[i];
        }
        return false;
    }

    pub inline fn div128by64(hi: u64, lo: u64, d: u64) struct { q: u64, r: u64 } {
        const dh: u64 = d >> 32;
        const dl: u64 = d & 0xFFFFFFFF;
        const lo_hi: u64 = lo >> 32;
        const lo_lo: u64 = lo & 0xFFFFFFFF;

        var q1: u64 = hi / dh;
        var r1: u64 = hi - q1 * dh;
        while (q1 >= (1 << 32) or q1 * dl > ((r1 << 32) | lo_hi)) {
            q1 -= 1;
            r1 += dh;
            if (r1 >= (1 << 32)) break;
        }

        const rem1: u128 = ((@as(u128, hi) << 32) | lo_hi) -% @as(u128, q1) * d;
        const rem1_64: u64 = @truncate(rem1);

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

    pub fn mulFull(a: U256, b: U256) [8]u64 {
        const al: [4]u64 = @bitCast(a.val);
        const bl: [4]u64 = @bitCast(b.val);
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

    pub fn limbMod(comptime M: comptime_int, a: [M]u64, b: [4]u64) [4]u64 {
        var n: usize = 0;
        for (0..4) |i| {
            if (b[3 - i] != 0) {
                n = 4 - i;
                break;
            }
        }
        if (n == 0) return [_]u64{0} ** 4;

        if (n == 1) {
            const d = b[0];
            const shift: u6 = @intCast(@clz(d));
            const d_norm = d << shift;

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

            var rem: u64 = 0;
            var i: usize = M;
            if (u_shifted[M] != 0) {
                rem = u_shifted[M];
            }
            while (i > 0) {
                i -= 1;
                const dv = div128by64(rem, u_shifted[i], d_norm);
                rem = dv.r;
            }

            rem >>= shift;
            return .{ rem, 0, 0, 0 };
        }

        const shift: u6 = @intCast(@clz(b[n - 1]));

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

        const m = M - n;

        var j: usize = m + 1;
        while (j > 0) {
            j -= 1;

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

            if (final_borrow != 0) {
                var add_carry: u64 = 0;
                for (0..n) |i| {
                    const sum: u128 = @as(u128, u[j + i]) + v[i] + add_carry;
                    u[j + i] = @truncate(sum);
                    add_carry = @intCast(sum >> 64);
                }
                u[j + n] +%= add_carry;
            }
        }

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
};

comptime {
    _ = @import("u256_tests.zig");
}
