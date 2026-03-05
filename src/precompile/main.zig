const std = @import("std");
const primitives = @import("primitives");

// Import precompile modules (needed for PrecompileId.precompile method)
pub const identity = @import("identity.zig");
pub const hash = @import("hash.zig");
pub const secp256k1 = @import("secp256k1.zig");
pub const secp256r1 = @import("secp256r1.zig");
pub const modexp = @import("modexp.zig");
pub const bn254 = @import("bn254.zig");
pub const blake2 = @import("blake2.zig");
pub const kzg_point_evaluation = @import("kzg_point_evaluation.zig");
pub const bls12_381 = @import("bls12_381.zig");

/// Precompile error type
pub const PrecompileError = error{
    OutOfGas,
    Blake2WrongLength,
    Blake2WrongFinalIndicatorFlag,
    ModexpExpOverflow,
    ModexpBaseOverflow,
    ModexpModOverflow,
    ModexpEip7823LimitSize,
    Bn254FieldPointNotAMember,
    Bn254AffineGFailedToCreate,
    Bn254PairLength,
    BlobInvalidInputLength,
    BlobMismatchedVersion,
    BlobVerifyKzgProofFailed,
    NonCanonicalFp,
    Bls12381G1NotOnCurve,
    Bls12381G1NotInSubgroup,
    Bls12381G2NotOnCurve,
    Bls12381G2NotInSubgroup,
    Bls12381ScalarInputLength,
    Bls12381G1AddInputLength,
    Bls12381G2AddInputLength,
    Bls12381G1MsmInputLength,
    Bls12381G2MsmInputLength,
    Bls12381PairingInputLength,
    Bls12381MapFpToG1InputLength,
    Bls12381MapFp2ToG2InputLength,
    Secp256k1RecoverFailed,
    P256VerifyFailed,
};

/// Precompile result type
pub const PrecompileResult = union(enum) {
    success: PrecompileOutput,
    err: PrecompileError,
};

/// Precompile execution output
pub const PrecompileOutput = struct {
    /// Gas used by the precompile
    gas_used: u64,
    /// Output bytes
    bytes: []const u8,
    /// Whether the precompile reverted
    reverted: bool,

    /// Create new precompile output
    pub fn new(gas_used: u64, bytes: []const u8) PrecompileOutput {
        return PrecompileOutput{
            .gas_used = gas_used,
            .bytes = bytes,
            .reverted = false,
        };
    }

    /// Create new precompile revert
    pub fn newReverted(gas_used: u64, bytes: []const u8) PrecompileOutput {
        return PrecompileOutput{
            .gas_used = gas_used,
            .bytes = bytes,
            .reverted = true,
        };
    }
};

/// Precompile function type
pub const PrecompileFn = *const fn (input: []const u8, gas_limit: u64) PrecompileResult;

