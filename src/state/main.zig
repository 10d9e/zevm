const std = @import("std");
const primitives = @import("primitives");
const bytecode = @import("bytecode");

/// Account and storage state management for the EVM.
/// Account information that contains balance, nonce, code hash and code
/// Code is set as optional.
pub const AccountInfo = struct {
    /// Account balance.
    balance: primitives.U256,
    /// Account nonce.
    nonce: u64,
    /// Hash of the raw bytes in code, or KECCAK_EMPTY.
    code_hash: primitives.Hash,
    /// Bytecode data associated with this account.
    /// If null, code_hash will be used to fetch it from the database, if code needs to be
    /// loaded from inside the EVM.
    /// By default, this is Some(Bytecode::default()).
    code: ?bytecode.Bytecode,

    const Self = @This();

    pub fn default() Self {
        return Self{
            .balance = @as(primitives.U256, 0),
            .nonce = 0,
            .code_hash = primitives.KECCAK_EMPTY,
            .code = bytecode.Bytecode.new(),
        };
    }

    /// Creates a new AccountInfo with the given fields.
    pub fn new(balance: primitives.U256, nonce: u64, code_hash: primitives.Hash, code: bytecode.Bytecode) Self {
        return Self{
            .balance = balance,
            .nonce = nonce,
            .code_hash = code_hash,
            .code = code,
        };
    }

    /// Creates a new AccountInfo with the given code.
    /// Note: As code hash is calculated with Bytecode::hashSlow there will be performance penalty if used frequently.
    pub fn withCode(self: Self, code: bytecode.Bytecode) Self {
        return Self{
            .balance = self.balance,
            .nonce = self.nonce,
            .code_hash = code.hashSlow(),
            .code = code,
        };
    }

    /// Creates a new AccountInfo with the given code hash.
    /// Note: Resets code to null. Not guaranteed to maintain invariant code and code_hash.
    pub fn withCodeHash(self: Self, code_hash: primitives.Hash) Self {
        return Self{
            .balance = self.balance,
            .nonce = self.nonce,
            .code_hash = code_hash,
            .code = null,
        };
    }

    /// Creates a new AccountInfo with the given code and code hash.
    pub fn withCodeAndHash(self: Self, code: bytecode.Bytecode, code_hash: primitives.Hash) Self {
        std.debug.assert(std.mem.eql(u8, &code.hashSlow(), &code_hash));
        return Self{
            .balance = self.balance,
            .nonce = self.nonce,
            .code_hash = code_hash,
            .code = code,
        };
    }

    /// Creates a new AccountInfo with the given balance.
    pub fn withBalance(self: Self, balance: primitives.U256) Self {
        var result = self;
        result.balance = balance;
        return result;
    }

    /// Creates a new AccountInfo with the given nonce.
    pub fn withNonce(self: Self, nonce: u64) Self {
        var result = self;
        result.nonce = nonce;
        return result;
    }

    /// Sets the AccountInfo balance.
    pub fn setBalance(self: *Self, balance: primitives.U256) void {
        self.balance = balance;
    }

    /// Sets the AccountInfo nonce.
    pub fn setNonce(self: *Self, nonce: u64) void {
        self.nonce = nonce;
    }

    /// Sets the AccountInfo code_hash and clears any cached bytecode.
    pub fn setCodeHash(self: *Self, code_hash: primitives.Hash) void {
        self.code = null;
        self.code_hash = code_hash;
    }

    /// Replaces the AccountInfo bytecode and recalculates code_hash.
    pub fn setCode(self: *Self, code: bytecode.Bytecode) void {
        self.code_hash = code.hashSlow();
        self.code = code;
    }

    /// Sets the bytecode and its hash.
    pub fn setCodeAndHash(self: *Self, code: bytecode.Bytecode, code_hash: primitives.Hash) void {
        self.code_hash = code_hash;
        self.code = code;
    }

    /// Returns a copy of this account with the Bytecode removed.
    pub fn copyWithoutCode(self: Self) Self {
        return Self{
            .balance = self.balance,
            .nonce = self.nonce,
            .code_hash = self.code_hash,
            .code = null,
        };
    }

    /// Strips the Bytecode from this account and drop it.
    pub fn withoutCode(self: Self) Self {
        var result = self;
        result.code = null;
        return result;
    }

    /// Returns if an account is empty.
    /// An account is empty if the following conditions are met:
    /// - code hash is zero or set to the Keccak256 hash of the empty string ""
    /// - balance is zero
    /// - nonce is zero
    pub fn isEmpty(self: Self) bool {
        const code_empty = self.isEmptyCodeHash() or self.code_hash[0] == 0;
        return code_empty and self.balance == 0 and self.nonce == 0;
    }

    /// Returns true if the account is not empty.
    pub fn exists(self: Self) bool {
        return !self.isEmpty();
    }

    /// Returns true if account has no nonce and code.
    pub fn hasNoCodeAndNonce(self: Self) bool {
        return self.isEmptyCodeHash() and self.nonce == 0;
    }

    /// Returns bytecode hash associated with this account.
    /// If account does not have code, it returns KECCAK_EMPTY hash.
    pub fn codeHash(self: Self) primitives.Hash {
        return self.code_hash;
    }

    /// Returns true if the code hash is the Keccak256 hash of the empty string "".
    pub fn isEmptyCodeHash(self: Self) bool {
        return std.mem.eql(u8, &self.code_hash, &primitives.KECCAK_EMPTY);
    }

    /// Takes bytecode from account.
    /// Code will be set to null.
    pub fn takeBytecode(self: *Self) ?bytecode.Bytecode {
        const result = self.code;
        self.code = null;
        return result;
    }

    /// Initializes an AccountInfo with the given balance, setting all other fields to their default values.
    pub fn fromBalance(balance: primitives.U256) Self {
        return Self{
            .balance = balance,
            .nonce = 0,
            .code_hash = primitives.KECCAK_EMPTY,
            .code = bytecode.Bytecode.new(),
        };
    }

    /// Initializes an AccountInfo with the given bytecode, setting its balance to zero, its
    /// nonce to 1, and calculating the code hash from the given bytecode.
    pub fn fromBytecode(bytecode_val: bytecode.Bytecode) Self {
        const hash = bytecode_val.hashSlow();
        return Self{
            .balance = @as(primitives.U256, 0),
            .nonce = 1,
            .code = bytecode_val,
            .code_hash = hash,
        };
    }
};

