//! blst wrapper for BLS12-381 and KZG operations
//! Requires blst library to be installed and linked
//!
//! To use this wrapper:
//! 1. Install blst: https://github.com/supranational/blst
//! 2. Uncomment the blst linking in build.zig
//! 3. Ensure blst.h is in your include path
const std = @import("std");

// Import blst C API
// This will fail at compile time if blst.h is not found
// Install blst: https://github.com/supranational/blst
const build_options = @import("build_options");
const c = if (build_options.enable_blst) blk: {
    break :blk @cImport({
        @cInclude("blst.h");
    });
} else struct {
    // Stub types when blst is disabled (should not happen by default)
    pub const blst_fp = extern struct { l: [6]u64 = undefined };
    pub const blst_fp2 = extern struct { fp: [2]blst_fp = undefined };
    pub const blst_p1 = extern struct { x: blst_fp = undefined, y: blst_fp = undefined, z: blst_fp = undefined };
    pub const blst_p1_affine = extern struct { x: blst_fp = undefined, y: blst_fp = undefined };
    pub const blst_p2 = extern struct { x: blst_fp2 = undefined, y: blst_fp2 = undefined, z: blst_fp2 = undefined };
    pub const blst_p2_affine = extern struct { x: blst_fp2 = undefined, y: blst_fp2 = undefined };
    pub const blst_scalar = extern struct { b: [32]u8 = undefined };
    pub const blst_fp12 = extern struct { fp6: [2]extern struct { fp2: [3]blst_fp2 = undefined } = undefined };
    pub const BLS12_381_G1 = blst_p1_affine{};
    pub const BLS12_381_G2 = blst_p2_affine{};
    pub fn blst_fp_from_bendian(_: *blst_fp, _: *const [48]u8) void {}
    pub fn blst_bendian_from_fp(_: *[48]u8, _: *const blst_fp) void {}
    pub fn blst_scalar_from_bendian(_: *blst_scalar, _: *const [32]u8) void {}
    pub fn blst_p1_affine_on_curve(_: *const blst_p1_affine) bool {
        return false;
    }
    pub fn blst_p1_affine_in_g1(_: *const blst_p1_affine) bool {
        return false;
    }
    pub fn blst_p2_affine_on_curve(_: *const blst_p2_affine) bool {
        return false;
    }
    pub fn blst_p2_affine_in_g2(_: *const blst_p2_affine) bool {
        return false;
    }
    pub fn blst_p1_from_affine(_: *blst_p1, _: *const blst_p1_affine) void {}
    pub fn blst_p1_to_affine(_: *blst_p1_affine, _: *const blst_p1) void {}
    pub fn blst_p2_from_affine(_: *blst_p2, _: *const blst_p2_affine) void {}
    pub fn blst_p2_to_affine(_: *blst_p2_affine, _: *const blst_p2) void {}
    pub fn blst_p1_add_or_double_affine(_: *blst_p1, _: *const blst_p1, _: *const blst_p1_affine) void {}
    pub fn blst_p2_add_or_double_affine(_: *blst_p2, _: *const blst_p2, _: *const blst_p2_affine) void {}
    pub fn blst_p1s_mult_pippenger(_: *blst_p1, _: [*]const *const blst_p1_affine, _: i32, _: [*]const *const u8, _: i32, _: ?*anyopaque) void {}
    pub fn blst_p2s_mult_pippenger(_: *blst_p2, _: [*]const *const blst_p2_affine, _: i32, _: [*]const *const u8, _: i32, _: ?*anyopaque) void {}
    pub fn blst_p1s_mult_pippenger_scratch_sizeof(_: usize) usize { return 0; }
    pub fn blst_p2s_mult_pippenger_scratch_sizeof(_: usize) usize { return 0; }
    pub fn blst_p1_cneg(_: *blst_p1, _: bool) void {}
    pub fn blst_p2_cneg(_: *blst_p2, _: bool) void {}
    pub fn blst_p1_add(_: *blst_p1, _: *const blst_p1, _: *const blst_p1) void {}
    pub fn blst_p2_add(_: *blst_p2, _: *const blst_p2, _: *const blst_p2) void {}
    pub fn blst_miller_loop(_: *blst_fp12, _: *const blst_p2_affine, _: *const blst_p1_affine) void {}
    pub fn blst_fp12_mul(_: *blst_fp12, _: *const blst_fp12, _: *const blst_fp12) void {}
    pub fn blst_final_exp(_: *blst_fp12, _: *const blst_fp12) void {}
    pub fn blst_fp12_is_one(_: *const blst_fp12) bool {
        return false;
    }
    pub fn blst_map_to_g1(_: *blst_p1, _: *const blst_fp, _: ?*const anyopaque) void {}
    pub fn blst_map_to_g2(_: *blst_p2, _: *const blst_fp2, _: ?*const anyopaque) void {}
    pub fn blst_p1_uncompress(_: *blst_p1_affine, _: *const [48]u8) i32 {
        return 0;
    }
    pub fn blst_p2_uncompress(_: *blst_p2_affine, _: *const [96]u8) i32 {
        return 0;
    }
    pub fn blst_p1_mult(_: *blst_p1, _: *const blst_p1, _: *const blst_scalar, _: i32) void {}
    pub fn blst_p2_mult(_: *blst_p2, _: *const blst_p2, _: *const blst_scalar, _: i32) void {}
    pub fn blst_p1_sub(_: *blst_p1, _: *const blst_p1, _: *const blst_p1) void {}
    pub fn blst_p2_sub(_: *blst_p2, _: *const blst_p2, _: *const blst_p2) void {}
    pub fn blst_p2_neg(_: *blst_p2, _: *const blst_p2) void {}
};