/// Precompile identifier
pub const PrecompileId = union(enum) {
    /// Elliptic curve digital signature algorithm (ECDSA) public key recovery function.
    EcRec,
    /// SHA2-256 hash function.
    Sha256,
    /// RIPEMD-160 hash function.
    Ripemd160,
    /// Identity precompile.
    Identity,
    /// Arbitrary-precision exponentiation under modulo.
    ModExp,
    /// Point addition (ADD) on the elliptic curve 'alt_bn128'.
    Bn254Add,
    /// Scalar multiplication (MUL) on the elliptic curve 'alt_bn128'.
    Bn254Mul,
    /// Bilinear function on groups on the elliptic curve 'alt_bn128'.
    Bn254Pairing,
    /// Compression function F used in the BLAKE2 cryptographic hashing algorithm.
    Blake2F,
    /// Verify p(z) = y given commitment that corresponds to the polynomial p(x) and a KZG proof.
    KzgPointEvaluation,
    /// Point addition in G1 (curve over base prime field).
    Bls12G1Add,
    /// Multi-scalar-multiplication (MSM) in G1 (curve over base prime field).
    Bls12G1Msm,
    /// Point addition in G2 (curve over quadratic extension of the base prime field).
    Bls12G2Add,
    /// Multi-scalar-multiplication (MSM) in G2 (curve over quadratic extension of the base prime field).
    Bls12G2Msm,
    /// Pairing operations between a set of pairs of (G1, G2) points.
    Bls12Pairing,
    /// Base field element mapping into the G1 point.
    Bls12MapFpToGp1,
    /// Extension field element mapping into the G2 point.
    Bls12MapFp2ToGp2,
    /// ECDSA signature verification over the secp256r1 elliptic curve.
    P256Verify,
    /// Custom precompile identifier.
    Custom: []const u8,

    /// Create new custom precompile ID.
    pub fn custom(id: []const u8) PrecompileId {
        return PrecompileId{ .Custom = id };
    }

    /// Returns the name of the precompile as defined in EIP-7910.
    pub fn name(self: PrecompileId) []const u8 {
        return switch (self) {
            .EcRec => "ECREC",
            .Sha256 => "SHA256",
            .Ripemd160 => "RIPEMD160",
            .Identity => "ID",
            .ModExp => "MODEXP",
            .Bn254Add => "BN254_ADD",
            .Bn254Mul => "BN254_MUL",
            .Bn254Pairing => "BN254_PAIRING",
            .Blake2F => "BLAKE2F",
            .KzgPointEvaluation => "KZG_POINT_EVALUATION",
            .Bls12G1Add => "BLS12_G1ADD",
            .Bls12G1Msm => "BLS12_G1MSM",
            .Bls12G2Add => "BLS12_G2ADD",
            .Bls12G2Msm => "BLS12_G2MSM",
            .Bls12Pairing => "BLS12_PAIRING_CHECK",
            .Bls12MapFpToGp1 => "BLS12_MAP_FP_TO_G1",
            .Bls12MapFp2ToGp2 => "BLS12_MAP_FP2_TO_G2",
            .P256Verify => "P256VERIFY",
            .Custom => |id| id,
        };
    }

    /// Returns the precompile function for the given spec.
    ///
    /// If case of Custom it will return null.
    ///
    /// For case where precompile was still not introduced in the spec,
    /// it will return the fork closest to activation.
    pub fn precompile(self: PrecompileId, spec: PrecompileSpecId) ?Precompile {
        return switch (self) {
            .EcRec => secp256k1.ECRECOVER,
            .Sha256 => hash.SHA256,
            .Ripemd160 => hash.RIPEMD160,
            .Identity => identity.FUN,
            .ModExp => blk: {
                // ModExp changes gas calculation based on spec
                const mod_exp_precompile: Precompile = if (@intFromEnum(spec) < @intFromEnum(PrecompileSpecId.Berlin)) modexp.BYZANTIUM else if (@intFromEnum(spec) < @intFromEnum(PrecompileSpecId.Osaka)) modexp.BERLIN else modexp.OSAKA;
                break :blk mod_exp_precompile;
            },
            .Bn254Add => blk: {
                // BN254 add - gas cost changes in Istanbul
                const bn254_add_precompile: Precompile = if (@intFromEnum(spec) < @intFromEnum(PrecompileSpecId.Istanbul)) bn254.add.BYZANTIUM else bn254.add.ISTANBUL;
                break :blk bn254_add_precompile;
            },
            .Bn254Mul => blk: {
                // BN254 mul - gas cost changes in Istanbul
                const bn254_mul_precompile: Precompile = if (@intFromEnum(spec) < @intFromEnum(PrecompileSpecId.Istanbul)) bn254.mul.BYZANTIUM else bn254.mul.ISTANBUL;
                break :blk bn254_mul_precompile;
            },
            .Bn254Pairing => blk: {
                // BN254 pairing - gas cost changes in Istanbul
                const bn254_pair_precompile: Precompile = if (@intFromEnum(spec) < @intFromEnum(PrecompileSpecId.Istanbul)) bn254.pair.BYZANTIUM else bn254.pair.ISTANBUL;
                break :blk bn254_pair_precompile;
            },
            .Blake2F => blake2.FUN,
            .KzgPointEvaluation => kzg_point_evaluation.POINT_EVALUATION,
            .Bls12G1Add => bls12_381.g1_add.PRECOMPILE,
            .Bls12G1Msm => bls12_381.g1_msm.PRECOMPILE,
            .Bls12G2Add => bls12_381.g2_add.PRECOMPILE,
            .Bls12G2Msm => bls12_381.g2_msm.PRECOMPILE,
            .Bls12Pairing => bls12_381.pairing.PRECOMPILE,
            .Bls12MapFpToGp1 => bls12_381.map_fp_to_g1.PRECOMPILE,
            .Bls12MapFp2ToGp2 => bls12_381.map_fp2_to_g2.PRECOMPILE,
            .P256Verify => blk: {
                // P256 verify - gas cost changes in Osaka
                const p256_precompile: Precompile = if (@intFromEnum(spec) < @intFromEnum(PrecompileSpecId.Osaka)) secp256r1.P256VERIFY else secp256r1.P256VERIFY_OSAKA;
                break :blk p256_precompile;
            },
            .Custom => return null,
        };
    }
};