/// Account status flags
pub const AccountStatus = packed struct {
    /// When account is newly created we will not access database to fetch storage values.
    created: bool = false,
    /// When accounts gets loaded this flag is set to false. Create will always be true if CreatedLocal is true.
    created_local: bool = false,
    /// If account is marked for self destruction.
    self_destructed: bool = false,
    /// If account is marked for self destruction.
    self_destructed_local: bool = false,
    /// Only when account is marked as touched we will save it to database.
    /// Additionally first touch on empty existing account (After EIP-161) will mark it
    /// for removal from state after transaction execution.
    touched: bool = false,
    /// used only for pre spurious dragon hardforks where existing and empty were two separate states.
    /// it became same state after EIP-161: State trie clearing
    loaded_as_not_existing: bool = false,
    /// used to mark account as cold.
    /// It is used only in local scope and it is reset on account loading.
    cold: bool = false,
    /// Reserved for future use
    _reserved: bool = false,

    pub fn empty() AccountStatus {
        return AccountStatus{};
    }

    /// Returns true if the account status is touched.
    pub fn isTouched(self: AccountStatus) bool {
        return self.touched;
    }

    /// Returns true if the account status contains the given flag.
    pub fn contains(self: AccountStatus, other: AccountStatus) bool {
        return (self.touched and other.touched) or
            (self.created and other.created) or
            (self.created_local and other.created_local) or
            (self.self_destructed and other.self_destructed) or
            (self.self_destructed_local and other.self_destructed_local) or
            (self.loaded_as_not_existing and other.loaded_as_not_existing) or
            (self.cold and other.cold);
    }

    /// Sets the touched flag
    pub fn setTouched(self: *AccountStatus) void {
        self.touched = true;
    }

    /// Clears the touched flag
    pub fn clearTouched(self: *AccountStatus) void {
        self.touched = false;
    }

    /// Sets the created flag
    pub fn setCreated(self: *AccountStatus) void {
        self.created = true;
    }

    /// Clears the created flag
    pub fn clearCreated(self: *AccountStatus) void {
        self.created = false;
    }

    /// Sets the created local flag
    pub fn setCreatedLocal(self: *AccountStatus) void {
        self.created_local = true;
    }

    /// Clears the created local flag
    pub fn clearCreatedLocal(self: *AccountStatus) void {
        self.created_local = false;
    }

    /// Sets the self destructed flag
    pub fn setSelfDestructed(self: *AccountStatus) void {
        self.self_destructed = true;
    }

    /// Clears the self destructed flag
    pub fn clearSelfDestructed(self: *AccountStatus) void {
        self.self_destructed = false;
    }

    /// Sets the self destructed local flag
    pub fn setSelfDestructedLocal(self: *AccountStatus) void {
        self.self_destructed_local = true;
    }

    /// Clears the self destructed local flag
    pub fn clearSelfDestructedLocal(self: *AccountStatus) void {
        self.self_destructed_local = false;
    }

    /// Sets the loaded as not existing flag
    pub fn setLoadedAsNotExisting(self: *AccountStatus) void {
        self.loaded_as_not_existing = true;
    }

    /// Clears the loaded as not existing flag
    pub fn clearLoadedAsNotExisting(self: *AccountStatus) void {
        self.loaded_as_not_existing = false;
    }

    /// Sets the cold flag
    pub fn setCold(self: *AccountStatus) void {
        self.cold = true;
    }

    /// Clears the cold flag
    pub fn clearCold(self: *AccountStatus) void {
        self.cold = false;
    }
};

