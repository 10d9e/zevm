const std = @import("std");

/// RIPEMD-160 hash function implementation
/// Full two-line (left + right) RIPEMD-160 per the Dobbertin/Bosselaers/Preneel spec.
pub fn ripemd160(input: []const u8) [20]u8 {
    var ctx = Context.init();
    ctx.update(input);
    return ctx.final();
}

// ─── Round message-word permutations ────────────────────────────────────────

// Left line
const RL = [80]u32{
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, // r1
    7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8, // r2
    3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12, // r3
    1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2, // r4
    4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13, // r5
};

// Right line
const RR = [80]u32{
    5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12, // r'1
    6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2, // r'2
    15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13, // r'3
    8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14, // r'4
    12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11, // r'5
};

// ─── Shift amounts ───────────────────────────────────────────────────────────

// Left line
const SL = [80]u32{
    11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8, // r1
    7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12, // r2
    11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5, // r3
    11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12, // r4
    9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6, // r5
};

// Right line
const SR = [80]u32{
    8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6, // r'1
    9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11, // r'2
    9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5, // r'3
    15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8, // r'4
    8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11, // r'5
};

// ─── Round constants ─────────────────────────────────────────────────────────

const KL = [5]u32{ 0x00000000, 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC, 0xA953FD4E };
const KR = [5]u32{ 0x50A28BE6, 0x5C4DD124, 0x6D703EF3, 0x7A6D76E9, 0x00000000 };

// ─── Boolean functions ───────────────────────────────────────────────────────

inline fn f1(x: u32, y: u32, z: u32) u32 {
    return x ^ y ^ z;
}
inline fn f2(x: u32, y: u32, z: u32) u32 {
    return (x & y) | (~x & z);
}
inline fn f3(x: u32, y: u32, z: u32) u32 {
    return (x | ~y) ^ z;
}
inline fn f4(x: u32, y: u32, z: u32) u32 {
    return (x & z) | (y & ~z);
}
inline fn f5(x: u32, y: u32, z: u32) u32 {
    return x ^ (y | ~z);
}

// ─── Context ─────────────────────────────────────────────────────────────────

