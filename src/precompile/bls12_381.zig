const std = @import("std");
const primitives = @import("primitives");
const main = @import("main.zig");
const blst_wrapper = @import("blst_wrapper.zig");

/// BLS12-381 elliptic curve precompiles
pub const g1_add = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12G1Add,
        main.u64ToAddress(0x0B),
        bls12G1AddRun,
    );
};

pub const g1_msm = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12G1Msm,
        main.u64ToAddress(0x0C),
        bls12G1MsmRun,
    );
};

pub const g2_add = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12G2Add,
        main.u64ToAddress(0x0D),
        bls12G2AddRun,
    );
};

pub const g2_msm = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12G2Msm,
        main.u64ToAddress(0x0E),
        bls12G2MsmRun,
    );
};

pub const pairing = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12Pairing,
        main.u64ToAddress(0x0F),
        bls12PairingRun,
    );
};

pub const map_fp_to_g1 = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12MapFpToGp1,
        main.u64ToAddress(0x10),
        bls12MapFpToG1Run,
    );
};

pub const map_fp2_to_g2 = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12MapFp2ToGp2,
        main.u64ToAddress(0x11),
        bls12MapFp2ToG2Run,
    );
};

// Constants
const FP_LENGTH: usize = 48;
const PADDED_FP_LENGTH: usize = 64;
const G1_LENGTH: usize = 2 * FP_LENGTH; // 96 bytes (unpadded)
const PADDED_G1_LENGTH: usize = 2 * PADDED_FP_LENGTH; // 128 bytes (padded)
const FP2_LENGTH: usize = 2 * FP_LENGTH; // 96 bytes
const PADDED_FP2_LENGTH: usize = 2 * PADDED_FP_LENGTH; // 128 bytes
const G2_LENGTH: usize = 2 * FP2_LENGTH; // 192 bytes (unpadded)
const PADDED_G2_LENGTH: usize = 2 * PADDED_FP2_LENGTH; // 256 bytes (padded)
const SCALAR_LENGTH: usize = 32;

// Pair types for MSM and pairing operations
const G1PointScalarPair = struct { point: [G1_LENGTH]u8, scalar: [32]u8 };
const G2PointScalarPair = struct { point: [G2_LENGTH]u8, scalar: [32]u8 };
const G1G2Pair = struct { g1: [G1_LENGTH]u8, g2: [G2_LENGTH]u8 };

// Gas costs
const G1_ADD_BASE_GAS_FEE: u64 = 375;
const G1_MSM_BASE_GAS_FEE: u64 = 12000;
const G2_ADD_BASE_GAS_FEE: u64 = 600;
const G2_MSM_BASE_GAS_FEE: u64 = 22500;
const MAP_FP_TO_G1_BASE_GAS_FEE: u64 = 5500;
const MAP_FP2_TO_G2_BASE_GAS_FEE: u64 = 23800;
const PAIRING_OFFSET_BASE: u64 = 37700;
const PAIRING_MULTIPLIER_BASE: u64 = 32600;
const MSM_MULTIPLIER: u64 = 1000;

// Discount tables for MSM
const DISCOUNT_TABLE_G1_MSM: [128]u16 = .{
    1000, 949, 848, 797, 764, 750, 738, 728, 719, 712, 705, 698, 692, 687, 682, 677, 673, 669, 665,
    661,  658, 654, 651, 648, 645, 642, 640, 637, 635, 632, 630, 627, 625, 623, 621, 619, 617, 615,
    613,  611, 609, 608, 606, 604, 603, 601, 599, 598, 596, 595, 593, 592, 591, 589, 588, 586, 585,
    584,  582, 581, 580, 579, 577, 576, 575, 574, 573, 572, 570, 569, 568, 567, 566, 565, 564, 563,
    562,  561, 560, 559, 558, 557, 556, 555, 554, 553, 552, 551, 550, 549, 548, 547, 547, 546, 545,
    544,  543, 542, 541, 540, 540, 539, 538, 537, 536, 536, 535, 534, 533, 532, 532, 531, 530, 529,
    528,  528, 527, 526, 525, 525, 524, 523, 522, 522, 521, 520, 520, 519,
};