/// Check if blst is available
/// blst is enabled by default, but can be disabled with -Dblst=false
pub fn isAvailable() bool {
    return build_options.enable_blst;
}

/// BLS12-381 field prime p (big-endian, 48 bytes):
/// p = 0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab
const BLS_FP_MODULUS: [48]u8 = .{
    0x1a, 0x01, 0x11, 0xea, 0x39, 0x7f, 0xe6, 0x9a,
    0x4b, 0x1b, 0xa7, 0xb6, 0x43, 0x4b, 0xac, 0xd7,
    0x64, 0x77, 0x4b, 0x84, 0xf3, 0x85, 0x12, 0xbf,
    0x67, 0x30, 0xd2, 0xa0, 0xf6, 0xb0, 0xf6, 0x24,
    0x1e, 0xab, 0xff, 0xfe, 0xb1, 0x53, 0xff, 0xff,
    0xb9, 0xfe, 0xff, 0xff, 0xff, 0xff, 0xaa, 0xab,
};

/// Returns true if the 48-byte big-endian value is a canonical field element (0 <= x < p).
/// EIP-2537 requires all Fp inputs to be canonical; blst_fp_from_bendian silently reduces mod p.
fn isFpCanonical(bytes: *const [48]u8) bool {
    return std.mem.order(u8, bytes, &BLS_FP_MODULUS) == .lt;
}

/// Parse a G1 affine point from 96 bytes, returning error for invalid non-infinity points.
/// Treats all-zero bytes as the point at infinity (valid).
fn parseG1Affine(bytes: [96]u8, affine: *c.blst_p1_affine) !bool {
    // All-zero bytes = point at infinity (identity element)
    const zero96 = [_]u8{0} ** 96;
    if (std.mem.eql(u8, &bytes, &zero96)) return true; // is_infinity

    // EIP-2537: field elements must be canonical (0 <= x < p)
    if (!isFpCanonical(bytes[0..48]) or !isFpCanonical(bytes[48..96])) {
        return error.NonCanonicalFieldElement;
    }

    var fp_x: c.blst_fp = undefined;
    var fp_y: c.blst_fp = undefined;
    c.blst_fp_from_bendian(&fp_x, bytes[0..48]);
    c.blst_fp_from_bendian(&fp_y, bytes[48..96]);
    affine.x = fp_x;
    affine.y = fp_y;

    // For G1Add: only check on-curve, NOT subgroup membership (per EIP-2537)
    if (!c.blst_p1_affine_on_curve(affine)) return error.InvalidG1Point;
    return false; // not infinity
}

