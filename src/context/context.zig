const std = @import("std");
const primitives = @import("primitives");
const state = @import("state");
const bytecode = @import("bytecode");
const database = @import("database");
const BlockEnv = @import("block.zig").BlockEnv;
const TxEnv = @import("tx.zig").TxEnv;
const CfgEnv = @import("cfg.zig").CfgEnv;
const Journal = @import("journal.zig").Journal;
const LocalContext = @import("local.zig").LocalContext;

/// Context error type
pub const ContextError = enum {
    ok,
    database_error,
    execution_error,
    gas_error,
    stack_error,
    memory_error,
    invalid_opcode,
    invalid_jump,
    invalid_call,
    invalid_return,
    invalid_create,
    invalid_selfdestruct,
    invalid_log,
    invalid_storage,
    invalid_balance,
    invalid_nonce,
    invalid_code,
    invalid_address,
    invalid_data,
    invalid_gas,
    invalid_value,
    invalid_depth,
    invalid_static,
    invalid_access,
    invalid_warmth,
    invalid_cold,
    invalid_hot,
    invalid_touched,
    invalid_created,
    invalid_destroyed,
    invalid_reverted,
    invalid_committed,
    invalid_discarded,
    invalid_finalized,
    invalid_checkpoint,
    invalid_revert,
    invalid_commit,
    invalid_transfer,
    invalid_refund,
    invalid_cost,
    invalid_limit,
    invalid_cap,
    invalid_size,
    invalid_length,
    invalid_offset,
    invalid_index,
    invalid_key,
    invalid_hash,
    invalid_signature,
    invalid_authorization,
    invalid_permission,
    invalid_authority,
    invalid_delegation,
    invalid_proxy,
    invalid_implementation,
    invalid_interface,
    invalid_abi,
    invalid_selector,
    invalid_calldata,
    invalid_returndata,
    invalid_event,
    invalid_topic,
    invalid_logs,
    invalid_bloom,
    invalid_receipt,
    invalid_transaction,
    invalid_block,
    invalid_header,
    invalid_body,
    invalid_state,
    invalid_account,
    invalid_code_hash,
    invalid_storage_root,
    invalid_state_root,
    invalid_receipt_root,
    invalid_transactions_root,
    invalid_uncles_hash,
    invalid_mix_hash,
    invalid_nonce_value,
    invalid_difficulty,
    invalid_timestamp,
    invalid_gas_limit,
    invalid_gas_used,
    invalid_base_fee,
    invalid_extra_data,
    invalid_bloom_filter,
    invalid_logs_bloom,
    invalid_receipts_bloom,
    invalid_transactions_bloom,
    invalid_uncles_bloom,
    invalid_state_bloom,
    invalid_storage_bloom,
    invalid_account_bloom,
    invalid_balance_bloom,
    invalid_nonce_bloom,
    invalid_code_bloom,
    invalid_code_hash_bloom,
    invalid_storage_root_bloom,
    invalid_state_root_bloom,
    invalid_receipt_root_bloom,
    invalid_transactions_root_bloom,
    invalid_uncles_hash_bloom,
    invalid_mix_hash_bloom,
    invalid_nonce_value_bloom,
    invalid_difficulty_bloom,
    invalid_timestamp_bloom,
    invalid_gas_limit_bloom,
    invalid_gas_used_bloom,
    invalid_base_fee_bloom,
    invalid_extra_data_bloom,
};