const Context = struct {
    h: [5]u32,
    total: u64,
    buf: [64]u8,
    buflen: usize,

    pub fn init() Context {
        return Context{
            .h = [_]u32{
                0x67452301,
                0xEFCDAB89,
                0x98BADCFE,
                0x10325476,
                0xC3D2E1F0,
            },
            .total = 0,
            .buf = [_]u8{0} ** 64,
            .buflen = 0,
        };
    }

    pub fn update(self: *Context, input: []const u8) void {
        var i: usize = 0;
        while (i < input.len) {
            const space = 64 - self.buflen;
            const to_copy = @min(space, input.len - i);
            @memcpy(self.buf[self.buflen..][0..to_copy], input[i..][0..to_copy]);
            self.buflen += to_copy;
            i += to_copy;

            if (self.buflen == 64) {
                self.processBlock();
                self.buflen = 0;
            }
        }
        self.total += input.len;
    }

    pub fn final(self: *Context) [20]u8 {
        // Append 0x80 padding byte
        self.buf[self.buflen] = 0x80;
        self.buflen += 1;

        // If not enough room for the 8-byte length, flush and start new block
        if (self.buflen > 56) {
            @memset(self.buf[self.buflen..64], 0);
            self.processBlock();
            self.buflen = 0;
        }

        // Zero-pad up to byte 56
        @memset(self.buf[self.buflen..56], 0);

        // Append bit length as little-endian u64
        const bit_len = self.total * 8;
        std.mem.writeInt(u64, self.buf[56..64], bit_len, .little);
        self.processBlock();

        // Serialize hash state as little-endian u32 words
        var output: [20]u8 = undefined;
        for (0..5) |i| {
            std.mem.writeInt(u32, output[i * 4 ..][0..4], self.h[i], .little);
        }
        return output;
    }

    fn processBlock(self: *Context) void {
        // Load message words (little-endian u32)
        var w: [16]u32 = undefined;
        for (0..16) |i| {
            w[i] = std.mem.readInt(u32, self.buf[i * 4 ..][0..4], .little);
        }

        // ── Left line ──────────────────────────────────────────────────────
        var al = self.h[0];
        var bl = self.h[1];
        var cl = self.h[2];
        var dl = self.h[3];
        var el = self.h[4];

        for (0..80) |i| {
            const round: u32 = @intCast(i / 16);
            const f = switch (round) {
                0 => f1(bl, cl, dl),
                1 => f2(bl, cl, dl),
                2 => f3(bl, cl, dl),
                3 => f4(bl, cl, dl),
                else => f5(bl, cl, dl),
            };
            const t = std.math.rotl(u32, al +% f +% w[RL[i]] +% KL[round], SL[i]) +% el;
            al = el;
            el = dl;
            dl = std.math.rotl(u32, cl, 10);
            cl = bl;
            bl = t;
        }

        // ── Right line ─────────────────────────────────────────────────────
        var ar = self.h[0];
        var br = self.h[1];
        var cr = self.h[2];
        var dr = self.h[3];
        var er = self.h[4];

        for (0..80) |i| {
            const round: u32 = @intCast(i / 16);
            const f = switch (round) {
                0 => f5(br, cr, dr),
                1 => f4(br, cr, dr),
                2 => f3(br, cr, dr),
                3 => f2(br, cr, dr),
                else => f1(br, cr, dr),
            };
            const t = std.math.rotl(u32, ar +% f +% w[RR[i]] +% KR[round], SR[i]) +% er;
            ar = er;
            er = dr;
            dr = std.math.rotl(u32, cr, 10);
            cr = br;
            br = t;
        }

        // ── Combine both lines with initial state ──────────────────────────
        const t = self.h[1] +% cl +% dr;
        self.h[1] = self.h[2] +% dl +% er;
        self.h[2] = self.h[3] +% el +% ar;
        self.h[3] = self.h[4] +% al +% br;
        self.h[4] = self.h[0] +% bl +% cr;
        self.h[0] = t;
    }
};

// ─── Test vectors ─────────────────────────────────────────────────────────────

test "RIPEMD-160: empty string" {
    const result = ripemd160(&.{});
    // RIPEMD-160("") = 9c1185a5c5e9fc54612808977ee8f548b2258d31
    const expected = [20]u8{ 0x9c, 0x11, 0x85, 0xa5, 0xc5, 0xe9, 0xfc, 0x54, 0x61, 0x28, 0x08, 0x97, 0x7e, 0xe8, 0xf5, 0x48, 0xb2, 0x25, 0x8d, 0x31 };
    try std.testing.expectEqual(expected, result);
}

test "RIPEMD-160: abc" {
    const result = ripemd160("abc");
    // RIPEMD-160("abc") = 8eb208f7e05d987a9b044a8e98c6b087f15a0bfc
    const expected = [20]u8{ 0x8e, 0xb2, 0x08, 0xf7, 0xe0, 0x5d, 0x98, 0x7a, 0x9b, 0x04, 0x4a, 0x8e, 0x98, 0xc6, 0xb0, 0x87, 0xf1, 0x5a, 0x0b, 0xfc };
    try std.testing.expectEqual(expected, result);
}

test "RIPEMD-160: message longer than one block" {
    // "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    // = 84983e441c3bd26ebaae4aa1f95129e5e54670f1
    const input = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    const result = ripemd160(input);
    const expected = [20]u8{ 0x84, 0x98, 0x3e, 0x44, 0x1c, 0x3b, 0xd2, 0x6e, 0xba, 0xae, 0x4a, 0xa1, 0xf9, 0x51, 0x29, 0xe5, 0xe5, 0x46, 0x70, 0xf1 };
    try std.testing.expectEqual(expected, result);
}