/// BLS12-381 G1 point addition
/// Input: two 96-byte unpadded G1 points (x || y, each 48 bytes, big-endian)
/// Output: 96-byte unpadded G1 point
/// Note: EIP-2537 G1Add accepts points not in the prime-order subgroup (only on-curve required)
pub fn g1Add(a: [96]u8, b: [96]u8) ![96]u8 {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    var p1_affine: c.blst_p1_affine = undefined;
    var p2_affine: c.blst_p1_affine = undefined;

    const a_is_inf = try parseG1Affine(a, &p1_affine);
    const b_is_inf = try parseG1Affine(b, &p2_affine);

    // Handle infinity (identity element): infinity + P = P
    if (a_is_inf and b_is_inf) return [_]u8{0} ** 96;
    if (a_is_inf) {
        var output: [96]u8 = undefined;
        c.blst_bendian_from_fp(output[0..48], &p2_affine.x);
        c.blst_bendian_from_fp(output[48..96], &p2_affine.y);
        return output;
    }
    if (b_is_inf) {
        var output: [96]u8 = undefined;
        c.blst_bendian_from_fp(output[0..48], &p1_affine.x);
        c.blst_bendian_from_fp(output[48..96], &p1_affine.y);
        return output;
    }

    // Convert to projective form and add
    var p1: c.blst_p1 = undefined;
    c.blst_p1_from_affine(&p1, &p1_affine);

    var result: c.blst_p1 = undefined;
    c.blst_p1_add_or_double_affine(&result, &p1, &p2_affine);

    // Convert back to affine and serialize
    var result_affine: c.blst_p1_affine = undefined;
    c.blst_p1_to_affine(&result_affine, &result);

    var output: [96]u8 = undefined;
    c.blst_bendian_from_fp(output[0..48], &result_affine.x);
    c.blst_bendian_from_fp(output[48..96], &result_affine.y);

    return output;
}

/// BLS12-381 G1 multi-scalar multiplication
/// Input: array of (point, scalar) pairs
/// Output: 96-byte unpadded G1 point
/// Note: G1MSM requires points to be in the G1 prime-order subgroup (per EIP-2537)
///       Scalars are 32 bytes big-endian (passed directly to pippenger)
pub fn g1Msm(pairs: []const struct { point: [96]u8, scalar: [32]u8 }) ![96]u8 {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    if (pairs.len == 0) {
        return error.InvalidInput;
    }

    const zero96 = [_]u8{0} ** 96;

    // Parse points and scalars, filtering out infinity points (they contribute identity)
    var points = try std.heap.c_allocator.alloc(c.blst_p1_affine, pairs.len);
    defer std.heap.c_allocator.free(points);
    var point_ptrs = try std.heap.c_allocator.alloc(*const c.blst_p1_affine, pairs.len);
    defer std.heap.c_allocator.free(point_ptrs);
    var scalar_ptrs = try std.heap.c_allocator.alloc(*const u8, pairs.len);
    defer std.heap.c_allocator.free(scalar_ptrs);
    // blst_scalar stores scalars in little-endian; blst_scalar_from_bendian converts from EIP-2537 big-endian
    var scalars = try std.heap.c_allocator.alloc(c.blst_scalar, pairs.len);
    defer std.heap.c_allocator.free(scalars);

    var active_count: usize = 0;
    for (pairs) |pair| {
        // Skip infinity points (identity contributes nothing to MSM sum)
        if (std.mem.eql(u8, &pair.point, &zero96)) continue;

        const i = active_count;

        // EIP-2537: field elements must be canonical (0 <= x < p)
        if (!isFpCanonical(pair.point[0..48]) or !isFpCanonical(pair.point[48..96])) {
            return error.NonCanonicalFieldElement;
        }

        var fp_x: c.blst_fp = undefined;
        var fp_y: c.blst_fp = undefined;
        c.blst_fp_from_bendian(&fp_x, pair.point[0..48]);
        c.blst_fp_from_bendian(&fp_y, pair.point[48..96]);
        points[i].x = fp_x;
        points[i].y = fp_y;

        // G1MSM requires subgroup membership
        if (!c.blst_p1_affine_on_curve(&points[i]) or !c.blst_p1_affine_in_g1(&points[i])) {
            return error.InvalidG1Point;
        }

        // Convert scalar from big-endian (EIP-2537) to little-endian (blst pippenger format)
        c.blst_scalar_from_bendian(&scalars[i], &pair.scalar);
        point_ptrs[i] = &points[i];
        scalar_ptrs[i] = @ptrCast(&scalars[i].b[0]);
        active_count += 1;
    }

    // If all points were infinity, result is infinity
    if (active_count == 0) return [_]u8{0} ** 96;

    // Allocate scratch space for MSM
    const scratch_size = c.blst_p1s_mult_pippenger_scratch_sizeof(active_count);
    const alloc_size = if (scratch_size == 0) @as(usize, 8) else scratch_size;
    const scratch_bytes = try std.heap.page_allocator.alloc(u8, alloc_size);
    defer std.heap.page_allocator.free(scratch_bytes);

    var result: c.blst_p1 = undefined;
    c.blst_p1s_mult_pippenger(&result, point_ptrs.ptr, @intCast(active_count), scalar_ptrs.ptr, 256, @ptrCast(@alignCast(scratch_bytes.ptr)));

    var result_affine: c.blst_p1_affine = undefined;
    c.blst_p1_to_affine(&result_affine, &result);

    var output: [96]u8 = undefined;
    c.blst_bendian_from_fp(output[0..48], &result_affine.x);
    c.blst_bendian_from_fp(output[48..96], &result_affine.y);

    return output;
}

