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

/// BLS12-381 G1 point addition
/// Input: two 96-byte unpadded G1 points (x || y, each 48 bytes, big-endian)
/// Output: 96-byte unpadded G1 point
pub fn g1Add(a: [96]u8, b: [96]u8) ![96]u8 {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    // Parse G1 points from bytes
    // blst expects points in affine form (x, y coordinates)
    var p1_affine: c.blst_p1_affine = undefined;
    var p2_affine: c.blst_p1_affine = undefined;

    // Parse first point (a)
    // Points are stored as (x || y) where each is 48 bytes big-endian
    const a_x = a[0..48].*;
    const a_y = a[48..96].*;

    // Convert big-endian bytes to blst_fp
    var fp1_x: c.blst_fp = undefined;
    var fp1_y: c.blst_fp = undefined;
    c.blst_fp_from_bendian(&fp1_x, &a_x);
    c.blst_fp_from_bendian(&fp1_y, &a_y);

    // Set affine coordinates
    p1_affine.x = fp1_x;
    p1_affine.y = fp1_y;

    // Parse second point (b)
    const b_x = b[0..48].*;
    const b_y = b[48..96].*;

    var fp2_x: c.blst_fp = undefined;
    var fp2_y: c.blst_fp = undefined;
    c.blst_fp_from_bendian(&fp2_x, &b_x);
    c.blst_fp_from_bendian(&fp2_y, &b_y);

    p2_affine.x = fp2_x;
    p2_affine.y = fp2_y;

    // Verify points are on curve and in subgroup
    if (!c.blst_p1_affine_on_curve(&p1_affine) or
        !c.blst_p1_affine_in_g1(&p1_affine))
    {
        return error.InvalidG1Point;
    }

    if (!c.blst_p1_affine_on_curve(&p2_affine) or
        !c.blst_p1_affine_in_g1(&p2_affine))
    {
        return error.InvalidG1Point;
    }

    // Convert to projective form for addition
    var p1: c.blst_p1 = undefined;
    var p2: c.blst_p1 = undefined;
    c.blst_p1_from_affine(&p1, &p1_affine);
    c.blst_p1_from_affine(&p2, &p2_affine);

    // Add points
    var result: c.blst_p1 = undefined;
    c.blst_p1_add_or_double_affine(&result, &p1, &p2_affine);

    // Convert back to affine form
    var result_affine: c.blst_p1_affine = undefined;
    c.blst_p1_to_affine(&result_affine, &result);

    // Serialize result to bytes (big-endian)
    var output: [96]u8 = undefined;
    c.blst_bendian_from_fp(output[0..48], &result_affine.x);
    c.blst_bendian_from_fp(output[48..96], &result_affine.y);

    return output;
}

