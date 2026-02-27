const std = @import("std");
const primitives = @import("primitives");

/// The block environment
pub const BlockEnv = struct {
    /// The number of ancestor blocks of this block (block height).
    number: primitives.U256,
    /// Beneficiary (Coinbase or miner) is a address that have signed the block.
    ///
    /// This is the receiver address of all the gas spent in the block.
    beneficiary: primitives.Address,
    /// The timestamp of the block in seconds since the UNIX epoch
    timestamp: primitives.U256,
    /// The gas limit of the block
    gas_limit: u64,
    /// The base fee per gas, added in the London upgrade with EIP-1559
    basefee: u64,
    /// The difficulty of the block
    ///
    /// Unused after the Paris (AKA the merge) upgrade, and replaced by `prevrandao`.
    difficulty: primitives.U256,
    /// The output of the randomness beacon provided by the beacon chain
    ///
    /// Replaces `difficulty` after the Paris (AKA the merge) upgrade with EIP-4399.
    ///
    /// Note: `prevrandao` can be found in a block in place of `mix_hash`.
    prevrandao: ?primitives.Hash,
    /// Excess blob gas and blob gasprice
    ///
    /// Incorporated as part of the Cancun upgrade via EIP-4844.
    blob_excess_gas_and_price: ?BlobExcessGasAndPrice,

    pub fn default() BlockEnv {
        return .{
            .number = @as(primitives.U256, 0),
            .beneficiary = [_]u8{0} ** 20,
            .timestamp = @as(primitives.U256, 1),
            .gas_limit = std.math.maxInt(u64),
            .basefee = 0,
            .difficulty = @as(primitives.U256, 0),
            .prevrandao = null,
            .blob_excess_gas_and_price = BlobExcessGasAndPrice.new(0, primitives.BLOB_BASE_FEE_UPDATE_FRACTION_PRAGUE),
        };
    }

    /// Takes `blob_excess_gas` saves it inside env
    /// and calculates `blob_fee` with [`BlobExcessGasAndPrice`].
    pub fn setBlobExcessGasAndPrice(self: *BlockEnv, excess_blob_gas: u64, base_fee_update_fraction: u64) void {
        self.blob_excess_gas_and_price = BlobExcessGasAndPrice.new(excess_blob_gas, base_fee_update_fraction);
    }

    pub fn getNumber(self: BlockEnv) primitives.U256 {
        return self.number;
    }

    pub fn getBeneficiary(self: BlockEnv) primitives.Address {
        return self.beneficiary;
    }

    pub fn getTimestamp(self: BlockEnv) primitives.U256 {
        return self.timestamp;
    }

    pub fn getGasLimit(self: BlockEnv) u64 {
        return self.gas_limit;
    }

    pub fn getBasefee(self: BlockEnv) u64 {
        return self.basefee;
    }

    pub fn getDifficulty(self: BlockEnv) primitives.U256 {
        return self.difficulty;
    }

    pub fn getPrevrandao(self: BlockEnv) ?primitives.Hash {
        return self.prevrandao;
    }

    pub fn blobExcessGasAndPrice(self: BlockEnv) ?BlobExcessGasAndPrice {
        return self.blob_excess_gas_and_price;
    }
};

/// Excess blob gas and blob gasprice
pub const BlobExcessGasAndPrice = struct {
    excess_blob_gas: u64,
    blob_gasprice: u64,

    pub fn new(excess_blob_gas: u64, base_fee_update_fraction: u64) BlobExcessGasAndPrice {
        return .{
            .excess_blob_gas = excess_blob_gas,
            .blob_gasprice = calculateBlobGasprice(excess_blob_gas, base_fee_update_fraction),
        };
    }

    pub fn excessBlobGas(self: BlobExcessGasAndPrice) u64 {
        return self.excess_blob_gas;
    }

    pub fn blobGasprice(self: BlobExcessGasAndPrice) u64 {
        return self.blob_gasprice;
    }
};

/// Calculate blob gasprice based on excess blob gas and base fee update fraction
fn calculateBlobGasprice(excess_blob_gas: u64, base_fee_update_fraction: u64) u64 {
    // Simplified calculation - in practice this would be more complex
    // This is a placeholder implementation
    if (excess_blob_gas == 0) return 1;
    return @min(excess_blob_gas / base_fee_update_fraction, std.math.maxInt(u64));
}