/// Parse a G2 affine point from 192 bytes, returning error for invalid non-infinity points.
/// Treats all-zero bytes as the point at infinity (identity element).
/// EIP-2537 G2 input: [Fp2.fp[0] (48B) || Fp2.fp[1] (48B)] for each of x and y.
/// blst blst_fp2: fp[0] and fp[1] map directly to the input bytes (direct mapping, no swap).
fn parseG2Affine(bytes: [192]u8, affine: *c.blst_p2_affine) !bool {
    const zero192 = [_]u8{0} ** 192;
    if (std.mem.eql(u8, &bytes, &zero192)) return true; // is_infinity

    // EIP-2537: all four Fp components of Fp2 must be canonical (0 <= x < p)
    if (!isFpCanonical(bytes[0..48]) or !isFpCanonical(bytes[48..96]) or
        !isFpCanonical(bytes[96..144]) or !isFpCanonical(bytes[144..192]))
    {
        return error.NonCanonicalFieldElement;
    }

    // Direct mapping: EIP-2537 encodes Fp2 as two consecutive 48-byte field elements.
    // blst's blst_fp2.fp[0] = first element, fp[1] = second element.
    c.blst_fp_from_bendian(&affine.x.fp[0], bytes[0..48]);
    c.blst_fp_from_bendian(&affine.x.fp[1], bytes[48..96]);
    c.blst_fp_from_bendian(&affine.y.fp[0], bytes[96..144]);
    c.blst_fp_from_bendian(&affine.y.fp[1], bytes[144..192]);

    // For G2Add: only check on-curve, NOT subgroup membership (per EIP-2537)
    if (!c.blst_p2_affine_on_curve(affine)) return error.InvalidG2Point;
    return false; // not infinity
}

/// BLS12-381 G2 point addition
/// Input: two 192-byte unpadded G2 points
/// Output: 192-byte unpadded G2 point
/// Note: EIP-2537 G2Add accepts points not in the prime-order subgroup (only on-curve required)
pub fn g2Add(a: [192]u8, b: [192]u8) ![192]u8 {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    var p1_affine: c.blst_p2_affine = undefined;
    var p2_affine: c.blst_p2_affine = undefined;

    const a_is_inf = try parseG2Affine(a, &p1_affine);
    const b_is_inf = try parseG2Affine(b, &p2_affine);

    // Handle infinity (identity element)
    if (a_is_inf and b_is_inf) return [_]u8{0} ** 192;
    if (a_is_inf) {
        var output: [192]u8 = undefined;
        c.blst_bendian_from_fp(output[0..48], &p2_affine.x.fp[0]);
        c.blst_bendian_from_fp(output[48..96], &p2_affine.x.fp[1]);
        c.blst_bendian_from_fp(output[96..144], &p2_affine.y.fp[0]);
        c.blst_bendian_from_fp(output[144..192], &p2_affine.y.fp[1]);
        return output;
    }
    if (b_is_inf) {
        var output: [192]u8 = undefined;
        c.blst_bendian_from_fp(output[0..48], &p1_affine.x.fp[0]);
        c.blst_bendian_from_fp(output[48..96], &p1_affine.x.fp[1]);
        c.blst_bendian_from_fp(output[96..144], &p1_affine.y.fp[0]);
        c.blst_bendian_from_fp(output[144..192], &p1_affine.y.fp[1]);
        return output;
    }

    // Convert to projective and add
    var p1: c.blst_p2 = undefined;
    c.blst_p2_from_affine(&p1, &p1_affine);

    var result: c.blst_p2 = undefined;
    c.blst_p2_add_or_double_affine(&result, &p1, &p2_affine);

    // Convert back to affine and serialize (direct mapping)
    var result_affine: c.blst_p2_affine = undefined;
    c.blst_p2_to_affine(&result_affine, &result);

    var output: [192]u8 = undefined;
    c.blst_bendian_from_fp(output[0..48], &result_affine.x.fp[0]);
    c.blst_bendian_from_fp(output[48..96], &result_affine.x.fp[1]);
    c.blst_bendian_from_fp(output[96..144], &result_affine.y.fp[0]);
    c.blst_bendian_from_fp(output[144..192], &result_affine.y.fp[1]);

    return output;
}