/// This type keeps track of the current value of a storage slot.
pub const EvmStorageSlot = struct {
    /// Original value of the storage slot
    original_value: primitives.StorageValue,
    /// Present value of the storage slot
    present_value: primitives.StorageValue,
    /// Transaction id, used to track when storage slot was made warm.
    transaction_id: usize,
    /// Represents if the storage slot is cold
    is_cold: bool,

    const Self = @This();

    /// Creates a new _unchanged_ EvmStorageSlot for the given value.
    pub fn new(original: primitives.StorageValue, transaction_id: usize) Self {
        return Self{
            .original_value = original,
            .present_value = original,
            .transaction_id = transaction_id,
            .is_cold = false,
        };
    }

    /// Creates a new _changed_ EvmStorageSlot.
    pub fn newChanged(original_value: primitives.StorageValue, present_value: primitives.StorageValue, transaction_id: usize) Self {
        return Self{
            .original_value = original_value,
            .present_value = present_value,
            .transaction_id = transaction_id,
            .is_cold = false,
        };
    }

    /// Returns true if the present value differs from the original value.
    pub fn isChanged(self: Self) bool {
        return self.original_value != self.present_value;
    }

    /// Returns the original value of the storage slot.
    pub fn originalValue(self: Self) primitives.StorageValue {
        return self.original_value;
    }

    /// Returns the current value of the storage slot.
    pub fn presentValue(self: Self) primitives.StorageValue {
        return self.present_value;
    }

    /// Marks the storage slot as cold. Does not change transaction_id.
    pub fn markCold(self: *Self) void {
        self.is_cold = true;
    }

    /// Is storage slot cold for given transaction id.
    pub fn isColdTransactionId(self: Self, transaction_id: usize) bool {
        return self.transaction_id != transaction_id or self.is_cold;
    }

    /// Marks the storage slot as warm and sets transaction_id to the given value
    /// Returns false if old transition_id is different from given id or in case they are same return Self::is_cold value.
    pub fn markWarmWithTransactionId(self: *Self, transaction_id: usize) bool {
        const was_cold = self.isColdTransactionId(transaction_id);
        self.transaction_id = transaction_id;
        self.is_cold = false;
        return was_cold;
    }
};