const DISCOUNT_TABLE_G2_MSM: [128]u16 = .{
    1000, 1000, 923, 884, 855, 832, 812, 796, 782, 770, 759, 749, 740, 732, 724, 717, 711, 704,
    699,  693,  688, 683, 679, 674, 670, 666, 663, 659, 655, 652, 649, 646, 643, 640, 637, 634,
    632,  629,  627, 624, 622, 620, 618, 615, 613, 611, 609, 607, 606, 604, 602, 600, 598, 597,
    595,  593,  592, 590, 589, 587, 586, 584, 583, 582, 580, 579, 578, 576, 575, 574, 573, 571,
    570,  569,  568, 567, 566, 565, 563, 562, 561, 560, 559, 558, 557, 556, 555, 554, 553, 552,
    552,  551,  550, 549, 548, 547, 546, 545, 545, 544, 543, 542, 541, 541, 540, 539, 538, 537,
    537,  536,  535, 535, 534, 533, 532, 532, 531, 530, 530, 529, 528, 528, 527, 526, 526, 525,
    524,  524,
};

/// Remove padding from G1 point (128 bytes -> 96 bytes).
/// EIP-2537: the top 16 bytes of each 64-byte element must be zero.
fn removeG1Padding(padded: []const u8) ![2][FP_LENGTH]u8 {
    if (padded.len < PADDED_G1_LENGTH) {
        return main.PrecompileError.Bls12381G1AddInputLength;
    }
    const zero16 = [_]u8{0} ** 16;
    if (!std.mem.eql(u8, padded[0..16], &zero16) or !std.mem.eql(u8, padded[64..80], &zero16)) {
        return main.PrecompileError.Bls12381G1AddInputLength;
    }
    var result: [2][FP_LENGTH]u8 = undefined;
    @memcpy(&result[0], padded[16 .. 16 + FP_LENGTH]);
    @memcpy(&result[1], padded[80 .. 80 + FP_LENGTH]);
    return result;
}

/// Pad G1 point (96 bytes -> 128 bytes)
fn padG1Point(unpadded: []const u8) [PADDED_G1_LENGTH]u8 {
    var result: [PADDED_G1_LENGTH]u8 = [_]u8{0} ** PADDED_G1_LENGTH;
    @memcpy(result[16 .. 16 + FP_LENGTH], unpadded[0..FP_LENGTH]);
    @memcpy(result[80 .. 80 + FP_LENGTH], unpadded[FP_LENGTH..]);
    return result;
}

/// Remove padding from G2 point (256 bytes -> 192 bytes).
/// EIP-2537: the top 16 bytes of each 64-byte element must be zero.
fn removeG2Padding(padded: []const u8) ![4][FP_LENGTH]u8 {
    if (padded.len < PADDED_G2_LENGTH) {
        return main.PrecompileError.Bls12381G2AddInputLength;
    }
    const zero16 = [_]u8{0} ** 16;
    if (!std.mem.eql(u8, padded[0..16], &zero16) or !std.mem.eql(u8, padded[64..80], &zero16) or
        !std.mem.eql(u8, padded[128..144], &zero16) or !std.mem.eql(u8, padded[192..208], &zero16))
    {
        return main.PrecompileError.Bls12381G2AddInputLength;
    }
    var result: [4][FP_LENGTH]u8 = undefined;
    @memcpy(&result[0], padded[16 .. 16 + FP_LENGTH]);
    @memcpy(&result[1], padded[80 .. 80 + FP_LENGTH]);
    @memcpy(&result[2], padded[144 .. 144 + FP_LENGTH]);
    @memcpy(&result[3], padded[208 .. 208 + FP_LENGTH]);
    return result;
}

/// Pad G2 point (192 bytes -> 256 bytes)
fn padG2Point(unpadded: []const u8) [PADDED_G2_LENGTH]u8 {
    var result: [PADDED_G2_LENGTH]u8 = [_]u8{0} ** PADDED_G2_LENGTH;
    @memcpy(result[16 .. 16 + FP_LENGTH], unpadded[0..FP_LENGTH]);
    @memcpy(result[80 .. 80 + FP_LENGTH], unpadded[FP_LENGTH..][0..FP_LENGTH]);
    @memcpy(result[144 .. 144 + FP_LENGTH], unpadded[FP2_LENGTH..][0..FP_LENGTH]);
    @memcpy(result[208 .. 208 + FP_LENGTH], unpadded[FP2_LENGTH + FP_LENGTH ..][0..FP_LENGTH]);
    return result;
}