/// BLS12-381 G2 multi-scalar multiplication
/// Input: array of (point, scalar) pairs
/// Output: 192-byte unpadded G2 point
/// Note: G2MSM requires points to be in the G2 prime-order subgroup (per EIP-2537)
///       Scalars are 32 bytes big-endian (passed directly to pippenger)
pub fn g2Msm(pairs: []const struct { point: [192]u8, scalar: [32]u8 }) ![192]u8 {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    if (pairs.len == 0) {
        return error.InvalidInput;
    }

    const zero192 = [_]u8{0} ** 192;

    var points = try std.heap.c_allocator.alloc(c.blst_p2_affine, pairs.len);
    defer std.heap.c_allocator.free(points);
    var point_ptrs = try std.heap.c_allocator.alloc(*const c.blst_p2_affine, pairs.len);
    defer std.heap.c_allocator.free(point_ptrs);
    var scalar_ptrs = try std.heap.c_allocator.alloc(*const u8, pairs.len);
    defer std.heap.c_allocator.free(scalar_ptrs);
    // blst_scalar stores scalars in little-endian; blst_scalar_from_bendian converts from EIP-2537 big-endian
    var scalars = try std.heap.c_allocator.alloc(c.blst_scalar, pairs.len);
    defer std.heap.c_allocator.free(scalars);

    var active_count: usize = 0;
    for (pairs) |pair| {
        // Skip infinity points (identity contributes nothing to MSM sum)
        if (std.mem.eql(u8, &pair.point, &zero192)) continue;

        const i = active_count;

        // EIP-2537: all four Fp components of Fp2 must be canonical (0 <= x < p)
        if (!isFpCanonical(pair.point[0..48]) or !isFpCanonical(pair.point[48..96]) or
            !isFpCanonical(pair.point[96..144]) or !isFpCanonical(pair.point[144..192]))
        {
            return error.NonCanonicalFieldElement;
        }

        // Direct mapping: EIP-2537 Fp2 bytes map to blst fp2.fp[0] and fp2.fp[1] directly
        c.blst_fp_from_bendian(&points[i].x.fp[0], pair.point[0..48]);
        c.blst_fp_from_bendian(&points[i].x.fp[1], pair.point[48..96]);
        c.blst_fp_from_bendian(&points[i].y.fp[0], pair.point[96..144]);
        c.blst_fp_from_bendian(&points[i].y.fp[1], pair.point[144..192]);

        // G2MSM requires subgroup membership
        if (!c.blst_p2_affine_on_curve(&points[i]) or !c.blst_p2_affine_in_g2(&points[i])) {
            return error.InvalidG2Point;
        }

        // Convert scalar from big-endian (EIP-2537) to little-endian (blst pippenger format)
        c.blst_scalar_from_bendian(&scalars[i], &pair.scalar);
        point_ptrs[i] = &points[i];
        scalar_ptrs[i] = @ptrCast(&scalars[i].b[0]);
        active_count += 1;
    }

    if (active_count == 0) return [_]u8{0} ** 192;

    const scratch_size = c.blst_p2s_mult_pippenger_scratch_sizeof(active_count);
    const alloc_size = if (scratch_size == 0) @as(usize, 8) else scratch_size;
    const scratch_bytes = try std.heap.page_allocator.alloc(u8, alloc_size);
    defer std.heap.page_allocator.free(scratch_bytes);

    var result: c.blst_p2 = undefined;
    c.blst_p2s_mult_pippenger(&result, point_ptrs.ptr, @intCast(active_count), scalar_ptrs.ptr, 256, @ptrCast(@alignCast(scratch_bytes.ptr)));

    var result_affine: c.blst_p2_affine = undefined;
    c.blst_p2_to_affine(&result_affine, &result);

    // Direct mapping output (same as input convention)
    var output: [192]u8 = undefined;
    c.blst_bendian_from_fp(output[0..48], &result_affine.x.fp[0]);
    c.blst_bendian_from_fp(output[48..96], &result_affine.x.fp[1]);
    c.blst_bendian_from_fp(output[96..144], &result_affine.y.fp[0]);
    c.blst_bendian_from_fp(output[144..192], &result_affine.y.fp[1]);

    return output;
}