/// Precompile specification ID
pub const PrecompileSpecId = enum {
    /// Homestead spec
    Homestead,
    /// Byzantium spec
    Byzantium,
    /// Istanbul spec
    Istanbul,
    /// Berlin spec
    Berlin,
    /// Cancun spec
    Cancun,
    /// Prague spec
    Prague,
    /// Osaka spec
    Osaka,

    /// Map from full SpecId to PrecompileSpecId
    /// Groups similar specs together since precompiles only change at certain hardforks
    pub fn fromSpec(spec: primitives.SpecId) PrecompileSpecId {
        return switch (spec) {
            .frontier, .frontier_thawing, .homestead, .dao_fork, .tangerine, .spurious_dragon => .Homestead,
            .byzantium, .constantinople, .petersburg => .Byzantium,
            .istanbul, .muir_glacier => .Istanbul,
            .berlin, .london, .arrow_glacier, .gray_glacier, .merge, .shanghai => .Berlin,
            .cancun => .Cancun,
            .prague => .Prague,
            .osaka, .amsterdam => .Osaka,
        };
    }
};

/// Precompile structure
pub const Precompile = struct {
    /// Unique identifier
    id: PrecompileId,
    /// Precompile address
    address: primitives.Address,
    /// Precompile implementation
    func: PrecompileFn,

    /// Create new precompile
    pub fn new(id: PrecompileId, address: primitives.Address, func: PrecompileFn) Precompile {
        return Precompile{
            .id = id,
            .address = address,
            .func = func,
        };
    }

    /// Execute the precompile
    pub fn execute(self: Precompile, input: []const u8, gas_limit: u64) PrecompileResult {
        return self.func(input, gas_limit);
    }
};

/// Calculate the linear cost of a precompile
pub fn calcLinearCost(len: usize, base: u64, word: u64) u64 {
    return (len + 31) / 32 * word + base;
}

/// Convert u64 to address
pub fn u64ToAddress(value: u64) primitives.Address {
    var address: primitives.Address = [_]u8{0} ** 20;
    std.mem.writeInt(u64, address[12..20], value, .big);
    return address;
}