/// BLS12-381 G1 point addition
pub fn bls12G1AddRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (G1_ADD_BASE_GAS_FEE > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    if (input.len != PADDED_G1_LENGTH * 2) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G1AddInputLength };
    }

    const a_coords = removeG1Padding(input[0..PADDED_G1_LENGTH]) catch |e| return main.PrecompileResult{ .err = e };
    const b_coords = removeG1Padding(input[PADDED_G1_LENGTH..]) catch |e| return main.PrecompileResult{ .err = e };

    // Convert to unpadded format for blst
    // a_coords and b_coords are [2][48]u8, we need to flatten to [96]u8
    var a_unpadded: [G1_LENGTH]u8 = undefined;
    @memcpy(a_unpadded[0..48], &a_coords[0]);
    @memcpy(a_unpadded[48..96], &a_coords[1]);
    var b_unpadded: [G1_LENGTH]u8 = undefined;
    @memcpy(b_unpadded[0..48], &b_coords[0]);
    @memcpy(b_unpadded[48..96], &b_coords[1]);

    var unpadded_result: [G1_LENGTH]u8 = undefined;
    if (blst_wrapper.isAvailable()) {
        if (blst_wrapper.g1Add(a_unpadded, b_unpadded)) |result| {
            unpadded_result = result;
        } else |_| {
            return main.PrecompileResult{ .err = error.Bls12381G1NotOnCurve };
        }
    } else {
        return main.PrecompileResult{ .err = error.Bls12381G1NotOnCurve };
    }

    const padded_result = padG1Point(&unpadded_result);
    const heap_out = std.heap.c_allocator.dupe(u8, &padded_result) catch
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(G1_ADD_BASE_GAS_FEE, heap_out) };
}

/// BLS12-381 G1 multi-scalar multiplication
pub fn bls12G1MsmRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    // EIP-2537: G1MSM pair = 128-byte padded G1 point + 32-byte scalar = 160 bytes
    const PAIR_LENGTH = PADDED_G1_LENGTH + SCALAR_LENGTH; // 160
    if (input.len < PAIR_LENGTH) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G1MsmInputLength };
    }

    const k = input.len / PAIR_LENGTH;
    if (k == 0) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G1MsmInputLength };
    }

    const discount = if (k <= DISCOUNT_TABLE_G1_MSM.len) DISCOUNT_TABLE_G1_MSM[k - 1] else DISCOUNT_TABLE_G1_MSM[DISCOUNT_TABLE_G1_MSM.len - 1];
    const gas_used = (@as(u64, k) * G1_MSM_BASE_GAS_FEE * @as(u64, discount)) / MSM_MULTIPLIER;
    if (gas_used > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // Parse point-scalar pairs
    var pairs = std.ArrayListUnmanaged(G1PointScalarPair){};
    defer pairs.deinit(std.heap.c_allocator);
    pairs.ensureTotalCapacity(std.heap.c_allocator, k) catch {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    };

    var i: usize = 0;
    while (i < input.len) : (i += PAIR_LENGTH) {
        if (i + PAIR_LENGTH > input.len) {
            return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G1MsmInputLength };
        }
        const point_padded = input[i..][0..PADDED_G1_LENGTH];
        const scalar_raw = input[i + PADDED_G1_LENGTH ..][0..SCALAR_LENGTH];

        // Remove padding from point (128 bytes -> 96 bytes)
        const point_coords = removeG1Padding(point_padded) catch {
            return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G1MsmInputLength };
        };

        // Flatten point coords to [96]u8
        var point: [G1_LENGTH]u8 = undefined;
        @memcpy(point[0..48], &point_coords[0]);
        @memcpy(point[48..96], &point_coords[1]);

        // Scalar is 32 bytes, no padding
        var scalar: [32]u8 = undefined;
        @memcpy(&scalar, scalar_raw);

        pairs.append(std.heap.c_allocator, .{ .point = point, .scalar = scalar }) catch {
            return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
        };
    }

    // Perform MSM using blst wrapper
    var unpadded_result: [G1_LENGTH]u8 = undefined;
    if (blst_wrapper.isAvailable()) {
        // Convert pairs to format expected by blst_wrapper
        const blst_pairs = std.heap.c_allocator.alloc(struct { point: [96]u8, scalar: [32]u8 }, pairs.items.len) catch {
            return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
        };
        defer std.heap.c_allocator.free(blst_pairs);
        for (pairs.items, 0..) |pair_item, idx| {
            blst_pairs[idx].point = pair_item.point;
            blst_pairs[idx].scalar = pair_item.scalar;
        }

        if (blst_wrapper.g1Msm(@ptrCast(blst_pairs))) |result| {
            unpadded_result = result;
        } else |_| {
            return main.PrecompileResult{ .err = error.Bls12381G1NotOnCurve };
        }
    } else {
        return main.PrecompileResult{ .err = error.Bls12381G1NotOnCurve };
    }

    const padded_result = padG1Point(&unpadded_result);
    const heap_out = std.heap.c_allocator.dupe(u8, &padded_result) catch
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_used, heap_out) };
}