/// BLS12-381 pairing check
/// Input: array of (G1, G2) point pairs
/// Returns true if pairing product == 1 (identity in GT)
/// Pairs where G1 or G2 is the point at infinity are skipped (they contribute 1 to product)
pub fn pairingCheck(pairs: []const struct { g1: [96]u8, g2: [192]u8 }) !bool {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    if (pairs.len == 0) {
        return true; // Empty pairing is valid (product of no terms = 1)
    }

    const zero96 = [_]u8{0} ** 96;
    const zero192 = [_]u8{0} ** 192;

    // Parse valid (non-infinity) pairs
    var g1_points = try std.heap.c_allocator.alloc(c.blst_p1_affine, pairs.len);
    defer std.heap.c_allocator.free(g1_points);
    var g2_points = try std.heap.c_allocator.alloc(c.blst_p2_affine, pairs.len);
    defer std.heap.c_allocator.free(g2_points);

    var active_count: usize = 0;

    for (pairs) |pair| {
        // Skip pairs where either point is infinity (they contribute 1 to product)
        if (std.mem.eql(u8, &pair.g1, &zero96) or std.mem.eql(u8, &pair.g2, &zero192)) continue;

        const i = active_count;

        // EIP-2537: G1 field elements must be canonical (0 <= x < p)
        if (!isFpCanonical(pair.g1[0..48]) or !isFpCanonical(pair.g1[48..96])) {
            return error.NonCanonicalFieldElement;
        }

        // Parse G1 point
        var fp_x: c.blst_fp = undefined;
        var fp_y: c.blst_fp = undefined;
        c.blst_fp_from_bendian(&fp_x, pair.g1[0..48]);
        c.blst_fp_from_bendian(&fp_y, pair.g1[48..96]);
        g1_points[i].x = fp_x;
        g1_points[i].y = fp_y;

        // Pairing requires both G1 and G2 to be in their respective subgroups
        if (!c.blst_p1_affine_on_curve(&g1_points[i]) or !c.blst_p1_affine_in_g1(&g1_points[i])) {
            return error.InvalidG1Point;
        }

        // EIP-2537: G2 field elements must be canonical (0 <= x < p)
        if (!isFpCanonical(pair.g2[0..48]) or !isFpCanonical(pair.g2[48..96]) or
            !isFpCanonical(pair.g2[96..144]) or !isFpCanonical(pair.g2[144..192]))
        {
            return error.NonCanonicalFieldElement;
        }

        // Parse G2 point — direct mapping (no swap)
        c.blst_fp_from_bendian(&g2_points[i].x.fp[0], pair.g2[0..48]);
        c.blst_fp_from_bendian(&g2_points[i].x.fp[1], pair.g2[48..96]);
        c.blst_fp_from_bendian(&g2_points[i].y.fp[0], pair.g2[96..144]);
        c.blst_fp_from_bendian(&g2_points[i].y.fp[1], pair.g2[144..192]);

        if (!c.blst_p2_affine_on_curve(&g2_points[i]) or !c.blst_p2_affine_in_g2(&g2_points[i])) {
            return error.InvalidG2Point;
        }

        active_count += 1;
    }

    // If all pairs were infinity, result is 1 (valid)
    if (active_count == 0) return true;

    // Compute pairing product over active pairs only
    var fp12: c.blst_fp12 = undefined;
    c.blst_miller_loop(&fp12, &g2_points[0], &g1_points[0]);

    for (1..active_count) |i| {
        var temp: c.blst_fp12 = undefined;
        c.blst_miller_loop(&temp, &g2_points[i], &g1_points[i]);
        c.blst_fp12_mul(&fp12, &fp12, &temp);
    }

    var result: c.blst_fp12 = undefined;
    c.blst_final_exp(&result, &fp12);

    return c.blst_fp12_is_one(&result);
}

/// BLS12-381 map field element to G1
/// Input: 48-byte field element
/// Output: 96-byte unpadded G1 point
pub fn mapFpToG1(fp: [48]u8) ![96]u8 {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    // EIP-2537: field element must be canonical (0 <= fp < p)
    if (!isFpCanonical(&fp)) {
        return error.NonCanonicalFieldElement;
    }

    // Parse field element
    var fp_elem: c.blst_fp = undefined;
    c.blst_fp_from_bendian(&fp_elem, &fp);

    // Map to G1
    var result: c.blst_p1 = undefined;
    c.blst_map_to_g1(&result, &fp_elem, null);

    // Convert to affine and serialize
    var result_affine: c.blst_p1_affine = undefined;
    c.blst_p1_to_affine(&result_affine, &result);

    var output: [96]u8 = undefined;
    c.blst_bendian_from_fp(output[0..48], &result_affine.x);
    c.blst_bendian_from_fp(output[48..96], &result_affine.y);

    return output;
}