/// BLS12-381 G1 multi-scalar multiplication
/// Input: array of (point, scalar) pairs
/// Output: 96-byte unpadded G1 point
pub fn g1Msm(pairs: []const struct { point: [96]u8, scalar: [32]u8 }) ![96]u8 {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    if (pairs.len == 0) {
        return error.InvalidInput;
    }

    // Parse points and scalars
    var points: []c.blst_p1_affine = try std.heap.c_allocator.alloc(c.blst_p1_affine, pairs.len);
    defer std.heap.c_allocator.free(points);

    var scalars: []c.blst_scalar = try std.heap.c_allocator.alloc(c.blst_scalar, pairs.len);
    defer std.heap.c_allocator.free(scalars);

    // Allocate arrays of pointers for blst API
    var point_ptrs: []*const c.blst_p1_affine = try std.heap.c_allocator.alloc(*const c.blst_p1_affine, pairs.len);
    defer std.heap.c_allocator.free(point_ptrs);

    var scalar_ptrs: []*const u8 = try std.heap.c_allocator.alloc(*const u8, pairs.len);
    defer std.heap.c_allocator.free(scalar_ptrs);

    for (pairs, 0..) |pair, i| {
        // Parse point
        var fp_x: c.blst_fp = undefined;
        var fp_y: c.blst_fp = undefined;
        c.blst_fp_from_bendian(&fp_x, &pair.point[0..48].*);
        c.blst_fp_from_bendian(&fp_y, &pair.point[48..96].*);

        points[i].x = fp_x;
        points[i].y = fp_y;

        // Verify point
        if (!c.blst_p1_affine_on_curve(&points[i]) or
            !c.blst_p1_affine_in_g1(&points[i]))
        {
            return error.InvalidG1Point;
        }

        // Parse scalar (32 bytes big-endian)
        c.blst_scalar_from_bendian(&scalars[i], &pair.scalar);

        // Set up pointers
        point_ptrs[i] = &points[i];
        scalar_ptrs[i] = @ptrCast(@as(*const u8, @ptrCast(&scalars[i])));
    }

    // Allocate scratch space for MSM (aligned to 8 bytes for limb_t)
    const scratch_size = c.blst_p1s_mult_pippenger_scratch_sizeof(pairs.len);
    const scratch_bytes = try std.heap.page_allocator.alloc(u8, scratch_size + 7);
    defer std.heap.page_allocator.free(scratch_bytes);
    const scratch_aligned = @as([*]align(8) u8, @ptrCast(@alignCast(scratch_bytes.ptr)))[0..scratch_size];

    // Perform MSM
    var result: c.blst_p1 = undefined;
    c.blst_p1s_mult_pippenger(&result, point_ptrs.ptr, @intCast(pairs.len), scalar_ptrs.ptr, 256, @ptrCast(scratch_aligned.ptr));

    // Convert to affine and serialize
    var result_affine: c.blst_p1_affine = undefined;
    c.blst_p1_to_affine(&result_affine, &result);

    var output: [96]u8 = undefined;
    c.blst_bendian_from_fp(output[0..48], &result_affine.x);
    c.blst_bendian_from_fp(output[48..96], &result_affine.y);

    return output;
}