/// EVM context contains data that EVM needs for execution.
pub const Context = struct {
    /// Block information.
    block: BlockEnv,
    /// Transaction information.
    tx: TxEnv,
    /// Configurations.
    cfg: CfgEnv,
    /// EVM State with journaling support and database.
    journaled_state: Journal(database.InMemoryDB),
    /// Inner context.
    chain: void,
    /// Local context that is filled by execution.
    local: LocalContext,
    /// Error that happened during execution.
    ctx_error: ContextError,

    pub fn new(database_param: database.InMemoryDB, spec: primitives.SpecId) Context {
        var journaled_state = Journal(database.InMemoryDB).new(database_param);
        journaled_state.setSpecId(spec);
        return .{
            .tx = TxEnv.default(),
            .block = BlockEnv.default(),
            .cfg = CfgEnv.newWithSpec(spec),
            .local = LocalContext.default(),
            .journaled_state = journaled_state,
            .chain = {},
            .ctx_error = ContextError.ok,
        };
    }

    /// Creates a new context with a new journal type. New journal needs to have the same database type.
    pub fn withNewJournal(self: Context, new_journal_param: anytype) Context {
        var new_journal = new_journal_param;
        new_journal.setSpecId(self.cfg.spec());
        return .{
            .tx = self.tx,
            .block = self.block,
            .cfg = self.cfg,
            .journaled_state = new_journal,
            .local = self.local,
            .chain = self.chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Creates a new context with a new database type.
    ///
    /// This will create a new [`Journal`] object.
    pub fn withDb(self: Context, database_param: anytype) Context {
        const spec = self.cfg.spec();
        var journaled_state = Journal.new(database_param);
        journaled_state.setSpecId(spec);
        return .{
            .tx = self.tx,
            .block = self.block,
            .cfg = self.cfg,
            .journaled_state = journaled_state,
            .local = self.local,
            .chain = self.chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Creates a new context with a new `DatabaseRef` type.
    pub fn withRefDb(self: Context, db_ref: anytype) Context {
        const spec = self.cfg.spec();
        var journaled_state = Journal.new(database.WrapDatabaseRef.new(db_ref));
        journaled_state.setSpecId(spec);
        return .{
            .tx = self.tx,
            .block = self.block,
            .cfg = self.cfg,
            .journaled_state = journaled_state,
            .local = self.local,
            .chain = self.chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Creates a new context with a new block type.
    pub fn withBlock(self: Context, block: BlockEnv) Context {
        return .{
            .tx = self.tx,
            .block = block,
            .cfg = self.cfg,
            .journaled_state = self.journaled_state,
            .local = self.local,
            .chain = self.chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Creates a new context with a new transaction type.
    pub fn withTx(self: Context, tx: TxEnv) Context {
        return .{
            .tx = tx,
            .block = self.block,
            .cfg = self.cfg,
            .journaled_state = self.journaled_state,
            .local = self.local,
            .chain = self.chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Creates a new context with a new chain type.
    pub fn withChain(self: Context, chain: anytype) Context {
        return .{
            .tx = self.tx,
            .block = self.block,
            .cfg = self.cfg,
            .journaled_state = self.journaled_state,
            .local = self.local,
            .chain = chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Creates a new context with a new chain type.
    pub fn withCfg(self: Context, cfg: CfgEnv) Context {
        var new_cfg = cfg;
        self.journaled_state.setSpecId(new_cfg.spec());
        return .{
            .tx = self.tx,
            .block = self.block,
            .cfg = new_cfg,
            .journaled_state = self.journaled_state,
            .local = self.local,
            .chain = self.chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Creates a new context with a new local context type.
    pub fn withLocal(self: Context, local: LocalContext) Context {
        return .{
            .tx = self.tx,
            .block = self.block,
            .cfg = self.cfg,
            .journaled_state = self.journaled_state,
            .local = local,
            .chain = self.chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Modifies the context configuration.
    pub fn modifyCfgChained(self: Context, f: fn (*CfgEnv) void) Context {
        var new_cfg = self.cfg;
        f(&new_cfg);
        self.journaled_state.setSpecId(new_cfg.spec());
        return .{
            .tx = self.tx,
            .block = self.block,
            .cfg = new_cfg,
            .journaled_state = self.journaled_state,
            .local = self.local,
            .chain = self.chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Modifies the context block.
    pub fn modifyBlockChained(self: Context, f: fn (*BlockEnv) void) Context {
        var new_block = self.block;
        f(&new_block);
        return .{
            .tx = self.tx,
            .block = new_block,
            .cfg = self.cfg,
            .journaled_state = self.journaled_state,
            .local = self.local,
            .chain = self.chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Modifies the context transaction.
    pub fn modifyTxChained(self: Context, f: fn (*TxEnv) void) Context {
        var new_tx = self.tx;
        f(&new_tx);
        return .{
            .tx = new_tx,
            .block = self.block,
            .cfg = self.cfg,
            .journaled_state = self.journaled_state,
            .local = self.local,
            .chain = self.chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Modifies the context chain.
    pub fn modifyChainChained(self: Context, f: fn (*@TypeOf(self.chain)) void) Context {
        var new_chain = self.chain;
        f(&new_chain);
        return .{
            .tx = self.tx,
            .block = self.block,
            .cfg = self.cfg,
            .journaled_state = self.journaled_state,
            .local = self.local,
            .chain = new_chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Modifies the context database.
    pub fn modifyDbChained(self: Context, f: fn (*@TypeOf(self.journaled_state.database)) void) Context {
        f(&self.journaled_state.database);
        return .{
            .tx = self.tx,
            .block = self.block,
            .cfg = self.cfg,
            .journaled_state = self.journaled_state,
            .local = self.local,
            .chain = self.chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Modifies the context journal.
    pub fn modifyJournalChained(self: Context, f: fn (*Journal) void) Context {
        f(&self.journaled_state);
        return .{
            .tx = self.tx,
            .block = self.block,
            .cfg = self.cfg,
            .journaled_state = self.journaled_state,
            .local = self.local,
            .chain = self.chain,
            .ctx_error = ContextError.ok,
        };
    }

    /// Modifies the context block.
    pub fn modifyBlock(self: *Context, f: fn (*BlockEnv) void) void {
        f(&self.block);
    }

    /// Modifies the context transaction.
    pub fn modifyTx(self: *Context, f: fn (*TxEnv) void) void {
        f(&self.tx);
    }

    /// Modifies the context configuration.
    pub fn modifyCfg(self: *Context, f: fn (*CfgEnv) void) void {
        f(&self.cfg);
        self.journaled_state.setSpecId(self.cfg.spec());
    }

    /// Modifies the context chain.
    pub fn modifyChain(self: *Context, f: fn (*@TypeOf(self.chain)) void) void {
        f(&self.chain);
    }

    /// Modifies the context database.
    pub fn modifyDb(self: *Context, f: fn (*@TypeOf(self.journaled_state.database)) void) void {
        f(&self.journaled_state.database);
    }

    /// Modifies the context journal.
    pub fn modifyJournal(self: *Context, f: fn (*Journal) void) void {
        f(&self.journaled_state);
    }

    /// Modifies the local context.
    pub fn modifyLocal(self: *Context, f: fn (*LocalContext) void) void {
        f(&self.local);
    }

    /// Set transaction
    pub fn setTx(self: *Context, tx: TxEnv) void {
        self.tx = tx;
    }

    /// Set block
    pub fn setBlock(self: *Context, block: BlockEnv) void {
        self.block = block;
    }

    /// Get all context components
    pub fn all(self: Context) struct { BlockEnv, TxEnv, CfgEnv, *const @TypeOf(self.journaled_state.database), Journal, @TypeOf(self.chain), LocalContext } {
        return .{
            self.block,
            self.tx,
            self.cfg,
            &self.journaled_state.database,
            self.journaled_state,
            self.chain,
            self.local,
        };
    }

    /// Get all context components mutably
    pub fn getAllMut(self: *Context) struct { BlockEnv, TxEnv, CfgEnv, *Journal, *@TypeOf(self.chain), *LocalContext } {
        return .{
            self.block,
            self.tx,
            self.cfg,
            &self.journaled_state,
            &self.chain,
            &self.local,
        };
    }

    /// Get error
    pub fn getError(self: *Context) *ContextError {
        return &self.ctx_error;
    }

    /// Get block
    pub fn getBlock(self: Context) BlockEnv {
        return self.block;
    }

    /// Get transaction
    pub fn getTx(self: Context) TxEnv {
        return self.tx;
    }

    /// Get configuration
    pub fn getCfg(self: Context) CfgEnv {
        return self.cfg;
    }

    /// Get database
    pub fn db(self: Context) *const @TypeOf(self.journaled_state.database) {
        return &self.journaled_state.database;
    }

    /// Get database mutably
    pub fn getDb(self: *Context) *@TypeOf(self.journaled_state.database) {
        return &self.journaled_state.database;
    }

    /// Get journal
    pub fn getJournal(self: Context) Journal {
        return self.journaled_state;
    }

    /// Get journal mutably
    pub fn getJournalMut(self: *Context) *Journal {
        return &self.journaled_state;
    }

    /// Get chain
    pub fn getChain(self: Context) @TypeOf(self.chain) {
        return self.chain;
    }

    /// Get chain mutably
    pub fn getChainMut(self: *Context) *@TypeOf(self.chain) {
        return &self.chain;
    }

    /// Get local context
    pub fn getLocal(self: Context) LocalContext {
        return self.local;
    }

    /// Get local context mutably
    pub fn getLocalMut(self: *Context) *LocalContext {
        return &self.local;
    }

    // Block methods

    pub fn basefee(self: Context) primitives.U256 {
        return primitives.U256.from(self.block.getBasefee());
    }

    pub fn blobGasprice(self: Context) primitives.U256 {
        return primitives.U256.from(self.block.blobExcessGasAndPrice().?.blobGasprice());
    }

    pub fn gasLimit(self: Context) primitives.U256 {
        return primitives.U256.from(self.block.getGasLimit());
    }

    pub fn difficulty(self: Context) primitives.U256 {
        return self.block.difficulty();
    }

    pub fn prevrandao(self: Context) ?primitives.U256 {
        return if (self.block.prevrandao()) |prev_randao| primitives.U256.fromBytes(prev_randao) else null;
    }

    pub fn blockNumber(self: Context) primitives.U256 {
        return self.block.number();
    }

    pub fn timestamp(self: Context) primitives.U256 {
        return self.block.timestamp();
    }

    pub fn beneficiary(self: Context) primitives.Address {
        return self.block.beneficiary();
    }

    pub fn chainId(self: Context) primitives.U256 {
        return primitives.U256.from(self.cfg.chainId());
    }

    // Transaction methods

    pub fn effectiveGasPrice(self: Context) primitives.U256 {
        const base_fee = self.block.getBasefee();
        return primitives.U256.fromU128(self.tx.effectiveGasPrice(base_fee));
    }

    pub fn caller(self: Context) primitives.Address {
        return self.tx.caller();
    }

    pub fn blobHash(self: Context, number: usize) ?primitives.U256 {
        const tx = self.tx;
        if (tx.txType() != @intFromEnum(TxEnv.TransactionType.Eip4844)) {
            return null;
        }
        const blob_hashes = tx.blobVersionedHashes();
        if (number < blob_hashes.len) {
            return primitives.U256.fromBytes(blob_hashes[number]);
        }
        return null;
    }

    // Config methods

    pub fn maxInitcodeSize(self: Context) usize {
        return self.cfg.maxInitcodeSize();
    }

    // Database methods

    pub fn blockHash(self: *Context, requested_number: u64) ?primitives.Hash {
        return self.journaled_state.database.blockHash(requested_number) catch {
            self.ctx_error = ContextError.database_error;
            return null;
        };
    }

    // Journal methods

    /// Gets the transient storage value of `address` at `index`.
    pub fn tload(self: *Context, address: primitives.Address, index: primitives.StorageKey) primitives.StorageValue {
        return self.journaled_state.tload(address, index);
    }

    /// Sets the transient storage value of `address` at `index`.
    pub fn tstore(self: *Context, address: primitives.Address, index: primitives.StorageKey, value: primitives.StorageValue) void {
        self.journaled_state.tstore(address, index, value);
    }

    /// Emits a log owned by `address` with given `LogData`.
    pub fn log(self: *Context, log_entry: primitives.Log) void {
        self.journaled_state.log(log_entry);
    }

    /// Marks `address` to be deleted, with funds transferred to `target`.
    pub fn selfdestruct(self: *Context, address: primitives.Address, target: primitives.Address) ?Journal.StateLoad(Journal.SelfDestructResult) {
        return self.journaled_state.selfdestruct(address, target) catch {
            self.ctx_error = ContextError.database_error;
            return null;
        };
    }

    pub fn sstoreSkipColdLoad(self: *Context, address: primitives.Address, key: primitives.StorageKey, value: primitives.StorageValue, skip_cold_load: bool) Journal.StateLoad(Journal.SStoreResult) {
        return self.journaled_state.sstoreSkipColdLoad(address, key, value, skip_cold_load) catch {
            self.ctx_error = ContextError.database_error;
            return Journal.StateLoad.new(Journal.SStoreResult{
                .original_value = @as(primitives.StorageValue, 0),
                .present_value = @as(primitives.StorageValue, 0),
                .new_value = value,
            }, false);
        };
    }

    pub fn sloadSkipColdLoad(self: *Context, address: primitives.Address, key: primitives.StorageKey, skip_cold_load: bool) Journal.StateLoad(primitives.StorageValue) {
        return self.journaled_state.sloadSkipColdLoad(address, key, skip_cold_load) catch {
            self.ctx_error = ContextError.database_error;
            return Journal.StateLoad.new(@as(primitives.StorageValue, 0), false);
        };
    }

    pub fn loadAccountInfoSkipColdLoad(self: *Context, address: primitives.Address, load_code: bool, skip_cold_load: bool) Journal.AccountInfoLoad {
        return self.journaled_state.loadAccountInfoSkipColdLoad(address, load_code, skip_cold_load) catch {
            self.ctx_error = ContextError.database_error;
            return Journal.AccountInfoLoad.new(&state.AccountInfo.default(), false, true);
        };
    }
};