/// BLS12-381 map field element to G2
/// Input: 96-byte Fp2 element
/// Output: 192-byte unpadded G2 point
pub fn mapFp2ToG2(fp2: [96]u8) ![192]u8 {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    // EIP-2537: both Fp2 components must be canonical (0 <= x < p)
    if (!isFpCanonical(fp2[0..48]) or !isFpCanonical(fp2[48..96])) {
        return error.NonCanonicalFieldElement;
    }

    // Parse Fp2 element — direct mapping: fp[0] = first 48 bytes, fp[1] = second 48 bytes
    var fp2_elem: c.blst_fp2 = undefined;
    c.blst_fp_from_bendian(&fp2_elem.fp[0], &fp2[0..48].*);
    c.blst_fp_from_bendian(&fp2_elem.fp[1], &fp2[48..96].*);

    // Map to G2
    var result: c.blst_p2 = undefined;
    c.blst_map_to_g2(&result, &fp2_elem, null);

    // Convert to affine and serialize
    var result_affine: c.blst_p2_affine = undefined;
    c.blst_p2_to_affine(&result_affine, &result);

    // Serialize with direct mapping (fp[0] first, fp[1] second)
    var output: [192]u8 = undefined;
    c.blst_bendian_from_fp(output[0..48], &result_affine.x.fp[0]);
    c.blst_bendian_from_fp(output[48..96], &result_affine.x.fp[1]);
    c.blst_bendian_from_fp(output[96..144], &result_affine.y.fp[0]);
    c.blst_bendian_from_fp(output[144..192], &result_affine.y.fp[1]);

    return output;
}

/// Ethereum KZG trusted setup G2 point [τ]₂
/// This is g2_monomial_1 from trusted_setup_4096.json
/// Taken from: https://github.com/ethereum/consensus-specs/blob/adc514a1c29532ebc1a67c71dc8741a2fdac5ed4/presets/mainnet/trusted_setups/trusted_setup_4096.json
const TRUSTED_SETUP_TAU_G2_BYTES: [96]u8 = .{
    0xb5, 0xbf, 0xd7, 0xdd, 0x8c, 0xde, 0xb1, 0x28, 0x84, 0x3b, 0xc2, 0x87, 0x23, 0x0a, 0xf3, 0x89,
    0x26, 0x18, 0x70, 0x75, 0xcb, 0xfb, 0xef, 0xa8, 0x10, 0x09, 0xa2, 0xce, 0x61, 0x5a, 0xc5, 0x3d,
    0x29, 0x14, 0xe5, 0x87, 0x0c, 0xb4, 0x52, 0xd2, 0xaf, 0xaa, 0xab, 0x24, 0xf3, 0x49, 0x9f, 0x72,
    0x18, 0x5c, 0xbf, 0xee, 0x53, 0x49, 0x27, 0x14, 0x73, 0x44, 0x29, 0xb7, 0xb3, 0x86, 0x08, 0xe2,
    0x39, 0x26, 0xc9, 0x11, 0xcc, 0xec, 0xea, 0xc9, 0xa3, 0x68, 0x51, 0x47, 0x7b, 0xa4, 0xc6, 0x0b,
    0x08, 0x70, 0x41, 0xde, 0x62, 0x10, 0x00, 0xed, 0xc9, 0x8e, 0xda, 0xda, 0x20, 0xc1, 0xde, 0xf2,
};