/// Account type used inside Journal to track changes to state.
pub const Account = struct {
    /// Balance, nonce, and code
    info: AccountInfo,
    /// Transaction id, used to track when account was touched/loaded into journal.
    transaction_id: usize,
    /// Storage cache
    storage: std.AutoHashMap(primitives.StorageKey, EvmStorageSlot),
    /// Account status flags
    status: AccountStatus,

    const Self = @This();

    pub fn default() Self {
        return Self{
            .info = AccountInfo.default(),
            .transaction_id = 0,
            .storage = std.AutoHashMap(primitives.StorageKey, EvmStorageSlot).init(std.heap.page_allocator),
            .status = AccountStatus.empty(),
        };
    }

    /// Creates new account and mark it as non existing.
    pub fn newNotExisting(transaction_id: usize) Self {
        return Self{
            .info = AccountInfo.default(),
            .storage = std.AutoHashMap(primitives.StorageKey, EvmStorageSlot).init(std.heap.page_allocator),
            .transaction_id = transaction_id,
            .status = AccountStatus{ .loaded_as_not_existing = true },
        };
    }

    /// Make changes to the caller account.
    /// It marks the account as touched, changes the balance and bumps the nonce if is_call is true.
    /// Returns the old balance.
    pub fn callerInitialModification(self: *Self, new_balance: primitives.U256, is_call: bool) primitives.U256 {
        // Touch account so we know it is changed.
        self.markTouch();

        if (is_call) {
            // Nonce is already checked
            self.info.nonce = self.info.nonce + 1;
        }

        const old_balance = self.info.balance;
        self.info.balance = new_balance;
        return old_balance;
    }

    /// Checks if account is empty and check if empty state before spurious dragon hardfork.
    pub fn stateClearAwareIsEmpty(self: Self, spec: primitives.SpecId) bool {
        if (primitives.isEnabledIn(spec, .spurious_dragon)) {
            return self.isEmpty();
        } else {
            return self.isLoadedAsNotExistingNotTouched();
        }
    }

    /// Marks the account as self destructed.
    pub fn markSelfdestruct(self: *Self) void {
        self.status.setSelfDestructed();
    }

    /// Unmarks the account as self destructed.
    pub fn unmarkSelfdestruct(self: *Self) void {
        self.status.clearSelfDestructed();
    }

    /// Is account marked for self destruct.
    pub fn isSelfdestructed(self: Self) bool {
        return self.status.self_destructed;
    }

    /// Marks the account as touched
    pub fn markTouch(self: *Self) void {
        self.status.setTouched();
    }

    /// Unmarks the touch flag.
    pub fn unmarkTouch(self: *Self) void {
        self.status.clearTouched();
    }

    /// If account status is marked as touched.
    pub fn isTouched(self: Self) bool {
        return self.status.isTouched();
    }

    /// Marks the account as newly created.
    pub fn markCreated(self: *Self) void {
        self.status.setCreated();
    }

    /// Unmarks the created flag.
    pub fn unmarkCreated(self: *Self) void {
        self.status.clearCreated();
    }

    /// Marks the account as cold.
    pub fn markCold(self: *Self) void {
        self.status.setCold();
    }

    /// Is account warm for given transaction id.
    pub fn isColdTransactionId(self: Self, transaction_id: usize) bool {
        return self.transaction_id != transaction_id or self.status.cold;
    }

    /// Marks the account as warm and return true if it was previously cold.
    pub fn markWarmWithTransactionId(self: *Self, transaction_id: usize) bool {
        const was_cold = self.isColdTransactionId(transaction_id);
        self.status.clearCold();
        self.transaction_id = transaction_id;
        return was_cold;
    }

    /// Is account locally created
    pub fn isCreatedLocally(self: Self) bool {
        return self.status.created_local;
    }

    /// Is account locally selfdestructed
    pub fn isSelfdestructedLocally(self: Self) bool {
        return self.status.self_destructed_local;
    }

    /// Selfdestruct the account by clearing its storage and resetting its account info
    pub fn selfdestruct(self: *Self) void {
        self.storage.clearAndFree();
        self.info = AccountInfo.default();
    }

    /// Mark account as locally created and mark global created flag.
    /// Returns true if it is created globally for first time.
    pub fn markCreatedLocally(self: *Self) bool {
        self.status.setCreatedLocal();
        const is_created_globally = !self.status.created;
        self.status.setCreated();
        return is_created_globally;
    }

    /// Unmark account as locally created
    pub fn unmarkCreatedLocally(self: *Self) void {
        self.status.clearCreatedLocal();
    }

    /// Mark account as locally and globally selfdestructed
    pub fn markSelfdestructedLocally(self: *Self) bool {
        self.status.setSelfDestructedLocal();
        const is_global_selfdestructed = !self.status.self_destructed;
        self.status.setSelfDestructed();
        return is_global_selfdestructed;
    }

    /// Unmark account as locally selfdestructed
    pub fn unmarkSelfdestructedLocally(self: *Self) void {
        self.status.clearSelfDestructedLocal();
    }

    /// Is account loaded as not existing from database.
    /// This is needed for pre spurious dragon hardforks where
    /// existing and empty were two separate states.
    pub fn isLoadedAsNotExisting(self: Self) bool {
        return self.status.loaded_as_not_existing;
    }

    /// Is account loaded as not existing from database and not touched.
    pub fn isLoadedAsNotExistingNotTouched(self: Self) bool {
        return self.isLoadedAsNotExisting() and !self.isTouched();
    }

    /// Is account newly created in this transaction.
    pub fn isCreated(self: Self) bool {
        return self.status.created;
    }

    /// Is account empty, check if nonce and balance are zero and code is empty.
    pub fn isEmpty(self: Self) bool {
        return self.info.isEmpty();
    }

    /// Sets account info and returns self for method chaining.
    pub fn withInfo(self: Self, info: AccountInfo) Self {
        var result = self;
        result.info = info;
        return result;
    }

    /// Marks the account as self destructed and returns self for method chaining.
    pub fn withSelfdestructMark(self: Self) Self {
        var result = self;
        result.markSelfdestruct();
        return result;
    }

    /// Marks the account as touched and returns self for method chaining.
    pub fn withTouchedMark(self: Self) Self {
        var result = self;
        result.markTouch();
        return result;
    }

    /// Marks the account as newly created and returns self for method chaining.
    pub fn withCreatedMark(self: Self) Self {
        var result = self;
        result.markCreated();
        return result;
    }

    /// Marks the account as cold and returns self for method chaining.
    pub fn withColdMark(self: Self) Self {
        var result = self;
        result.markCold();
        return result;
    }

    /// Marks the account as warm (not cold) and returns self for method chaining.
    /// Also returns whether the account was previously cold.
    pub fn withWarmMark(self: Self, transaction_id: usize) struct { Self, bool } {
        var result = self;
        const was_cold = result.markWarmWithTransactionId(transaction_id);
        return .{ result, was_cold };
    }

    /// Variant of withWarmMark that doesn't return the previous state.
    pub fn withWarm(self: Self, transaction_id: usize) Self {
        var result = self;
        _ = result.markWarmWithTransactionId(transaction_id);
        return result;
    }
};