/// BLS12-381 G2 point addition
pub fn bls12G2AddRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (G2_ADD_BASE_GAS_FEE > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    if (input.len != PADDED_G2_LENGTH * 2) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G2AddInputLength };
    }

    const a_coords = removeG2Padding(input[0..PADDED_G2_LENGTH]) catch |e| return main.PrecompileResult{ .err = e };
    const b_coords = removeG2Padding(input[PADDED_G2_LENGTH..]) catch |e| return main.PrecompileResult{ .err = e };

    // Flatten coords to [192]u8 format
    var a_unpadded: [G2_LENGTH]u8 = undefined;
    @memcpy(a_unpadded[0..48], &a_coords[0]);
    @memcpy(a_unpadded[48..96], &a_coords[1]);
    @memcpy(a_unpadded[96..144], &a_coords[2]);
    @memcpy(a_unpadded[144..192], &a_coords[3]);

    var b_unpadded: [G2_LENGTH]u8 = undefined;
    @memcpy(b_unpadded[0..48], &b_coords[0]);
    @memcpy(b_unpadded[48..96], &b_coords[1]);
    @memcpy(b_unpadded[96..144], &b_coords[2]);
    @memcpy(b_unpadded[144..192], &b_coords[3]);

    var unpadded_result: [G2_LENGTH]u8 = undefined;
    if (blst_wrapper.isAvailable()) {
        if (blst_wrapper.g2Add(a_unpadded, b_unpadded)) |result| {
            unpadded_result = result;
        } else |_| {
            return main.PrecompileResult{ .err = error.Bls12381G2NotOnCurve };
        }
    } else {
        return main.PrecompileResult{ .err = error.Bls12381G2NotOnCurve };
    }

    const padded_result = padG2Point(&unpadded_result);
    const heap_out = std.heap.c_allocator.dupe(u8, &padded_result) catch
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(G2_ADD_BASE_GAS_FEE, heap_out) };
}