/// Builder for constructing [`BlockEnv`] instances
pub const BlockEnvBuilder = struct {
    number: ?primitives.U256,
    beneficiary: ?primitives.Address,
    timestamp: ?primitives.U256,
    gas_limit: ?u64,
    basefee: ?u64,
    difficulty: ?primitives.U256,
    prevrandao: ?primitives.Hash,
    blob_excess_gas_and_price: ?BlobExcessGasAndPrice,

    pub fn new() BlockEnvBuilder {
        return .{
            .number = null,
            .beneficiary = null,
            .timestamp = null,
            .gas_limit = null,
            .basefee = null,
            .difficulty = null,
            .prevrandao = null,
            .blob_excess_gas_and_price = null,
        };
    }

    pub fn setNumber(self: BlockEnvBuilder, number: primitives.U256) BlockEnvBuilder {
        return .{
            .number = number,
            .beneficiary = self.beneficiary,
            .timestamp = self.timestamp,
            .gas_limit = self.gas_limit,
            .basefee = self.basefee,
            .difficulty = self.difficulty,
            .prevrandao = self.prevrandao,
            .blob_excess_gas_and_price = self.blob_excess_gas_and_price,
        };
    }

    pub fn setBeneficiary(self: BlockEnvBuilder, beneficiary: primitives.Address) BlockEnvBuilder {
        return .{
            .number = self.number,
            .beneficiary = beneficiary,
            .timestamp = self.timestamp,
            .gas_limit = self.gas_limit,
            .basefee = self.basefee,
            .difficulty = self.difficulty,
            .prevrandao = self.prevrandao,
            .blob_excess_gas_and_price = self.blob_excess_gas_and_price,
        };
    }

    pub fn setTimestamp(self: BlockEnvBuilder, timestamp: primitives.U256) BlockEnvBuilder {
        return .{
            .number = self.number,
            .beneficiary = self.beneficiary,
            .timestamp = timestamp,
            .gas_limit = self.gas_limit,
            .basefee = self.basefee,
            .difficulty = self.difficulty,
            .prevrandao = self.prevrandao,
            .blob_excess_gas_and_price = self.blob_excess_gas_and_price,
        };
    }

    pub fn setGasLimit(self: BlockEnvBuilder, gas_limit: u64) BlockEnvBuilder {
        return .{
            .number = self.number,
            .beneficiary = self.beneficiary,
            .timestamp = self.timestamp,
            .gas_limit = gas_limit,
            .basefee = self.basefee,
            .difficulty = self.difficulty,
            .prevrandao = self.prevrandao,
            .blob_excess_gas_and_price = self.blob_excess_gas_and_price,
        };
    }

    pub fn setBasefee(self: BlockEnvBuilder, basefee: u64) BlockEnvBuilder {
        return .{
            .number = self.number,
            .beneficiary = self.beneficiary,
            .timestamp = self.timestamp,
            .gas_limit = self.gas_limit,
            .basefee = basefee,
            .difficulty = self.difficulty,
            .prevrandao = self.prevrandao,
            .blob_excess_gas_and_price = self.blob_excess_gas_and_price,
        };
    }

    pub fn setDifficulty(self: BlockEnvBuilder, difficulty: primitives.U256) BlockEnvBuilder {
        return .{
            .number = self.number,
            .beneficiary = self.beneficiary,
            .timestamp = self.timestamp,
            .gas_limit = self.gas_limit,
            .basefee = self.basefee,
            .difficulty = difficulty,
            .prevrandao = self.prevrandao,
            .blob_excess_gas_and_price = self.blob_excess_gas_and_price,
        };
    }

    pub fn setPrevrandao(self: BlockEnvBuilder, prevrandao: ?primitives.Hash) BlockEnvBuilder {
        return .{
            .number = self.number,
            .beneficiary = self.beneficiary,
            .timestamp = self.timestamp,
            .gas_limit = self.gas_limit,
            .basefee = self.basefee,
            .difficulty = self.difficulty,
            .prevrandao = prevrandao,
            .blob_excess_gas_and_price = self.blob_excess_gas_and_price,
        };
    }

    pub fn blobExcessGasAndPrice(self: BlockEnvBuilder, blob_excess_gas_and_price: ?BlobExcessGasAndPrice) BlockEnvBuilder {
        return .{
            .number = self.number,
            .beneficiary = self.beneficiary,
            .timestamp = self.timestamp,
            .gas_limit = self.gas_limit,
            .basefee = self.basefee,
            .difficulty = self.difficulty,
            .prevrandao = self.prevrandao,
            .blob_excess_gas_and_price = blob_excess_gas_and_price,
        };
    }

    pub fn build(self: BlockEnvBuilder) BlockEnv {
        return .{
            .number = self.number orelse @as(primitives.U256, 0),
            .beneficiary = self.beneficiary orelse primitives.Address{0} ** 20,
            .timestamp = self.timestamp orelse @as(primitives.U256, 1),
            .gas_limit = self.gas_limit orelse std.math.maxInt(u64),
            .basefee = self.basefee orelse 0,
            .difficulty = self.difficulty orelse @as(primitives.U256, 0),
            .prevrandao = self.prevrandao,
            .blob_excess_gas_and_price = self.blob_excess_gas_and_price orelse BlobExcessGasAndPrice.new(0, primitives.BLOB_BASE_FEE_UPDATE_FRACTION_PRAGUE),
        };
    }
};