/// KZG proof verification
/// commitment: 48-byte G1 point (compressed)
/// z: 32-byte field element
/// y: 32-byte field element
/// proof: 48-byte G1 point (compressed)
///
/// This requires the Ethereum KZG trusted setup (tau G2 point)
/// Verifies: e(commitment - [y]G1, -G2) * e(proof, [τ]G2 - [z]G2) == 1
pub fn verifyKzgProof(commitment: [48]u8, z: [32]u8, y: [32]u8, proof: [48]u8) !bool {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    // Parse commitment as compressed G1 point
    var commitment_affine: c.blst_p1_affine = undefined;
    if (c.blst_p1_uncompress(&commitment_affine, &commitment) != 0) {
        return false; // Invalid G1 point
    }
    if (!c.blst_p1_affine_on_curve(&commitment_affine) or
        !c.blst_p1_affine_in_g1(&commitment_affine))
    {
        return false;
    }

    // Parse proof as compressed G1 point
    var proof_affine: c.blst_p1_affine = undefined;
    if (c.blst_p1_uncompress(&proof_affine, &proof) != 0) {
        return false; // Invalid G1 point
    }
    if (!c.blst_p1_affine_on_curve(&proof_affine) or
        !c.blst_p1_affine_in_g1(&proof_affine))
    {
        return false;
    }

    // Parse z and y as scalar field elements (Fr)
    var z_scalar: c.blst_scalar = undefined;
    var y_scalar: c.blst_scalar = undefined;
    c.blst_scalar_from_bendian(&z_scalar, &z);
    c.blst_scalar_from_bendian(&y_scalar, &y);

    // Get trusted setup G2 point [τ]G2
    var tau_g2_affine: c.blst_p2_affine = undefined;
    if (c.blst_p2_uncompress(&tau_g2_affine, &TRUSTED_SETUP_TAU_G2_BYTES) != 0) {
        return false; // Invalid trusted setup point
    }

    // Get generators
    const g1_generator = c.BLS12_381_G1;
    const g2_generator = c.BLS12_381_G2;

    // Compute [y]G1
    var g1_projective: c.blst_p1 = undefined;
    c.blst_p1_from_affine(&g1_projective, &g1_generator);
    var y_g1: c.blst_p1 = undefined;
    c.blst_p1_mult(&y_g1, &g1_projective, @ptrCast(@as(*const u8, @ptrCast(&y_scalar))), 8 * 32);
    var y_g1_affine: c.blst_p1_affine = undefined;
    c.blst_p1_to_affine(&y_g1_affine, &y_g1);

    // Compute commitment - [y]G1 = P_minus_y
    var commitment_proj: c.blst_p1 = undefined;
    c.blst_p1_from_affine(&commitment_proj, &commitment_affine);
    var y_g1_neg: c.blst_p1 = y_g1;
    c.blst_p1_cneg(&y_g1_neg, true); // Negate y_g1
    var p_minus_y: c.blst_p1 = undefined;
    c.blst_p1_add(&p_minus_y, &commitment_proj, &y_g1_neg);
    var p_minus_y_affine: c.blst_p1_affine = undefined;
    c.blst_p1_to_affine(&p_minus_y_affine, &p_minus_y);

    // Compute [z]G2
    var g2_projective: c.blst_p2 = undefined;
    c.blst_p2_from_affine(&g2_projective, &g2_generator);
    var z_g2: c.blst_p2 = undefined;
    c.blst_p2_mult(&z_g2, &g2_projective, @ptrCast(@as(*const u8, @ptrCast(&z_scalar))), 8 * 32);
    var z_g2_affine: c.blst_p2_affine = undefined;
    c.blst_p2_to_affine(&z_g2_affine, &z_g2);

    // Compute [τ]G2 - [z]G2 = X_minus_z
    var tau_g2_proj: c.blst_p2 = undefined;
    c.blst_p2_from_affine(&tau_g2_proj, &tau_g2_affine);
    var z_g2_neg_for_x: c.blst_p2 = z_g2;
    c.blst_p2_cneg(&z_g2_neg_for_x, true); // Negate z_g2
    var x_minus_z: c.blst_p2 = undefined;
    c.blst_p2_add(&x_minus_z, &tau_g2_proj, &z_g2_neg_for_x);
    var x_minus_z_affine: c.blst_p2_affine = undefined;
    c.blst_p2_to_affine(&x_minus_z_affine, &x_minus_z);

    // Compute -G2
    var neg_g2: c.blst_p2 = g2_projective;
    c.blst_p2_cneg(&neg_g2, true); // Negate G2
    var neg_g2_affine: c.blst_p2_affine = undefined;
    c.blst_p2_to_affine(&neg_g2_affine, &neg_g2);

    // Verify pairing: e(P - y, -G2) * e(proof, X - z) == 1
    // This is equivalent to checking if the product equals identity
    var fp12_1: c.blst_fp12 = undefined;
    c.blst_miller_loop(&fp12_1, &neg_g2_affine, &p_minus_y_affine);

    var fp12_2: c.blst_fp12 = undefined;
    c.blst_miller_loop(&fp12_2, &x_minus_z_affine, &proof_affine);

    var fp12_product: c.blst_fp12 = undefined;
    c.blst_fp12_mul(&fp12_product, &fp12_1, &fp12_2);

    var fp12_result: c.blst_fp12 = undefined;
    c.blst_final_exp(&fp12_result, &fp12_product);

    // Check if result is identity (pairing is valid if result == 1)
    return c.blst_fp12_is_one(&fp12_result);
}

pub const BlstError = error{
    BlstNotAvailable,
    InvalidG1Point,
    InvalidG2Point,
    InvalidInput,
    NonCanonicalFieldElement,
};