/// Precompiles collection
pub const Precompiles = struct {
    /// Inner HashMap of precompiles
    inner: std.AutoHashMap(primitives.Address, Precompile),
    /// Addresses of precompiles
    addresses: std.AutoHashMap(primitives.Address, void),
    /// Optimized access for short addresses
    optimized_access: [256]?Precompile,
    /// Whether all precompiles are short addresses
    all_short_addresses: bool,

    /// Create new precompiles collection
    pub fn new() Precompiles {
        return Precompiles{
            .inner = std.AutoHashMap(primitives.Address, Precompile).init(std.heap.c_allocator),
            .addresses = std.AutoHashMap(primitives.Address, void).init(std.heap.c_allocator),
            .optimized_access = [_]?Precompile{null} ** 256,
            .all_short_addresses = true,
        };
    }

    /// Add a precompile to the collection
    pub fn add(self: *Precompiles, precompile: Precompile) !void {
        try self.inner.put(precompile.address, precompile);
        try self.addresses.put(precompile.address, {});

        // Update optimized access for short addresses
        if (precompile.address[0] == 0 and precompile.address[1] == 0 and precompile.address[2] == 0 and precompile.address[3] == 0) {
            const index = std.mem.readInt(u32, precompile.address[16..20], .big);
            if (index < 256) {
                self.optimized_access[index] = precompile;
            }
        }
    }

    /// Get precompile by address
    pub fn get(self: *const Precompiles, address: primitives.Address) ?Precompile {
        return self.inner.get(address);
    }

    /// Check if address is a precompile
    pub fn contains(self: *const Precompiles, address: primitives.Address) bool {
        return self.addresses.contains(address);
    }

    /// Get precompiles for a specific spec
    pub fn forSpec(spec: PrecompileSpecId) Precompiles {
        var precompiles = Precompiles.new();

        switch (spec) {
            .Homestead => {
                precompiles.add(identity.FUN) catch {};
                precompiles.add(hash.SHA256) catch {};
                precompiles.add(hash.RIPEMD160) catch {};
                precompiles.add(secp256k1.ECRECOVER) catch {};
            },
            .Byzantium => {
                precompiles.add(identity.FUN) catch {};
                precompiles.add(hash.SHA256) catch {};
                precompiles.add(hash.RIPEMD160) catch {};
                precompiles.add(secp256k1.ECRECOVER) catch {};
                precompiles.add(modexp.BYZANTIUM) catch {};
                precompiles.add(bn254.add.BYZANTIUM) catch {};
                precompiles.add(bn254.mul.BYZANTIUM) catch {};
                precompiles.add(bn254.pair.BYZANTIUM) catch {};
            },
            .Istanbul => {
                precompiles.add(identity.FUN) catch {};
                precompiles.add(hash.SHA256) catch {};
                precompiles.add(hash.RIPEMD160) catch {};
                precompiles.add(secp256k1.ECRECOVER) catch {};
                precompiles.add(modexp.BYZANTIUM) catch {};
                precompiles.add(bn254.add.ISTANBUL) catch {};
                precompiles.add(bn254.mul.ISTANBUL) catch {};
                precompiles.add(bn254.pair.ISTANBUL) catch {};
                precompiles.add(blake2.FUN) catch {};
            },
            .Berlin => {
                precompiles.add(identity.FUN) catch {};
                precompiles.add(hash.SHA256) catch {};
                precompiles.add(hash.RIPEMD160) catch {};
                precompiles.add(secp256k1.ECRECOVER) catch {};
                precompiles.add(modexp.BERLIN) catch {};
                precompiles.add(bn254.add.ISTANBUL) catch {};
                precompiles.add(bn254.mul.ISTANBUL) catch {};
                precompiles.add(bn254.pair.ISTANBUL) catch {};
                precompiles.add(blake2.FUN) catch {};
            },
            .Cancun => {
                precompiles.add(identity.FUN) catch {};
                precompiles.add(hash.SHA256) catch {};
                precompiles.add(hash.RIPEMD160) catch {};
                precompiles.add(secp256k1.ECRECOVER) catch {};
                precompiles.add(modexp.BERLIN) catch {};
                precompiles.add(bn254.add.ISTANBUL) catch {};
                precompiles.add(bn254.mul.ISTANBUL) catch {};
                precompiles.add(bn254.pair.ISTANBUL) catch {};
                precompiles.add(blake2.FUN) catch {};
                precompiles.add(kzg_point_evaluation.POINT_EVALUATION) catch {};
            },
            .Prague => {
                precompiles.add(identity.FUN) catch {};
                precompiles.add(hash.SHA256) catch {};
                precompiles.add(hash.RIPEMD160) catch {};
                precompiles.add(secp256k1.ECRECOVER) catch {};
                precompiles.add(modexp.BERLIN) catch {};
                precompiles.add(bn254.add.ISTANBUL) catch {};
                precompiles.add(bn254.mul.ISTANBUL) catch {};
                precompiles.add(bn254.pair.ISTANBUL) catch {};
                precompiles.add(blake2.FUN) catch {};
                precompiles.add(kzg_point_evaluation.POINT_EVALUATION) catch {};
                precompiles.add(bls12_381.g1_add.PRECOMPILE) catch {};
                precompiles.add(bls12_381.g1_msm.PRECOMPILE) catch {};
                precompiles.add(bls12_381.g2_add.PRECOMPILE) catch {};
                precompiles.add(bls12_381.g2_msm.PRECOMPILE) catch {};
                precompiles.add(bls12_381.pairing.PRECOMPILE) catch {};
                precompiles.add(bls12_381.map_fp_to_g1.PRECOMPILE) catch {};
                precompiles.add(bls12_381.map_fp2_to_g2.PRECOMPILE) catch {};
            },
            .Osaka => {
                precompiles.add(identity.FUN) catch {};
                precompiles.add(hash.SHA256) catch {};
                precompiles.add(hash.RIPEMD160) catch {};
                precompiles.add(secp256k1.ECRECOVER) catch {};
                precompiles.add(modexp.OSAKA) catch {};
                precompiles.add(bn254.add.ISTANBUL) catch {};
                precompiles.add(bn254.mul.ISTANBUL) catch {};
                precompiles.add(bn254.pair.ISTANBUL) catch {};
                precompiles.add(blake2.FUN) catch {};
                precompiles.add(kzg_point_evaluation.POINT_EVALUATION) catch {};
                precompiles.add(bls12_381.g1_add.PRECOMPILE) catch {};
                precompiles.add(bls12_381.g1_msm.PRECOMPILE) catch {};
                precompiles.add(bls12_381.g2_add.PRECOMPILE) catch {};
                precompiles.add(bls12_381.g2_msm.PRECOMPILE) catch {};
                precompiles.add(bls12_381.pairing.PRECOMPILE) catch {};
                precompiles.add(bls12_381.map_fp_to_g1.PRECOMPILE) catch {};
                precompiles.add(bls12_381.map_fp2_to_g2.PRECOMPILE) catch {};
                precompiles.add(secp256r1.P256VERIFY_OSAKA) catch {};
            },
        }

        return precompiles;
    }
};

