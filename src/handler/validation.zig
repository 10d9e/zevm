const std = @import("std");
const primitives = @import("primitives");
const context = @import("context");
const state = @import("state");
const main = @import("main.zig");

// Gas constants for intrinsic gas calculation
const TX_BASE_COST: u64 = 21000;
const TX_CREATE_COST: u64 = 32000;
const CALLDATA_ZERO_BYTE_COST: u64 = 4;
const CALLDATA_NONZERO_BYTE_COST: u64 = 16;
const ACCESS_LIST_ADDRESS_COST: u64 = 2400;
const ACCESS_LIST_STORAGE_KEY_COST: u64 = 1900;
// EIP-7702: per-authorization intrinsic gas (PER_AUTH_BASE_COST)
const TX_EIP7702_AUTH_COST: u64 = 12500;

/// Validation utilities
pub const Validation = struct {
    /// Validate environment (block, tx, cfg) — no DB access needed.
    pub fn validateEnv(evm: *main.Evm) !void {
        const ctx = evm.getContext();

        // Validate block environment
        try validateBlockEnv(&ctx.block);

        // Validate transaction environment
        try validateTxEnv(&ctx.tx, &ctx.cfg);

        // Validate configuration environment
        try validateCfgEnv(&ctx.cfg);
    }

    /// Validate block environment
    pub fn validateBlockEnv(block: *context.BlockEnv) !void {
        _ = block;
        // Block fields are unsigned — no negative checks needed.
        // gas_limit == 0 is technically valid (empty block), so we skip it.
    }

    /// Validate transaction environment (no DB access — just field checks)
    pub fn validateTxEnv(tx: *context.TxEnv, cfg: *context.CfgEnv) !void {
        // EIP-155: Validate chain ID matches if present in the tx
        if (cfg.tx_chain_id_check) {
            if (tx.chain_id) |tx_chain_id| {
                if (tx_chain_id != cfg.chain_id) {
                    return ValidationError.InvalidChainId;
                }
            }
        }

        // EIP-7825: Transaction gas limit cap (30,000,000 by default)
        const gas_cap = cfg.tx_gas_limit_cap orelse primitives.TX_GAS_LIMIT_CAP;
        if (tx.gas_limit > gas_cap) {
            return ValidationError.GasLimitExceedsCap;
        }

        // EIP-1559: priority fee must not exceed max fee per gas
        if (tx.gas_priority_fee) |priority_fee| {
            if (priority_fee > tx.gas_price) {
                return ValidationError.PriorityFeeGreaterThanMaxFee;
            }
        }
    }

    /// Validate configuration environment
    pub fn validateCfgEnv(cfg: *context.CfgEnv) !void {
        if (cfg.chain_id == 0) {
            return ValidationError.InvalidChainId;
        }
    }

    /// Calculate the initial (intrinsic) gas and EIP-7623 floor gas for a transaction.
    ///
    /// Returns `InsufficientGas` if gas_limit < initial_gas.
    pub fn validateInitialTxGas(evm: *main.Evm) !InitialAndFloorGas {
        const ctx = evm.getContext();
        const tx = &ctx.tx;
        const spec = ctx.cfg.spec;

        // Calculate initial gas cost
        const initial_gas = calculateInitialGas(tx, spec);

        // Calculate floor gas (EIP-7623: tokens * 10)
        const floor_gas = calculateFloorGas(tx, spec);

        // Validate gas limit covers intrinsic gas
        if (tx.gas_limit < initial_gas) {
            return ValidationError.InsufficientGas;
        }

        return InitialAndFloorGas{
            .initial_gas = initial_gas,
            .floor_gas = floor_gas,
        };
    }

    /// Validate caller account state and deduct the maximum gas fee + value.
    ///
    /// - Loads caller from the DB (cold load, records journal warming entry)
    /// - Validates EIP-3607 (reject if caller has code)
    /// - Validates nonce matches tx.nonce (unless disabled)
    /// - Validates caller balance >= gas_limit * gas_price + value
    /// - Deducts maximum fee from caller and bumps nonce (journaled, revertable)
    pub fn validateAgainstStateAndDeductCaller(evm: *main.Evm, initial_gas: u64) !void {
        const ctx = evm.getContext();
        const tx = &ctx.tx;
        const cfg = &ctx.cfg;
        const js = &ctx.journaled_state;

        // Load caller account (marks it warm, creates journal entry)
        const load_result = try js.loadAccountMutOptionalCode(tx.caller, true, false);
        const journaled_account = load_result.data;
        const account_info = &journaled_account.account.info;

        // EIP-3607: Reject transactions from senders with deployed code
        if (!cfg.disable_eip3607) {
            if (!std.mem.eql(u8, &account_info.code_hash, &primitives.KECCAK_EMPTY)) {
                return ValidationError.SenderHasCode;
            }
        }

        // Validate nonce
        if (!cfg.disable_nonce_check) {
            if (account_info.nonce != tx.nonce) {
                return ValidationError.NonceMismatch;
            }
        }

        // Compute effective gas price (EIP-1559): min(max_fee, basefee + priority_fee).
        // Balance validation uses max_fee (worst-case affordability).
        // Deduction uses effective_gas_price so the refund in postExecution balances correctly.
        const effective_gas_price: u128 = if (tx.gas_priority_fee) |tip|
            @min(tx.gas_price, @as(u128, ctx.block.basefee) + tip)
        else
            tx.gas_price;

        // Maximum gas fee at worst-case price (for balance validation only)
        const max_gas_fee: primitives.U256 = @as(primitives.U256, tx.gas_limit) * @as(primitives.U256, tx.gas_price);
        // Effective gas fee deducted upfront (reimbursed proportionally in postExecution)
        const effective_gas_fee: primitives.U256 = @as(primitives.U256, tx.gas_limit) * @as(primitives.U256, effective_gas_price);

        // Validate balance covers worst-case gas fee + value (affordability check at max_fee).
        const max_cost = std.math.add(primitives.U256, max_gas_fee, tx.value) catch {
            return ValidationError.BalanceOverflow;
        };
        if (account_info.balance < max_cost) {
            return ValidationError.InsufficientBalance;
        }

        // Validate base fee if enabled (EIP-1559)
        if (!cfg.disable_base_fee) {
            const base_fee = ctx.block.basefee;
            if (@as(u128, tx.gas_price) < @as(u128, base_fee)) {
                return ValidationError.GasPriceLessThanBaseFee;
            }
        }

        _ = initial_gas; // used in Phase 3 for floor gas check

        // Record journal entries BEFORE mutating (so revert can restore old state)
        const old_balance = account_info.balance;
        js.callerAccountingJournalEntry(tx.caller, old_balance, true);

        // Deduct effective gas fee from caller balance (not the value — handled in executeFrame)
        account_info.balance = old_balance - effective_gas_fee;

        // Bump nonce
        account_info.nonce += 1;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// Calculates the intrinsic gas for a transaction.
    ///
    /// Breakdown:
    ///   21,000 base (always)
    /// + 32,000 for CREATE transactions
    /// + 4 per zero calldata byte, 16 per non-zero calldata byte
    /// + 2,400 per access-list address, 1,900 per access-list storage slot
    /// + 12,500 per EIP-7702 authorization list entry (Prague+)
    /// + GAS_PER_BLOB per EIP-4844 blob hash
    pub fn calculateInitialGas(tx: *const context.TxEnv, spec: primitives.SpecId) u64 {
        var gas: u64 = TX_BASE_COST;

        // CREATE adds extra base cost
        if (tx.kind == .Create) {
            gas += TX_CREATE_COST;
        }

        // Calldata costs: 4 per zero byte, 16 per non-zero byte
        if (tx.data) |data| {
            for (data.items) |byte| {
                if (byte == 0) {
                    gas += CALLDATA_ZERO_BYTE_COST;
                } else {
                    gas += CALLDATA_NONZERO_BYTE_COST;
                }
            }
        }

        // EIP-2930 / EIP-2929: Access list gas
        if (tx.access_list.items) |items| {
            for (items.items) |item| {
                gas += ACCESS_LIST_ADDRESS_COST;
                gas += @as(u64, item.storage_keys.items.len) * ACCESS_LIST_STORAGE_KEY_COST;
            }
        }

        // EIP-4844: blob intrinsic gas (GAS_PER_BLOB per blob)
        if (tx.blob_hashes) |blob_hashes| {
            gas += @as(u64, blob_hashes.items.len) * primitives.GAS_PER_BLOB;
        }

        // EIP-7702: authorization list intrinsic gas (Prague+)
        if (primitives.isEnabledIn(spec, .prague)) {
            if (tx.authorization_list) |auth_list| {
                gas += @as(u64, auth_list.items.len) * TX_EIP7702_AUTH_COST;
            }
        }

        return gas;
    }

    /// Validate EIP-7702 set-code transaction fields (Prague+).
    ///
    /// - Rejects if Prague is not enabled
    /// - Rejects if the authorization list is empty
    pub fn validateEip7702Tx(tx: *const context.TxEnv, spec: primitives.SpecId) !void {
        if (!primitives.isEnabledIn(spec, .prague)) return;

        // Only applies to transactions that carry an authorization list
        const auth_list = tx.authorization_list orelse return;

        // EIP-7702: authorization list must be non-empty
        if (auth_list.items.len == 0) {
            return ValidationError.EmptyAuthorizationList;
        }
    }

    /// Validate EIP-4844 blob transaction fields (Cancun+).
    ///
    /// Checks blob count, versioned hash format, and blob gas price affordability.
    pub fn validateBlobTx(tx: *const context.TxEnv, block: *const context.BlockEnv, spec: primitives.SpecId) !void {
        if (!primitives.isEnabledIn(spec, .cancun)) return;

        const blob_hashes = tx.blob_hashes orelse return;

        // EIP-4844: blob transactions cannot be CREATE
        if (tx.kind == .Create) {
            return ValidationError.BlobCreateTransaction;
        }

        // Blob count limit
        if (blob_hashes.items.len > primitives.MAX_BLOB_NUMBER_PER_BLOCK) {
            return ValidationError.TooManyBlobs;
        }

        // All blob hashes must use KZG version prefix 0x01
        for (blob_hashes.items) |hash| {
            if (hash[0] != primitives.VERSIONED_HASH_VERSION_KZG) {
                return ValidationError.InvalidBlobVersionedHash;
            }
        }

        // max_fee_per_blob_gas must cover the current block blob base fee
        if (block.blob_excess_gas_and_price) |blob_info| {
            if (tx.max_fee_per_blob_gas < blob_info.blob_gasprice) {
                return ValidationError.BlobGasPriceTooLow;
            }
        }
    }

    /// Calculates the EIP-7623 floor gas (tokens * 10).
    ///
    /// Floor gas ensures a minimum amount of gas is spent on calldata-heavy txs.
    pub fn calculateFloorGas(tx: *const context.TxEnv, spec: primitives.SpecId) u64 {
        if (!primitives.isEnabledIn(spec, .prague)) {
            return 0;
        }

        // EIP-7623: token_cost * 10 where token_cost is calldata tokens
        // (same zero/nonzero byte distinction)
        var tokens: u64 = 0;
        if (tx.data) |data| {
            for (data.items) |byte| {
                if (byte == 0) {
                    tokens += CALLDATA_ZERO_BYTE_COST;
                } else {
                    tokens += CALLDATA_NONZERO_BYTE_COST;
                }
            }
        }
        return tokens * 10;
    }
};

/// Initial and floor gas result
pub const InitialAndFloorGas = struct {
    /// Intrinsic gas required before execution begins
    initial_gas: u64,
    /// EIP-7623 floor gas requirement
    floor_gas: u64,
};

/// Validation errors
pub const ValidationError = error{
    InvalidChainId,
    GasLimitExceedsCap,
    PriorityFeeGreaterThanMaxFee,
    InsufficientGas,
    SenderHasCode,
    NonceMismatch,
    BalanceOverflow,
    InsufficientBalance,
    GasPriceLessThanBaseFee,
    CallerLoadFailed,
    // EIP-4844 blob transaction errors
    TooManyBlobs,
    InvalidBlobVersionedHash,
    BlobGasPriceTooLow,
    BlobCreateTransaction,
    // EIP-7702 set-code transaction errors
    EmptyAuthorizationList,
};

test {
    _ = @import("validation_tests.zig");
}
