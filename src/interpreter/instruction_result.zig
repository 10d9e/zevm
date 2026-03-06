const std = @import("std");

/// Result of executing an EVM instruction.
///
/// This enum represents all possible outcomes when executing an instruction,
/// including successful execution, reverts, and various error conditions.
pub const InstructionResult = enum(u8) {
    /// Continue execution to the next instruction.
    continue_ = 0,
    /// Encountered a `STOP` opcode
    stop = 1,
    /// Return from the current call.
    @"return",
    /// Self-destruct the current contract.
    selfdestruct,

    // Revert Codes
    /// Revert the transaction.
    revert = 0x10,
    /// Exceeded maximum call depth.
    call_too_deep,
    /// Insufficient funds for transfer.
    out_of_funds,
    /// Revert if `CREATE`/`CREATE2` starts with `0xEF00`.
    create_init_code_starting_ef00,
    /// Invalid EVM Object Format (EOF) init code.
    invalid_eof_init_code,
    /// `ExtDelegateCall` calling a non EOF contract.
    invalid_ext_delegate_call_target,

    // Error Codes
    /// Out of gas error.
    out_of_gas = 0x20,
    /// Out of gas error encountered during memory expansion.
    memory_oog,
    /// The memory limit of the EVM has been exceeded.
    memory_limit_oog,
    /// Out of gas error encountered during the execution of a precompiled contract.
    precompile_oog,
    /// Out of gas error encountered while calling an invalid operand.
    invalid_operand_oog,
    /// Out of gas error encountered while checking for reentrancy sentry.
    reentrancy_sentry_oog,
    /// Unknown or invalid opcode.
    invalid_opcode,
    /// Invalid jump destination.
    invalid_jump,
    /// Invalid call destination.
    invalid_call,
    /// Invalid return data.
    invalid_return,
    /// Invalid create data.
    invalid_create,
    /// Invalid selfdestruct data.
    invalid_selfdestruct,
    /// Invalid log data.
    invalid_log,
    /// Invalid storage data.
    invalid_storage,
    /// Invalid balance data.
    invalid_balance,
    /// Invalid nonce data.
    invalid_nonce,
    /// Invalid code data.
    invalid_code,
    /// Invalid address data.
    invalid_address,
    /// Invalid data.
    invalid_data,
    /// Invalid gas data.
    invalid_gas,
    /// Invalid value data.
    invalid_value,
    /// Invalid depth data.
    invalid_depth,
    /// Invalid static data.
    invalid_static,
    /// Invalid access data.
    invalid_access,
    /// Invalid warmth data.
    invalid_warmth,
    /// Invalid cold data.
    invalid_cold,
    /// Invalid hot data.
    invalid_hot,
    /// Invalid touched data.
    invalid_touched,
    /// Invalid created data.
    invalid_created,
    /// Invalid destroyed data.
    invalid_destroyed,
    /// Invalid reverted data.
    invalid_reverted,
    /// Invalid committed data.
    invalid_committed,
    /// Invalid discarded data.
    invalid_discarded,
    /// Invalid finalized data.
    invalid_finalized,
    /// Invalid checkpoint data.
    invalid_checkpoint,
    /// Invalid revert data.
    invalid_revert,
    /// Invalid commit data.
    invalid_commit,
    /// Invalid transfer data.
    invalid_transfer,
    /// Invalid refund data.
    invalid_refund,
    /// Invalid cost data.
    invalid_cost,
    /// Invalid limit data.
    invalid_limit,
    /// Invalid cap data.
    invalid_cap,
    /// Invalid size data.
    invalid_size,
    /// Invalid length data.
    invalid_length,
    /// Invalid offset data.
    invalid_offset,
    /// Invalid index data.
    invalid_index,
    /// Invalid key data.
    invalid_key,
    /// Invalid hash data.
    invalid_hash,
    /// Invalid signature data.
    invalid_signature,
    /// Invalid authorization data.
    invalid_authorization,
    /// Invalid permission data.
    invalid_permission,
    /// Invalid authority data.
    invalid_authority,
    /// Invalid delegation data.
    invalid_delegation,
    /// Invalid proxy data.
    invalid_proxy,
    /// Invalid implementation data.
    invalid_implementation,
    /// Invalid interface data.
    invalid_interface,
    /// Invalid ABI data.
    invalid_abi,
    /// Invalid selector data.
    invalid_selector,
    /// Invalid calldata data.
    invalid_calldata,
    /// Invalid returndata data.
    invalid_returndata,
    /// Invalid event data.
    invalid_event,
    /// Invalid topic data.
    invalid_topic,
    /// Invalid logs data.
    invalid_logs,
    /// Invalid bloom data.
    invalid_bloom,
    /// Invalid receipt data.
    invalid_receipt,
    /// Invalid transaction data.
    invalid_transaction,
    /// Invalid block data.
    invalid_block,
    /// Invalid header data.
    invalid_header,
    /// Invalid body data.
    invalid_body,
    /// Invalid state data.
    invalid_state,
    /// Invalid account data.
    invalid_account,
    /// Invalid code hash data.
    invalid_code_hash,
    /// Invalid storage root data.
    invalid_storage_root,
    /// Invalid state root data.
    invalid_state_root,
    /// Invalid receipt root data.
    invalid_receipt_root,
    /// Invalid transactions root data.
    invalid_transactions_root,
    /// Invalid uncles hash data.
    invalid_uncles_hash,
    /// Invalid mix hash data.
    invalid_mix_hash,
    /// Invalid nonce value data.
    invalid_nonce_value,
    /// Invalid difficulty data.
    invalid_difficulty,
    /// Invalid timestamp data.
    invalid_timestamp,
    /// Invalid gas limit data.
    invalid_gas_limit,
    /// Invalid gas used data.
    invalid_gas_used,
    /// Invalid base fee data.
    invalid_base_fee,
    /// Invalid extra data data.
    invalid_extra_data,
    /// Invalid bloom filter data.
    invalid_bloom_filter,
    /// Invalid logs bloom data.
    invalid_logs_bloom,
    /// Invalid receipts bloom data.
    invalid_receipts_bloom,
    /// Invalid transactions bloom data.
    invalid_transactions_bloom,
    /// Invalid uncles bloom data.
    invalid_uncles_bloom,
    /// Invalid state bloom data.
    invalid_state_bloom,
    /// Invalid storage bloom data.
    invalid_storage_bloom,
    /// Invalid account bloom data.
    invalid_account_bloom,
    /// Invalid balance bloom data.
    invalid_balance_bloom,
    /// Invalid nonce bloom data.
    invalid_nonce_bloom,
    /// Invalid code bloom data.
    invalid_code_bloom,
    /// Invalid code hash bloom data.
    invalid_code_hash_bloom,
    /// Invalid storage root bloom data.
    invalid_storage_root_bloom,
    /// Invalid state root bloom data.
    invalid_state_root_bloom,
    /// Invalid receipt root bloom data.
    invalid_receipt_root_bloom,
    /// Invalid transactions root bloom data.
    invalid_transactions_root_bloom,
    /// Invalid uncles hash bloom data.
    invalid_uncles_hash_bloom,
    /// Invalid mix hash bloom data.
    invalid_mix_hash_bloom,
    /// Invalid nonce value bloom data.
    invalid_nonce_value_bloom,
    /// Invalid difficulty bloom data.
    invalid_difficulty_bloom,
    /// Invalid timestamp bloom data.
    invalid_timestamp_bloom,
    /// Invalid gas limit bloom data.
    invalid_gas_limit_bloom,
    /// Invalid gas used bloom data.
    invalid_gas_used_bloom,
    /// Invalid base fee bloom data.
    invalid_base_fee_bloom,
    /// Invalid extra data bloom data.
    invalid_extra_data_bloom,
    /// Stack underflow — not enough items on the stack.
    stack_underflow,
    /// Stack overflow — too many items on the stack.
    stack_overflow,

    /// Check if the result is a success
    pub fn isSuccess(self: InstructionResult) bool {
        return switch (self) {
            .stop, .@"return", .selfdestruct => true,
            else => false,
        };
    }

    /// Check if the result is a revert
    pub fn isRevert(self: InstructionResult) bool {
        return switch (self) {
            .revert, .call_too_deep, .out_of_funds, .create_init_code_starting_ef00, .invalid_eof_init_code, .invalid_ext_delegate_call_target => true,
            else => false,
        };
    }

    /// Check if the result is an error
    pub fn isError(self: InstructionResult) bool {
        return !self.isSuccess() and !self.isRevert() and self != .continue_;
    }

    /// Get the default result (stop)
    pub fn default() InstructionResult {
        return .stop;
    }
};
