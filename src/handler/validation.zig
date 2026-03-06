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
// EIP-7702: per-authorization intrinsic gas (PER_EMPTY_ACCOUNT_COST per EIP-7702 spec)
const TX_EIP7702_AUTH_COST: u64 = 25000;
// EIP-7623: token costs (different from calldata gas costs)
const FLOOR_ZERO_TOKEN_COST: u64 = 1;
const FLOOR_NONZERO_TOKEN_COST: u64 = 4;
// EIP-3860: max initcode size = 2 * MAX_CODE_SIZE
const MAX_INITCODE_SIZE: usize = 49152;

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

        // Block gas limit: tx gas_limit must not exceed block gas_limit
        if (!ctx.cfg.disable_block_gas_limit) {
            if (ctx.tx.gas_limit > ctx.block.gas_limit) {
                return ValidationError.TxGasLimitExceedsBlockLimit;
            }
        }
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

        // EIP-7825: Transaction gas limit cap (opt-in — null = no cap).
        // Set cfg.tx_gas_limit_cap explicitly to enforce a cap (e.g. 1<<24 for Osaka EIP-7825).
        if (cfg.tx_gas_limit_cap) |gas_cap| {
            if (tx.gas_limit > gas_cap) {
                return ValidationError.GasLimitExceedsCap;
            }
        }

        // EIP-1559: priority fee must not exceed max fee per gas
        if (!cfg.disable_priority_fee_check) {
            if (tx.gas_priority_fee) |priority_fee| {
                if (priority_fee > tx.gas_price) {
                    return ValidationError.PriorityFeeGreaterThanMaxFee;
                }
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
    /// Returns `InsufficientGas` if gas_limit < initial_gas or < floor total.
    /// Returns `CreateInitcodeOverLimit` if CREATE initcode exceeds EIP-3860 limit (Shanghai+).
    pub fn validateInitialTxGas(evm: *main.Evm) !InitialAndFloorGas {
        const ctx = evm.getContext();
        const tx = &ctx.tx;
        const spec = ctx.cfg.spec;

        // EIP-3860 (Shanghai+): initcode size limit for CREATE transactions
        if (primitives.isEnabledIn(spec, .shanghai)) {
            if (tx.kind == .Create) {
                const calldata_len = if (tx.data) |d| d.items.len else 0;
                if (calldata_len > MAX_INITCODE_SIZE) {
                    return ValidationError.CreateInitcodeOverLimit;
                }
            }
        }

        // Calculate initial gas cost
        const initial_gas = calculateInitialGas(tx, spec);

        // Calculate floor gas exec-portion (EIP-7623: tokens * 10, only calldata tokens).
        // Returns 0 if EIP-7623 is disabled via cfg flag.
        const floor_gas = if (!ctx.cfg.disable_eip7623) calculateFloorGas(tx, spec) else 0;

        // Validate gas limit covers intrinsic gas
        if (tx.gas_limit < initial_gas) {
            return ValidationError.InsufficientGas;
        }

        // EIP-7623 (Prague+): gas_limit must also cover the floor (21000 base + floor exec gas).
        // floor_gas is the exec-portion only; the 21000 base is the fixed floor minimum.
        // Skipped if disable_eip7623 is set (floor_gas will be 0 in that case).
        if (primitives.isEnabledIn(spec, .prague)) {
            if (floor_gas > 0 and tx.gas_limit < TX_BASE_COST + floor_gas) {
                return ValidationError.InsufficientGas;
            }
        }

        return InitialAndFloorGas{
            .initial_gas = initial_gas,
            .floor_gas = floor_gas,
        };
    }

    /// Validate caller account state and deduct the maximum gas fee + value.
    ///
    /// - Loads caller from the DB (cold load, records journal warming entry)
    /// - Validates EIP-3607 (reject if caller has code; EIP-7702 delegation accounts are exempt)
    /// - Validates EIP-2681 (nonce overflow for CREATE)
    /// - Validates nonce matches tx.nonce (unless disabled)
    /// - Validates caller balance >= gas_limit * gas_price + value + blob fees
    /// - Deducts effective gas fee + blob fee from caller and bumps nonce (journaled, revertable)
    pub fn validateAgainstStateAndDeductCaller(evm: *main.Evm, initial_gas: u64) !void {
        const ctx = evm.getContext();
        const tx = &ctx.tx;
        const cfg = &ctx.cfg;
        const js = &ctx.journaled_state;

        // Load caller account with code (need code to check EIP-7702 delegation exception in EIP-3607)
        const load_result = try js.loadAccountMutOptionalCode(tx.caller, true, false);
        const journaled_account = load_result.data;
        const account_info = &journaled_account.account.info;

        // EIP-3607: Reject transactions from senders with deployed code.
        // EIP-7702 exception: delegation accounts (code is an EIP-7702 designator) may send txs.
        if (!cfg.disable_eip3607) {
            if (!std.mem.eql(u8, &account_info.code_hash, &primitives.KECCAK_EMPTY)) {
                const is_delegation = if (account_info.code) |code| code.isEip7702() else false;
                if (!is_delegation) {
                    return ValidationError.SenderHasCode;
                }
            }
        }

        // EIP-2681: CREATE tx with sender nonce at u64 max is invalid
        if (tx.kind == .Create) {
            if (account_info.nonce == std.math.maxInt(u64)) {
                return ValidationError.NonceIsMax;
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

        // EIP-4844: compute blob fees — balance validation uses max_fee_per_blob_gas (worst-case),
        // upfront deduction uses actual blob_gasprice (what the user actually pays).
        // Blob fees are NOT reimbursed in postExecution (separate fee market).
        var max_blob_fee: primitives.U256 = 0; // for balance validation (worst-case)
        var blob_fee: primitives.U256 = 0; // for upfront deduction (actual price)
        if (tx.blob_hashes) |blob_hashes| {
            if (blob_hashes.items.len > 0) {
                const blob_count = blob_hashes.items.len;
                // Balance validation: use tx.max_fee_per_blob_gas (the max the user agreed to pay)
                max_blob_fee = @as(primitives.U256, blob_count) *
                    @as(primitives.U256, primitives.GAS_PER_BLOB) *
                    @as(primitives.U256, tx.max_fee_per_blob_gas);
                // Upfront deduction: use actual blob_gasprice from the block
                if (ctx.block.blob_excess_gas_and_price) |blob_info| {
                    blob_fee = @as(primitives.U256, blob_count) *
                        @as(primitives.U256, primitives.GAS_PER_BLOB) *
                        @as(primitives.U256, blob_info.blob_gasprice);
                }
            }
        }

        // Validate balance covers worst-case gas fee + value + blob fee.
        var max_cost = std.math.add(primitives.U256, max_gas_fee, tx.value) catch {
            return ValidationError.BalanceOverflow;
        };
        max_cost = std.math.add(primitives.U256, max_cost, max_blob_fee) catch {
            return ValidationError.BlobFeeOverflow;
        };
        if (account_info.balance < max_cost) {
            if (!cfg.disable_balance_check) {
                return ValidationError.InsufficientBalance;
            }
            // When balance check is disabled (e.g. eth_call simulation), grant the caller
            // enough balance so execution does not fail due to insufficient funds.
            account_info.balance = max_cost;
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

        // Deduct effective gas fee + blob fee from caller balance upfront.
        // (Value transfer is handled in executeFrame, not here.)
        // Skip if fee charging is disabled (e.g. eth_call on OP-chains where basefee=0 is insufficient).
        if (!cfg.disable_fee_charge) {
            account_info.balance = old_balance - effective_gas_fee - blob_fee;
        }

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
    /// + 25,000 per EIP-7702 authorization list entry (PER_EMPTY_ACCOUNT_COST, Prague+)
    /// + GAS_PER_BLOB per EIP-4844 blob hash
    pub fn calculateInitialGas(tx: *const context.TxEnv, spec: primitives.SpecId) u64 {
        var gas: u64 = TX_BASE_COST;

        // CREATE adds extra base cost (EIP-2, Homestead+).
        // Frontier does NOT charge G_TXCREATE (32000) for CREATE transactions.
        if (tx.kind == .Create and primitives.isEnabledIn(spec, .homestead)) {
            gas += TX_CREATE_COST;
        }

        // Calldata costs:
        //   4 gas per zero byte (all forks)
        //   16 gas per nonzero byte (Istanbul+, EIP-2028)
        //   68 gas per nonzero byte (pre-Istanbul: Frontier through Constantinople/Petersburg)
        const calldata_nonzero_cost: u64 = if (primitives.isEnabledIn(spec, .istanbul))
            CALLDATA_NONZERO_BYTE_COST // 16
        else
            68; // pre-EIP-2028 (Frontier through Petersburg)
        if (tx.data) |data| {
            for (data.items) |byte| {
                if (byte == 0) {
                    gas += CALLDATA_ZERO_BYTE_COST;
                } else {
                    gas += calldata_nonzero_cost;
                }
            }
        }

        // EIP-3860 (Shanghai+): initcode word gas for CREATE transactions
        // 2 gas per 32-byte word of initcode (rounds up)
        if (tx.kind == .Create and primitives.isEnabledIn(spec, .shanghai)) {
            const calldata_len: u64 = if (tx.data) |d| @intCast(d.items.len) else 0;
            gas += 2 * ((calldata_len + 31) / 32);
        }

        // EIP-2930 / EIP-2929: Access list gas
        if (tx.access_list.items) |items| {
            for (items.items) |item| {
                gas += ACCESS_LIST_ADDRESS_COST;
                gas += @as(u64, item.storage_keys.items.len) * ACCESS_LIST_STORAGE_KEY_COST;
            }
        }

        // EIP-4844: blob gas is a SEPARATE fee market paid from sender balance,
        // NOT counted in the transaction gas_limit intrinsic gas.
        // Blob fees are deducted in validateAgainstStateAndDeductCaller.

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
    /// - Rejects Type 4 (EIP-7702) transactions that are also CREATE transactions
    pub fn validateEip7702Tx(tx: *const context.TxEnv, spec: primitives.SpecId) !void {
        if (!primitives.isEnabledIn(spec, .prague)) return;

        // Only applies to transactions that carry an authorization list
        const auth_list = tx.authorization_list orelse return;

        // EIP-7702: Type 4 tx with authorization list cannot be CREATE
        if (tx.kind == .Create) {
            return ValidationError.Type4TxContractCreation;
        }

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

        // Blob transactions must carry at least one blob hash
        if (blob_hashes.items.len == 0) {
            return ValidationError.EmptyBlobList;
        }

        // EIP-7594 (Osaka): per-transaction blob count limit = 6 (separate from per-block limit)
        if (primitives.isEnabledIn(spec, .osaka)) {
            if (blob_hashes.items.len > primitives.MAX_BLOB_NUMBER_PER_TX) {
                return ValidationError.TooManyBlobs;
            }
        } else {
            // Blob count limit (EIP-7691: Prague increases max blobs from 6 to 9)
            const max_blobs = if (primitives.isEnabledIn(spec, .prague))
                primitives.MAX_BLOB_NUMBER_PER_BLOCK_PRAGUE
            else
                primitives.MAX_BLOB_NUMBER_PER_BLOCK;
            if (blob_hashes.items.len > max_blobs) {
                return ValidationError.TooManyBlobs;
            }
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

    /// Calculates the EIP-7623 floor gas exec-portion (tokens * 10).
    ///
    /// Returns only the exec-portion of floor gas (excludes 21000 base).
    /// Used in postExecution to enforce minimum exec gas spent.
    /// Token costs: 1 per zero byte, 4 per nonzero byte (EIP-7623 token definition).
    pub fn calculateFloorGas(tx: *const context.TxEnv, spec: primitives.SpecId) u64 {
        if (!primitives.isEnabledIn(spec, .prague)) {
            return 0;
        }

        // EIP-7623: tokens = sum(1 per zero byte, 4 per nonzero byte); floor_exec = tokens * 10
        var tokens: u64 = 0;
        if (tx.data) |data| {
            for (data.items) |byte| {
                if (byte == 0) {
                    tokens += FLOOR_ZERO_TOKEN_COST;
                } else {
                    tokens += FLOOR_NONZERO_TOKEN_COST;
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
    /// EIP-7702: gas refund accumulated during authorization list processing (preExecution).
    /// 25,000 (PER_EMPTY_ACCOUNT_COST) added for each valid authorization that sets code.
    /// Applied in postExecution with the standard 1/5 cap against total gas used.
    auth_refund: i64 = 0,
};

/// Validation errors
pub const ValidationError = error{
    InvalidChainId,
    GasLimitExceedsCap,
    TxGasLimitExceedsBlockLimit,
    PriorityFeeGreaterThanMaxFee,
    InsufficientGas,
    SenderHasCode,
    NonceMismatch,
    NonceIsMax,
    BalanceOverflow,
    BlobFeeOverflow,
    InsufficientBalance,
    GasPriceLessThanBaseFee,
    CallerLoadFailed,
    CreateInitcodeOverLimit,
    // EIP-4844 blob transaction errors
    EmptyBlobList,
    TooManyBlobs,
    InvalidBlobVersionedHash,
    BlobGasPriceTooLow,
    BlobCreateTransaction,
    // EIP-7702 set-code transaction errors
    EmptyAuthorizationList,
    Type4TxContractCreation,
};

test {
    _ = @import("validation_tests.zig");
}