/// BLS12-381 G2 multi-scalar multiplication
pub fn bls12G2MsmRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    // EIP-2537: G2MSM pair = 256-byte padded G2 point + 32-byte scalar = 288 bytes
    const PAIR_LENGTH = PADDED_G2_LENGTH + SCALAR_LENGTH; // 288
    if (input.len < PAIR_LENGTH) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G2MsmInputLength };
    }

    const k = input.len / PAIR_LENGTH;
    if (k == 0) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G2MsmInputLength };
    }

    const discount = if (k <= DISCOUNT_TABLE_G2_MSM.len) DISCOUNT_TABLE_G2_MSM[k - 1] else DISCOUNT_TABLE_G2_MSM[DISCOUNT_TABLE_G2_MSM.len - 1];
    const gas_used = (@as(u64, k) * G2_MSM_BASE_GAS_FEE * @as(u64, discount)) / MSM_MULTIPLIER;
    if (gas_used > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // Parse point-scalar pairs
    var pairs = std.ArrayListUnmanaged(G2PointScalarPair){};
    defer pairs.deinit(std.heap.c_allocator);
    pairs.ensureTotalCapacity(std.heap.c_allocator, k) catch {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    };

    var i: usize = 0;
    while (i < input.len) : (i += PAIR_LENGTH) {
        if (i + PAIR_LENGTH > input.len) {
            return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G2MsmInputLength };
        }
        const point_padded = input[i..][0..PADDED_G2_LENGTH];
        const scalar_raw = input[i + PADDED_G2_LENGTH ..][0..SCALAR_LENGTH];

        // Remove padding from point (256 bytes -> 192 bytes)
        const point_coords = removeG2Padding(point_padded) catch {
            return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G2MsmInputLength };
        };

        // Flatten point coords to [192]u8
        var point: [G2_LENGTH]u8 = undefined;
        @memcpy(point[0..48], &point_coords[0]);
        @memcpy(point[48..96], &point_coords[1]);
        @memcpy(point[96..144], &point_coords[2]);
        @memcpy(point[144..192], &point_coords[3]);

        // Scalar is 32 bytes, no padding
        var scalar: [32]u8 = undefined;
        @memcpy(&scalar, scalar_raw);

        pairs.append(std.heap.c_allocator, .{ .point = point, .scalar = scalar }) catch {
            return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
        };
    }

    // Perform MSM using blst wrapper
    var unpadded_result: [G2_LENGTH]u8 = undefined;
    if (blst_wrapper.isAvailable()) {
        // Convert pairs to format expected by blst_wrapper
        const blst_pairs = std.heap.c_allocator.alloc(struct { point: [192]u8, scalar: [32]u8 }, pairs.items.len) catch {
            return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
        };
        defer std.heap.c_allocator.free(blst_pairs);
        for (pairs.items, 0..) |pair_item, idx| {
            blst_pairs[idx].point = pair_item.point;
            blst_pairs[idx].scalar = pair_item.scalar;
        }

        if (blst_wrapper.g2Msm(@ptrCast(blst_pairs))) |result| {
            unpadded_result = result;
        } else |_| {
            return main.PrecompileResult{ .err = error.Bls12381G2NotOnCurve };
        }
    } else {
        return main.PrecompileResult{ .err = error.Bls12381G2NotOnCurve };
    }

    const padded_result = padG2Point(&unpadded_result);
    const heap_out = std.heap.c_allocator.dupe(u8, &padded_result) catch
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_used, heap_out) };
}

/// BLS12-381 pairing check
pub fn bls12PairingRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (input.len < PADDED_G1_LENGTH + PADDED_G2_LENGTH) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381PairingInputLength };
    }

    const pair_len = PADDED_G1_LENGTH + PADDED_G2_LENGTH;
    if (input.len % pair_len != 0) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381PairingInputLength };
    }

    const num_pairs = input.len / pair_len;
    const gas_used = @as(u64, num_pairs) * PAIRING_MULTIPLIER_BASE + PAIRING_OFFSET_BASE;
    if (gas_used > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // Parse pairs
    var pairs = std.ArrayListUnmanaged(G1G2Pair){};
    defer pairs.deinit(std.heap.c_allocator);
    pairs.ensureTotalCapacity(std.heap.c_allocator, num_pairs) catch {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    };

    var i: usize = 0;
    while (i < input.len) : (i += pair_len) {
        const g1_padded = input[i..][0..PADDED_G1_LENGTH];
        const g2_padded = input[i + PADDED_G1_LENGTH ..][0..PADDED_G2_LENGTH];

        // Remove padding from G1 point
        const g1_coords = removeG1Padding(g1_padded) catch {
            return main.PrecompileResult{ .err = main.PrecompileError.Bls12381PairingInputLength };
        };
        var g1: [G1_LENGTH]u8 = undefined;
        @memcpy(g1[0..48], &g1_coords[0]);
        @memcpy(g1[48..96], &g1_coords[1]);

        // Remove padding from G2 point
        const g2_coords = removeG2Padding(g2_padded) catch {
            return main.PrecompileResult{ .err = main.PrecompileError.Bls12381PairingInputLength };
        };
        var g2: [G2_LENGTH]u8 = undefined;
        @memcpy(g2[0..48], &g2_coords[0]);
        @memcpy(g2[48..96], &g2_coords[1]);
        @memcpy(g2[96..144], &g2_coords[2]);
        @memcpy(g2[144..192], &g2_coords[3]);

        pairs.append(std.heap.c_allocator, .{ .g1 = g1, .g2 = g2 }) catch {
            return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
        };
    }

    // Perform pairing check using blst wrapper
    var pairing_valid = false;
    if (blst_wrapper.isAvailable()) {
        // Convert pairs to format expected by blst_wrapper
        const blst_pairs = std.heap.c_allocator.alloc(struct { g1: [96]u8, g2: [192]u8 }, pairs.items.len) catch {
            return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
        };
        defer std.heap.c_allocator.free(blst_pairs);
        for (pairs.items, 0..) |pair_item, idx| {
            blst_pairs[idx].g1 = pair_item.g1;
            blst_pairs[idx].g2 = pair_item.g2;
        }

        if (blst_wrapper.pairingCheck(@ptrCast(blst_pairs))) |result| {
            pairing_valid = result;
        } else |_| {
            return main.PrecompileResult{ .err = error.Bls12381G1NotOnCurve };
        }
    } else {
        return main.PrecompileResult{ .err = error.Bls12381G1NotOnCurve };
    }

    // Result is 1 if pairing is valid, 0 otherwise
    var output: [32]u8 = [_]u8{0} ** 32;
    if (pairing_valid) {
        output[31] = 1;
    }

    const heap_out = std.heap.c_allocator.dupe(u8, &output) catch
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_used, heap_out) };
}