// Import test module
pub const tests = @import("tests.zig");

// Placeholder for testing
pub const testing = struct {
    pub fn testPrecompile() !void {
        std.log.info("Testing precompile module...", .{});

        // Test basic precompiles
        try testIdentity();
        try testHash();
        try testSecp256k1();

        std.log.info("Precompile module test passed!", .{});
    }

    fn testIdentity() !void {
        const input = "Hello, World!";
        const result = identity.identityRun(input, 1000);
        switch (result) {
            .success => |output| {
                std.debug.assert(output.gas_used == 15 + 3); // base + word cost
                std.debug.assert(std.mem.eql(u8, output.bytes, input));
            },
            .err => return error.TestUnexpectedResult,
        }
    }

    fn testHash() !void {
        const input = "Hello, World!";
        const sha256_result = hash.sha256Run(input, 1000);
        switch (sha256_result) {
            .success => |output| {
                std.debug.assert(output.gas_used == 60 + 12); // base + word cost
            },
            .err => return error.TestUnexpectedResult,
        }

        const ripemd160_result = hash.ripemd160Run(input, 1000);
        switch (ripemd160_result) {
            .success => |output| {
                std.debug.assert(output.gas_used == 600 + 120); // base + word cost
            },
            .err => return error.TestUnexpectedResult,
        }
    }

    fn testSecp256k1() !void {
        // Test with invalid input (should return empty result)
        const invalid_input = [_]u8{0} ** 128;
        const result = secp256k1.ecRecoverRun(&invalid_input, 10000);
        switch (result) {
            .success => |output| {
                std.debug.assert(output.gas_used == 3000);
                std.debug.assert(output.bytes.len == 0);
            },
            .err => return error.TestUnexpectedResult,
        }
    }
};
