//! mcl wrapper for BN254 (alt_bn128) operations
//! Requires mcl library to be installed and linked with C bindings
//!
//! mcl is required by default. Install mcl: https://github.com/herumi/mcl
const std = @import("std");

// Import mcl C API
// The Homebrew mcl package is compiled as bn_c384_256 (FP=384-bit, FR=256-bit)
// which supports both BLS12-381 and BN254.  Using bn_c256.h would compute
// MCLBN_COMPILED_TIME_VAR=44, but the library expects 46 (4*10+6), causing
// mclBn_init to return an error and leave all function pointers null.
const build_options = @import("build_options");

const c = if (build_options.enable_mcl) blk: {
    break :blk @cImport({
        @cDefine("MCL_FP_BIT", "384");
        @cDefine("MCL_FR_BIT", "256");
        @cInclude("mcl/bn.h");
    });
} else struct {
    // Stub types when mcl is disabled (should not happen by default)
    pub const mclBnFp = extern struct { d: [6]u64 = .{0} ** 6 };
    pub const mclBnFp2 = extern struct { d: [2]mclBnFp = .{.{}} ** 2 };
    pub const mclBnG1 = extern struct { x: mclBnFp = .{}, y: mclBnFp = .{}, z: mclBnFp = .{} };
    pub const mclBnG2 = extern struct { x: mclBnFp2 = .{}, y: mclBnFp2 = .{}, z: mclBnFp2 = .{} };
    pub const mclBnFr = extern struct { d: [4]u64 = .{0} ** 4 };
    pub const mclBnGT = extern struct { d: [12]mclBnFp = .{.{}} ** 12 };
    pub const mclSize = usize;
    pub fn mclBnFp_setBigEndianMod(_: *mclBnFp, _: *const anyopaque, _: mclSize) c_int { return -1; }
    pub fn mclBnFp_setInt32(_: *mclBnFp, _: c_int) void {}
    pub fn mclBnFp_getLittleEndian(_: *anyopaque, _: mclSize, _: *const mclBnFp) mclSize { return 0; }
    pub fn mclBnG1_clear(_: *mclBnG1) void {}
    pub fn mclBnG1_isZero(_: *const mclBnG1) c_int { return 1; }
    pub fn mclBnG1_isValid(_: *const mclBnG1) c_int { return 0; }
    pub fn mclBnG1_add(_: *mclBnG1, _: *const mclBnG1, _: *const mclBnG1) void {}
    pub fn mclBnG1_mul(_: *mclBnG1, _: *const mclBnG1, _: *const mclBnFr) void {}
    pub fn mclBnG1_normalize(_: *mclBnG1, _: *const mclBnG1) void {}
    pub fn mclBnG2_clear(_: *mclBnG2) void {}
    pub fn mclBnG2_isZero(_: *const mclBnG2) c_int { return 1; }
    pub fn mclBnG2_isValid(_: *const mclBnG2) c_int { return 0; }
    pub fn mclBnG2_normalize(_: *mclBnG2, _: *const mclBnG2) void {}
    pub fn mclBnFr_setBigEndianMod(_: *mclBnFr, _: *const anyopaque, _: mclSize) c_int { return -1; }
    pub fn mclBn_pairing(_: *mclBnGT, _: *const mclBnG1, _: *const mclBnG2) void {}
    pub fn mclBnGT_setInt(_: *mclBnGT, _: c_int) void {}
    pub fn mclBnGT_mul(_: *mclBnGT, _: *const mclBnGT, _: *const mclBnGT) void {}
    pub fn mclBnGT_isOne(_: *const mclBnGT) i32 { return 0; }
};

// Initialize mcl once (thread-safe initialization)
var mcl_initialized: std.Thread.Mutex = .{};
var mcl_init_done: bool = false;

/// Initialize mcl library (call once before using)
fn initMcl() void {
    mcl_initialized.lock();
    defer mcl_initialized.unlock();

    if (mcl_init_done) return;

    if (build_options.enable_mcl) {
        // Initialize mcl with BN254/SNARK1 curve.
        // MCL_BN_SNARK1=4; MCLBN_COMPILED_TIME_VAR=46 for bn_c384_256 (FP=384, FR=256).
        _ = c.mclBn_init(4, 46); // 4=MCL_BN_SNARK1, 46=MCLBN_COMPILED_TIME_VAR(384/256)
        mcl_init_done = true;
    }
}

/// Check if mcl is available
/// mcl is enabled by default, but can be disabled with -Dmcl=false
pub fn isAvailable() bool {
    return build_options.enable_mcl;
}

// ---------------------------------------------------------------------------
// Internal helpers: EVM-format <-> mcl point conversion
// ---------------------------------------------------------------------------

/// Construct a G1 point from EVM 64-byte format (32-byte big-endian x + 32-byte y).
/// All-zeros input is the identity/infinity point.
/// Returns error.InvalidG1Point if the bytes don't represent a valid curve point.
fn g1FromEVM(p: *c.mclBnG1, bytes: *const [64]u8) !void {
    // Identity / point-at-infinity: all zeros
    var all_zero = true;
    for (bytes) |b| {
        if (b != 0) { all_zero = false; break; }
    }
    if (all_zero) {
        c.mclBnG1_clear(p);
        return;
    }

    // Set x and y Fp coordinates from big-endian bytes (mod p)
    if (c.mclBnFp_setBigEndianMod(&p.x, bytes[0..32].ptr, 32) != 0) return error.InvalidG1Point;
    if (c.mclBnFp_setBigEndianMod(&p.y, bytes[32..64].ptr, 32) != 0) return error.InvalidG1Point;
    c.mclBnFp_setInt32(&p.z, 1); // affine z=1

    if (c.mclBnG1_isValid(p) == 0) return error.InvalidG1Point;
}

