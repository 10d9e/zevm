const std = @import("std");
const primitives = @import("primitives");
const context = @import("context");
const main = @import("main.zig");

/// Validation utilities
pub const Validation = struct {
    /// Validate environment
    pub fn validateEnv(evm: *main.Evm) !void {
        const ctx = evm.getContext();

        // Validate block environment
        try validateBlockEnv(&ctx.block);

        // Validate transaction environment
        try validateTxEnv(&ctx.tx);

        // Validate configuration environment
        try validateCfgEnv(&ctx.cfg);
    }

    /// Validate block environment
    pub fn validateBlockEnv(block: *context.BlockEnv) !void {
        // U256 values are always >= 0, no need to check number/timestamp

        // Validate gas limit
        if (block.gas_limit == 0) {
            return error.InvalidGasLimit;
        }

        // basefee is u64, always >= 0
    }

    /// Validate transaction environment
    pub fn validateTxEnv(tx: *context.TxEnv) !void {
        // Validate gas limit
        if (tx.gas_limit == 0) {
            return error.InvalidGasLimit;
        }

        // gas_price is u128, always >= 0
        // gas_priority_fee is ?u128, always >= 0 if present
        // value is U256, always >= 0
        // nonce is u64, always >= 0
    }

    /// Validate configuration environment
    pub fn validateCfgEnv(cfg: *context.CfgEnv) !void {
        // Validate chain ID
        if (cfg.chain_id == 0) {
            return error.InvalidChainId;
        }

        // Validate spec ID
        // Spec ID validation is handled by the enum type
    }

    /// Validate initial transaction gas
    pub fn validateInitialTxGas(evm: *main.Evm) !InitialAndFloorGas {
        const ctx = evm.getContext();
        const tx = &ctx.tx;

        // Calculate initial gas cost
        const initial_gas = calculateInitialGas(tx);

        // Calculate floor gas (EIP-7623)
        const floor_gas = calculateFloorGas(tx);

        // Validate gas limit covers initial gas
        if (tx.gas_limit < initial_gas) {
            return error.InsufficientGas;
        }

        return InitialAndFloorGas{
            .initial_gas = initial_gas,
            .floor_gas = floor_gas,
        };
    }

    /// Validate against state and deduct caller
    pub fn validateAgainstStateAndDeductCaller(evm: *main.Evm) !void {
        const ctx = evm.getContext();
        const tx = &ctx.tx;

        // Get caller account
        const caller_account = try ctx.db.basic(tx.caller);

        // Validate caller exists
        if (caller_account == null) {
            return error.CallerAccountNotFound;
        }

        // Validate nonce
        if (caller_account.?.nonce != tx.nonce) {
            return error.InvalidNonce;
        }

        // Calculate total cost
        const total_cost = calculateTotalCost(tx);

        // Validate sufficient balance
        if (caller_account.?.balance.lt(total_cost)) {
            return error.InsufficientBalance;
        }

        // Deduct cost from caller
        // In a real implementation, would update account balance
    }

    /// Calculate initial gas cost
    fn calculateInitialGas(tx: *context.TxEnv) u64 {
        var gas: u64 = 0;

        // Base gas cost
        gas += 21000;

        // Data gas cost
        if (tx.data) |data| {
            gas += data.len * 16; // 16 gas per byte for non-zero bytes
            // In a real implementation, would also count zero bytes at 4 gas each
        }

        // Access list gas cost (EIP-2929)
        if (tx.access_list) |access_list| {
            gas += access_list.len * 2400; // 2400 gas per access list entry
        }

        return gas;
    }

    /// Calculate floor gas (EIP-7623)
    fn calculateFloorGas(tx: *context.TxEnv) u64 {
        _ = tx;

        // Floor gas calculation
        // In a real implementation, would calculate based on transaction type
        return 0;
    }

    /// Calculate total cost
    fn calculateTotalCost(tx: *context.TxEnv) primitives.U256 {
        // Add gas cost: gas_cost (u64) * gas_price (u128)
        const gas_cost = calculateInitialGas(tx);
        const gas_price = tx.gas_price;
        const gas_total = primitives.U256.from(gas_cost).mul(primitives.U256.fromU128(gas_price));

        return tx.value.add(gas_total);
    }
};

/// Initial and floor gas structure
pub const InitialAndFloorGas = struct {
    /// Initial gas cost
    initial_gas: u64,
    /// Floor gas requirement
    floor_gas: u64,
};

/// Validation errors
pub const ValidationError = error{
    InvalidBlockNumber,
    InvalidTimestamp,
    InvalidGasLimit,
    InvalidBaseFee,
    InvalidGasPrice,
    InvalidMaxFeePerGas,
    InvalidMaxPriorityFeePerGas,
    InvalidValue,
    InvalidNonce,
    InvalidChainId,
    InsufficientGas,
    CallerAccountNotFound,
    InsufficientBalance,
};

// Placeholder for testing
pub const testing = struct {
    pub fn testValidation() !void {
        std.log.info("Testing validation module...", .{});

        // Test block environment validation
        var block = context.BlockEnv.default();

        try Validation.validateBlockEnv(&block);

        // Test transaction environment validation
        var tx = context.TxEnv.default();
        defer tx.deinit();

        try Validation.validateTxEnv(&tx);

        // Test configuration environment validation
        var cfg = context.CfgEnv.default();

        try Validation.validateCfgEnv(&cfg);

        // Test initial and floor gas
        const initial_and_floor = InitialAndFloorGas{
            .initial_gas = 21000,
            .floor_gas = 0,
        };

        std.debug.assert(initial_and_floor.initial_gas == 21000);
        std.debug.assert(initial_and_floor.floor_gas == 0);

        std.log.info("Validation module test passed!", .{});
    }
};