/// EVM State is a mapping from addresses to accounts.
pub const EvmState = std.AutoHashMap(primitives.Address, Account);

/// Structure used for EIP-1153 transient storage
pub const TransientStorage = std.AutoHashMap(struct { primitives.Address, primitives.StorageKey }, primitives.StorageValue);

/// An account's Storage is a mapping from 256-bit integer keys to EvmStorageSlots.
pub const EvmStorage = std.AutoHashMap(primitives.StorageKey, EvmStorageSlot);

/// Test module for state
pub const testing = struct {
    pub fn testAccountInfo() !void {
        const account = AccountInfo.default();
        try std.testing.expect(account.isEmpty());
        try std.testing.expect(!account.exists());
        try std.testing.expect(account.hasNoCodeAndNonce());
    }

    pub fn testAccountStatus() !void {
        var status = AccountStatus.empty();
        try std.testing.expect(!status.isTouched());

        status.setTouched();
        try std.testing.expect(status.isTouched());

        status.clearTouched();
        try std.testing.expect(!status.isTouched());
    }

    pub fn testEvmStorageSlot() !void {
        const slot = EvmStorageSlot.new(@as(primitives.U256, 100), 0);
        try std.testing.expectEqual(@as(primitives.U256, 100), slot.originalValue());
        try std.testing.expectEqual(@as(primitives.U256, 100), slot.presentValue());
        try std.testing.expect(!slot.isChanged());

        var slot_mut = slot;
        slot_mut.present_value = @as(primitives.U256, 200);
        try std.testing.expect(slot_mut.isChanged());
    }

    pub fn testAccount() !void {
        var account = Account.default();
        try std.testing.expect(account.isEmpty());
        try std.testing.expect(!account.isTouched());
        try std.testing.expect(!account.isSelfdestructed());

        account.markTouch();
        try std.testing.expect(account.isTouched());

        account.markSelfdestruct();
        try std.testing.expect(account.isSelfdestructed());

        account.unmarkSelfdestruct();
        try std.testing.expect(!account.isSelfdestructed());
    }
};