/// Serialize a G1 point to EVM 64-byte format (32-byte big-endian x + 32-byte y).
/// The identity/infinity point serializes as 64 zero bytes.
fn g1ToEVM(out: *[64]u8, p: *const c.mclBnG1) void {
    if (c.mclBnG1_isZero(p) != 0) {
        @memset(out, 0);
        return;
    }
    var normed: c.mclBnG1 = undefined;
    c.mclBnG1_normalize(&normed, p);

    // getLittleEndian returns up to 48 bytes for 384-bit Fp; BN254 Fp fits in 32.
    var xle: [48]u8 = [_]u8{0} ** 48;
    var yle: [48]u8 = [_]u8{0} ** 48;
    _ = c.mclBnFp_getLittleEndian(&xle, 48, &normed.x);
    _ = c.mclBnFp_getLittleEndian(&yle, 48, &normed.y);

    // Reverse little-endian to big-endian (32 bytes each for BN254)
    for (0..32) |i| out[i] = xle[31 - i];
    for (0..32) |i| out[32 + i] = yle[31 - i];
}

/// Construct a G2 point from EVM 128-byte format.
/// EIP-197 layout: x.imag(32) || x.real(32) || y.imag(32) || y.real(32)
/// In mcl mclBnFp2: d[0]=real, d[1]=imag
fn g2FromEVM(p: *c.mclBnG2, bytes: *const [128]u8) !void {
    var all_zero = true;
    for (bytes) |b| {
        if (b != 0) { all_zero = false; break; }
    }
    if (all_zero) {
        c.mclBnG2_clear(p);
        return;
    }

    if (c.mclBnFp_setBigEndianMod(&p.x.d[1], bytes[0..32].ptr, 32) != 0) return error.InvalidG2Point;   // x.imag
    if (c.mclBnFp_setBigEndianMod(&p.x.d[0], bytes[32..64].ptr, 32) != 0) return error.InvalidG2Point;  // x.real
    if (c.mclBnFp_setBigEndianMod(&p.y.d[1], bytes[64..96].ptr, 32) != 0) return error.InvalidG2Point;  // y.imag
    if (c.mclBnFp_setBigEndianMod(&p.y.d[0], bytes[96..128].ptr, 32) != 0) return error.InvalidG2Point; // y.real
    c.mclBnFp_setInt32(&p.z.d[0], 1); // affine z.real=1
    c.mclBnFp_setInt32(&p.z.d[1], 0); // z.imag=0

    if (c.mclBnG2_isValid(p) == 0) return error.InvalidG2Point;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// BN254 G1 point addition
/// Input: two 64-byte G1 points (x || y, each 32 bytes, big-endian)
/// Output: 64-byte G1 point (x || y, big-endian)
pub fn g1Add(a: [64]u8, b: [64]u8) ![64]u8 {
    if (!isAvailable()) return error.MclNotAvailable;
    initMcl();

    var p1: c.mclBnG1 = undefined;
    var p2: c.mclBnG1 = undefined;
    try g1FromEVM(&p1, &a);
    try g1FromEVM(&p2, &b);

    var result: c.mclBnG1 = undefined;
    c.mclBnG1_add(&result, &p1, &p2);

    var output: [64]u8 = undefined;
    g1ToEVM(&output, &result);
    return output;
}

/// BN254 G1 scalar multiplication
/// Input: 64-byte G1 point, 32-byte scalar (big-endian)
/// Output: 64-byte G1 point (x || y, big-endian)
pub fn g1Mul(point: [64]u8, scalar: [32]u8) ![64]u8 {
    if (!isAvailable()) return error.MclNotAvailable;
    initMcl();

    var p: c.mclBnG1 = undefined;
    try g1FromEVM(&p, &point);

    // Scalar is big-endian 32 bytes; use setBigEndianMod for Fr
    var s: c.mclBnFr = undefined;
    if (c.mclBnFr_setBigEndianMod(&s, &scalar, 32) != 0) return error.InvalidInput;

    var result: c.mclBnG1 = undefined;
    c.mclBnG1_mul(&result, &p, &s);

    var output: [64]u8 = undefined;
    g1ToEVM(&output, &result);
    return output;
}

/// BN254 pairing check
/// Input: array of (G1, G2) point pairs
/// Returns true if pairing product equals identity (pairing is valid)
pub fn pairingCheck(pairs: []const struct { g1: [64]u8, g2: [128]u8 }) !bool {
    if (!isAvailable()) return error.MclNotAvailable;
    if (pairs.len == 0) return true;
    initMcl();

    var gt_result: c.mclBnGT = undefined;
    c.mclBnGT_setInt(&gt_result, 1);

    for (pairs) |pair| {
        var g1: c.mclBnG1 = undefined;
        try g1FromEVM(&g1, &pair.g1);

        var g2: c.mclBnG2 = undefined;
        try g2FromEVM(&g2, &pair.g2);

        var temp_gt: c.mclBnGT = undefined;
        c.mclBn_pairing(&temp_gt, &g1, &g2);

        var new_result: c.mclBnGT = undefined;
        c.mclBnGT_mul(&new_result, &gt_result, &temp_gt);
        gt_result = new_result;
    }

    return c.mclBnGT_isOne(&gt_result) != 0;
}

pub const MclError = error{
    MclNotAvailable,
    InvalidG1Point,
    InvalidG2Point,
    InvalidInput,
};
