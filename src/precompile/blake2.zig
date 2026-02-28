const std = @import("std");
const primitives = @import("primitives");
const main = @import("main.zig");

/// BLAKE2 compression function precompile
pub const FUN = main.Precompile.new(
    main.PrecompileId.Blake2F,
    main.u64ToAddress(9),
    blake2fRun,
);

const F_ROUND: u64 = 1;
const INPUT_LENGTH: usize = 213;

/// BLAKE2 compression function
/// Reference: https://eips.ethereum.org/EIPS/eip-152
/// Input format:
/// [4 bytes for rounds][64 bytes for h][128 bytes for m][8 bytes for t_0][8 bytes for t_1][1 byte for f]
pub fn blake2fRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (input.len != INPUT_LENGTH) {
        return main.PrecompileResult{ .err = main.PrecompileError.Blake2WrongLength };
    }

    // Parse number of rounds (4 bytes, big-endian)
    const rounds = std.mem.readInt(u32, input[0..4], .big);
    const gas_used = @as(u64, rounds) * F_ROUND;
    if (gas_used > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // Parse final block flag
    const f_flag = input[212];
    if (f_flag > 1) {
        return main.PrecompileResult{ .err = main.PrecompileError.Blake2WrongFinalIndicatorFlag };
    }
    const f = f_flag == 1;

    // Parse state vector h (8 × u64, little-endian)
    var h: [8]u64 = undefined;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        h[i] = std.mem.readInt(u64, input[4 + i * 8 ..][0..8], .little);
    }

    // Parse message block m (16 × u64, little-endian)
    var m: [16]u64 = undefined;
    i = 0;
    while (i < 16) : (i += 1) {
        m[i] = std.mem.readInt(u64, input[68 + i * 8 ..][0..8], .little);
    }

    // Parse offset counters
    const t_0 = std.mem.readInt(u64, input[196..204], .little);
    const t_1 = std.mem.readInt(u64, input[204..212], .little);

    // Compress
    compress(@as(usize, rounds), &h, m, .{ t_0, t_1 }, f);

    // Output h as little-endian bytes
    var output: [64]u8 = undefined;
    i = 0;
    while (i < 8) : (i += 1) {
        std.mem.writeInt(u64, output[i * 8 ..][0..8], h[i], .little);
    }

    const heap_out = std.heap.c_allocator.dupe(u8, &output) catch
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_used, heap_out) };
}

/// SIGMA from spec: https://datatracker.ietf.org/doc/html/rfc7693#section-2.7
const SIGMA: [10][16]usize = .{
    .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
    .{ 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 },
    .{ 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4 },
    .{ 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8 },
    .{ 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13 },
    .{ 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9 },
    .{ 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11 },
    .{ 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10 },
    .{ 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5 },
    .{ 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0 },
};

/// IV from: https://en.wikipedia.org/wiki/BLAKE_(hash_function)
const IV: [8]u64 = .{
    0x6a09e667f3bcc908,
    0xbb67ae8584caa73b,
    0x3c6ef372fe94f82b,
    0xa54ff53a5f1d36f1,
    0x510e527fade682d1,
    0x9b05688c2b3e6c1f,
    0x1f83d9abfb41bd6b,
    0x5be0cd19137e2179,
};

/// G function: https://tools.ietf.org/html/rfc7693#section-3.1
inline fn g(v: *[16]u64, a: usize, b: usize, c: usize, d: usize, x: u64, y: u64) void {
    var va = v[a];
    var vb = v[b];
    var vc = v[c];
    var vd = v[d];

    va = va +% vb +% x;
    vd = (vd ^ va);
    vd = std.math.rotl(u64, vd, 32);
    vc = vc +% vd;
    vb = (vb ^ vc);
    vb = std.math.rotl(u64, vb, 24);

    va = va +% vb +% y;
    vd = (vd ^ va);
    vd = std.math.rotl(u64, vd, 16);
    vc = vc +% vd;
    vb = (vb ^ vc);
    vb = std.math.rotl(u64, vb, 63);

    v[a] = va;
    v[b] = vb;
    v[c] = vc;
    v[d] = vd;
}

/// Compression function F
fn compress(rounds: usize, h: *[8]u64, m: [16]u64, t: [2]u64, f: bool) void {
    var v: [16]u64 = undefined;
    // First half from state
    @memcpy(v[0..8], h);
    // Second half from IV
    @memcpy(v[8..16], &IV);

    v[12] ^= t[0];
    v[13] ^= t[1];

    if (f) {
        v[14] = ~v[14]; // Invert all bits if the last-block-flag is set
    }

    var i: usize = 0;
    while (i < rounds) : (i += 1) {
        round(&v, &m, i);
    }

    i = 0;
    while (i < 8) : (i += 1) {
        h[i] ^= v[i] ^ v[i + 8];
    }
}

/// Round function
inline fn round(v: *[16]u64, m: *const [16]u64, r: usize) void {
    const s = &SIGMA[r % 10];
    // g1
    g(v, 0, 4, 8, 12, m[s[0]], m[s[1]]);
    g(v, 1, 5, 9, 13, m[s[2]], m[s[3]]);
    g(v, 2, 6, 10, 14, m[s[4]], m[s[5]]);
    g(v, 3, 7, 11, 15, m[s[6]], m[s[7]]);
    // g2
    g(v, 0, 5, 10, 15, m[s[8]], m[s[9]]);
    g(v, 1, 6, 11, 12, m[s[10]], m[s[11]]);
    g(v, 2, 7, 8, 13, m[s[12]], m[s[13]]);
    g(v, 3, 4, 9, 14, m[s[14]], m[s[15]]);
}