/// BLS12-381 G2 point addition
/// Input: two 192-byte unpadded G2 points
/// Output: 192-byte unpadded G2 point
pub fn g2Add(a: [192]u8, b: [192]u8) ![192]u8 {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    // Parse G2 points
    // G2 points are (x0 || x1 || y0 || y1) where each is 48 bytes
    var p1_affine: c.blst_p2_affine = undefined;
    var p2_affine: c.blst_p2_affine = undefined;

    // Parse first point
    var fp1_x0: c.blst_fp = undefined;
    var fp1_x1: c.blst_fp = undefined;
    var fp1_y0: c.blst_fp = undefined;
    var fp1_y1: c.blst_fp = undefined;

    c.blst_fp_from_bendian(&fp1_x0, &a[0..48].*);
    c.blst_fp_from_bendian(&fp1_x1, &a[48..96].*);
    c.blst_fp_from_bendian(&fp1_y0, &a[96..144].*);
    c.blst_fp_from_bendian(&fp1_y1, &a[144..192].*);

    p1_affine.x.fp[0] = fp1_x0;
    p1_affine.x.fp[1] = fp1_x1;
    p1_affine.y.fp[0] = fp1_y0;
    p1_affine.y.fp[1] = fp1_y1;

    // Parse second point
    var fp2_x0: c.blst_fp = undefined;
    var fp2_x1: c.blst_fp = undefined;
    var fp2_y0: c.blst_fp = undefined;
    var fp2_y1: c.blst_fp = undefined;

    c.blst_fp_from_bendian(&fp2_x0, &b[0..48].*);
    c.blst_fp_from_bendian(&fp2_x1, &b[48..96].*);
    c.blst_fp_from_bendian(&fp2_y0, &b[96..144].*);
    c.blst_fp_from_bendian(&fp2_y1, &b[144..192].*);

    p2_affine.x.fp[0] = fp2_x0;
    p2_affine.x.fp[1] = fp2_x1;
    p2_affine.y.fp[0] = fp2_y0;
    p2_affine.y.fp[1] = fp2_y1;

    // Verify points
    if (!c.blst_p2_affine_on_curve(&p1_affine) or
        !c.blst_p2_affine_in_g2(&p1_affine))
    {
        return error.InvalidG2Point;
    }

    if (!c.blst_p2_affine_on_curve(&p2_affine) or
        !c.blst_p2_affine_in_g2(&p2_affine))
    {
        return error.InvalidG2Point;
    }

    // Convert to projective and add
    var p1: c.blst_p2 = undefined;
    var p2: c.blst_p2 = undefined;
    c.blst_p2_from_affine(&p1, &p1_affine);
    c.blst_p2_from_affine(&p2, &p2_affine);

    var result: c.blst_p2 = undefined;
    c.blst_p2_add_or_double_affine(&result, &p1, &p2_affine);

    // Convert back to affine and serialize
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
pub fn g2Msm(pairs: []const struct { point: [192]u8, scalar: [32]u8 }) ![192]u8 {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    if (pairs.len == 0) {
        return error.InvalidInput;
    }

    // Parse points and scalars
    var points: []c.blst_p2_affine = try std.heap.c_allocator.alloc(c.blst_p2_affine, pairs.len);
    defer std.heap.c_allocator.free(points);

    var scalars: []c.blst_scalar = try std.heap.c_allocator.alloc(c.blst_scalar, pairs.len);
    defer std.heap.c_allocator.free(scalars);

    // Allocate arrays of pointers for blst API
    var point_ptrs: []*const c.blst_p2_affine = try std.heap.c_allocator.alloc(*const c.blst_p2_affine, pairs.len);
    defer std.heap.c_allocator.free(point_ptrs);

    var scalar_ptrs: []*const u8 = try std.heap.c_allocator.alloc(*const u8, pairs.len);
    defer std.heap.c_allocator.free(scalar_ptrs);

    for (pairs, 0..) |pair, i| {
        // Parse G2 point
        var fp_x0: c.blst_fp = undefined;
        var fp_x1: c.blst_fp = undefined;
        var fp_y0: c.blst_fp = undefined;
        var fp_y1: c.blst_fp = undefined;

        c.blst_fp_from_bendian(&fp_x0, &pair.point[0..48].*);
        c.blst_fp_from_bendian(&fp_x1, &pair.point[48..96].*);
        c.blst_fp_from_bendian(&fp_y0, &pair.point[96..144].*);
        c.blst_fp_from_bendian(&fp_y1, &pair.point[144..192].*);

        points[i].x.fp[0] = fp_x0;
        points[i].x.fp[1] = fp_x1;
        points[i].y.fp[0] = fp_y0;
        points[i].y.fp[1] = fp_y1;

        // Verify point
        if (!c.blst_p2_affine_on_curve(&points[i]) or
            !c.blst_p2_affine_in_g2(&points[i]))
        {
            return error.InvalidG2Point;
        }

        // Parse scalar
        c.blst_scalar_from_bendian(&scalars[i], &pair.scalar);

        // Set up pointers
        point_ptrs[i] = &points[i];
        scalar_ptrs[i] = @ptrCast(@as(*const u8, @ptrCast(&scalars[i])));
    }

    // Allocate scratch space for MSM (aligned to 8 bytes for limb_t)
    const scratch_size = c.blst_p2s_mult_pippenger_scratch_sizeof(pairs.len);
    const scratch_bytes = try std.heap.page_allocator.alloc(u8, scratch_size + 7);
    defer std.heap.page_allocator.free(scratch_bytes);
    const scratch_aligned = @as([*]align(8) u8, @ptrCast(@alignCast(scratch_bytes.ptr)))[0..scratch_size];

    // Perform MSM
    var result: c.blst_p2 = undefined;
    c.blst_p2s_mult_pippenger(&result, point_ptrs.ptr, @intCast(pairs.len), scalar_ptrs.ptr, 256, @ptrCast(scratch_aligned.ptr));

    // Convert to affine and serialize
    var result_affine: c.blst_p2_affine = undefined;
    c.blst_p2_to_affine(&result_affine, &result);

    var output: [192]u8 = undefined;
    c.blst_bendian_from_fp(output[0..48], &result_affine.x.fp[0]);
    c.blst_bendian_from_fp(output[48..96], &result_affine.x.fp[1]);
    c.blst_bendian_from_fp(output[96..144], &result_affine.y.fp[0]);
    c.blst_bendian_from_fp(output[144..192], &result_affine.y.fp[1]);

    return output;
}

/// BLS12-381 pairing check
/// Input: array of (G1, G2) point pairs
/// Returns true if pairing is valid
pub fn pairingCheck(pairs: []const struct { g1: [96]u8, g2: [192]u8 }) !bool {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
    }

    if (pairs.len == 0) {
        return true; // Empty pairing is valid
    }

    // Parse all pairs
    var g1_points: []c.blst_p1_affine = try std.heap.c_allocator.alloc(c.blst_p1_affine, pairs.len);
    defer std.heap.c_allocator.free(g1_points);

    var g2_points: []c.blst_p2_affine = try std.heap.c_allocator.alloc(c.blst_p2_affine, pairs.len);
    defer std.heap.c_allocator.free(g2_points);

    for (pairs, 0..) |pair, i| {
        // Parse G1 point
        var fp_x: c.blst_fp = undefined;
        var fp_y: c.blst_fp = undefined;
        c.blst_fp_from_bendian(&fp_x, &pair.g1[0..48].*);
        c.blst_fp_from_bendian(&fp_y, &pair.g1[48..96].*);

        g1_points[i].x = fp_x;
        g1_points[i].y = fp_y;

        if (!c.blst_p1_affine_on_curve(&g1_points[i]) or
            !c.blst_p1_affine_in_g1(&g1_points[i]))
        {
            return error.InvalidG1Point;
        }

        // Parse G2 point
        var fp2_x0: c.blst_fp = undefined;
        var fp2_x1: c.blst_fp = undefined;
        var fp2_y0: c.blst_fp = undefined;
        var fp2_y1: c.blst_fp = undefined;

        c.blst_fp_from_bendian(&fp2_x0, &pair.g2[0..48].*);
        c.blst_fp_from_bendian(&fp2_x1, &pair.g2[48..96].*);
        c.blst_fp_from_bendian(&fp2_y0, &pair.g2[96..144].*);
        c.blst_fp_from_bendian(&fp2_y1, &pair.g2[144..192].*);

        g2_points[i].x.fp[0] = fp2_x0;
        g2_points[i].x.fp[1] = fp2_x1;
        g2_points[i].y.fp[0] = fp2_y0;
        g2_points[i].y.fp[1] = fp2_y1;

        if (!c.blst_p2_affine_on_curve(&g2_points[i]) or
            !c.blst_p2_affine_in_g2(&g2_points[i]))
        {
            return error.InvalidG2Point;
        }
    }

    // Compute pairing product
    var fp12: c.blst_fp12 = undefined;
    c.blst_miller_loop(&fp12, &g2_points[0], &g1_points[0]);

    // Multiply remaining pairs
    for (1..pairs.len) |i| {
        var temp: c.blst_fp12 = undefined;
        c.blst_miller_loop(&temp, &g2_points[i], &g1_points[i]);
        c.blst_fp12_mul(&fp12, &fp12, &temp);
    }

    // Final exponentiation
    var result: c.blst_fp12 = undefined;
    c.blst_final_exp(&result, &fp12);

    // Check if result is identity (pairing is valid if result == 1)
    return c.blst_fp12_is_one(&result);
}

/// BLS12-381 map field element to G1
/// Input: 48-byte field element
/// Output: 96-byte unpadded G1 point
pub fn mapFpToG1(fp: [48]u8) ![96]u8 {
    if (!isAvailable()) {
        return error.BlstNotAvailable;
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

    // Parse Fp2 element (two 48-byte field elements)
    var fp2_elem: c.blst_fp2 = undefined;
    c.blst_fp_from_bendian(&fp2_elem.fp[0], &fp2[0..48].*);
    c.blst_fp_from_bendian(&fp2_elem.fp[1], &fp2[48..96].*);

    // Map to G2
    var result: c.blst_p2 = undefined;
    c.blst_map_to_g2(&result, &fp2_elem, null);

    // Convert to affine and serialize
    var result_affine: c.blst_p2_affine = undefined;
    c.blst_p2_to_affine(&result_affine, &result);

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
};