/// BLS12-381 map field element to G1
pub fn bls12MapFpToG1Run(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (MAP_FP_TO_G1_BASE_GAS_FEE > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    if (input.len != PADDED_FP_LENGTH) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381MapFpToG1InputLength };
    }

    // EIP-2537: top 16 bytes must be zero
    const zero16 = [_]u8{0} ** 16;
    if (!std.mem.eql(u8, input[0..16], &zero16)) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381MapFpToG1InputLength };
    }

    // Extract field element (skip 16-byte padding, take 48 bytes)
    var fp: [FP_LENGTH]u8 = undefined;
    @memcpy(&fp, input[16..64]);

    // Map to G1 using blst wrapper
    var unpadded_result: [G1_LENGTH]u8 = undefined;
    if (blst_wrapper.isAvailable()) {
        if (blst_wrapper.mapFpToG1(fp)) |result| {
            unpadded_result = result;
        } else |_| {
            return main.PrecompileResult{ .err = error.Bls12381G1NotOnCurve };
        }
    } else {
        return main.PrecompileResult{ .err = error.Bls12381G1NotOnCurve };
    }

    const padded_result = padG1Point(&unpadded_result);
    const heap_out = std.heap.c_allocator.dupe(u8, &padded_result) catch
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(MAP_FP_TO_G1_BASE_GAS_FEE, heap_out) };
}

/// BLS12-381 map field element to G2
pub fn bls12MapFp2ToG2Run(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (MAP_FP2_TO_G2_BASE_GAS_FEE > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    if (input.len != PADDED_FP2_LENGTH) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381MapFp2ToG2InputLength };
    }

    // EIP-2537: top 16 bytes of each 64-byte element must be zero
    const zero16 = [_]u8{0} ** 16;
    if (!std.mem.eql(u8, input[0..16], &zero16) or !std.mem.eql(u8, input[64..80], &zero16)) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381MapFp2ToG2InputLength };
    }

    // Extract Fp2 element (skip 16-byte padding from first element, take 96 bytes total)
    // Fp2 is two Fp elements: [padding(16) | fp0(48) | padding(16) | fp1(48)]
    var fp2: [FP2_LENGTH]u8 = undefined;
    @memcpy(fp2[0..48], input[16..64]); // First Fp element
    @memcpy(fp2[48..96], input[80..128]); // Second Fp element

    // Map to G2 using blst wrapper
    var unpadded_result: [G2_LENGTH]u8 = undefined;
    if (blst_wrapper.isAvailable()) {
        if (blst_wrapper.mapFp2ToG2(fp2)) |result| {
            unpadded_result = result;
        } else |_| {
            return main.PrecompileResult{ .err = error.Bls12381G2NotOnCurve };
        }
    } else {
        return main.PrecompileResult{ .err = error.Bls12381G2NotOnCurve };
    }

    const padded_result = padG2Point(&unpadded_result);
    const heap_out = std.heap.c_allocator.dupe(u8, &padded_result) catch
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(MAP_FP2_TO_G2_BASE_GAS_FEE, heap_out) };
}
