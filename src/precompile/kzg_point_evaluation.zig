const std = @import("std");
const primitives = @import("primitives");
const main = @import("main.zig");
const blst_wrapper = @import("blst_wrapper.zig");

/// KZG point evaluation precompile
pub const POINT_EVALUATION = main.Precompile.new(
    main.PrecompileId.KzgPointEvaluation,
    main.u64ToAddress(0x0A),
    kzgPointEvaluationRun,
);

/// Gas cost of the KZG point evaluation precompile
pub const GAS_COST: u64 = 50_000;

/// Versioned hash version for KZG
pub const VERSIONED_HASH_VERSION_KZG: u8 = 0x01;

/// BLS12-381 scalar field modulus (Fr order)
/// 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
pub const BLS_MODULUS: [32]u8 = .{
    0x73, 0xed, 0xa7, 0x53, 0x29, 0x9d, 0x7d, 0x48, 0x33, 0x39, 0xd8, 0x08, 0x09, 0xa1, 0xd8, 0x05,
    0x53, 0xbd, 0xa4, 0x02, 0xff, 0xfe, 0x5b, 0xfe, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x01,
};

/// Return value: FIELD_ELEMENTS_PER_BLOB (4096) and BLS_MODULUS
/// Format: U256(FIELD_ELEMENTS_PER_BLOB).to_be_bytes() ++ BLS_MODULUS.to_bytes32()
pub const RETURN_VALUE: [64]u8 = .{
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, // 4096
    0x73, 0xed, 0xa7, 0x53, 0x29, 0x9d, 0x7d, 0x48, 0x33, 0x39, 0xd8, 0x08, 0x09, 0xa1, 0xd8, 0x05,
    0x53, 0xbd, 0xa4, 0x02, 0xff, 0xfe, 0x5b, 0xfe, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x01, // BLS_MODULUS
};

/// KZG point evaluation
/// Input format:
/// | versioned_hash |  z  |  y  | commitment | proof |
/// |     32         | 32  | 32  |     48     |   48  |
/// Total: 192 bytes
pub fn kzgPointEvaluationRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (gas_limit < GAS_COST) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // Verify input length
    if (input.len != 192) {
        return main.PrecompileResult{ .err = main.PrecompileError.BlobInvalidInputLength };
    }

    // Parse input
    const versioned_hash = input[0..32];
    const z = input[32..64];
    const y = input[64..96];
    const commitment = input[96..144];
    const proof = input[144..192];

    // Validate z and y are valid BLS12-381 scalar field elements (must be < BLS_MODULUS).
    // Per EIP-4844, inputs with z >= BLS_MODULUS or y >= BLS_MODULUS must be rejected.
    if (std.mem.order(u8, z, &BLS_MODULUS) != .lt) {
        return main.PrecompileResult{ .err = main.PrecompileError.BlobVerifyKzgProofFailed };
    }
    if (std.mem.order(u8, y, &BLS_MODULUS) != .lt) {
        return main.PrecompileResult{ .err = main.PrecompileError.BlobVerifyKzgProofFailed };
    }

    // Verify commitment matches versioned_hash
    var computed_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(commitment, &computed_hash, .{});
    computed_hash[0] = VERSIONED_HASH_VERSION_KZG;

    if (!std.mem.eql(u8, versioned_hash, &computed_hash)) {
        return main.PrecompileResult{ .err = main.PrecompileError.BlobMismatchedVersion };
    }

    // Verify KZG proof
    const z_bytes: [32]u8 = z[0..32].*;
    const y_bytes: [32]u8 = y[0..32].*;
    const commitment_bytes: [48]u8 = commitment[0..48].*;
    const proof_bytes: [48]u8 = proof[0..48].*;

    const proof_valid = if (blst_wrapper.isAvailable())
        blst_wrapper.verifyKzgProof(commitment_bytes, z_bytes, y_bytes, proof_bytes) catch false
    else
        verifyKzgProof(commitment_bytes, z_bytes, y_bytes, proof_bytes);

    if (!proof_valid) {
        return main.PrecompileResult{ .err = main.PrecompileError.BlobVerifyKzgProofFailed };
    }

    // Return FIELD_ELEMENTS_PER_BLOB and BLS_MODULUS
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(GAS_COST, &RETURN_VALUE) };
}

/// Verify KZG proof
/// TODO: Replace with actual KZG proof verification using external library
/// This requires BLS12-381 pairing operations and trusted setup
fn verifyKzgProof(commitment: [48]u8, z: [32]u8, y: [32]u8, proof: [48]u8) bool {
    _ = commitment;
    _ = z;
    _ = y;
    _ = proof;
    // Placeholder: actual implementation would:
    // 1. Parse commitment as G1 point
    // 2. Parse proof as G1 point
    // 3. Parse z and y as field elements
    // 4. Verify: e(commitment - [y]G1, -G2) * e(proof, [τ]G2 - [z]G2) == 1
    // where [τ]G2 is from the trusted setup
    return false; // Placeholder: always return false for now
}
