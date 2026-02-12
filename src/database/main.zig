const std = @import("std");
const primitives = @import("primitives");
const state = @import("state");
const bytecode = @import("bytecode");

/// Database interface and implementations for the EVM.
/// Address with all 0xff..ff in it. Used for testing.
pub const FFADDRESS: primitives.Address = [_]u8{0xff} ** 20;
/// BENCH_TARGET address
pub const BENCH_TARGET: primitives.Address = FFADDRESS;
/// Common test balance used for benchmark addresses
pub const TEST_BALANCE: primitives.U256 = primitives.U256{10_000_000_000_000_000};
/// BENCH_TARGET_BALANCE balance
pub const BENCH_TARGET_BALANCE: primitives.U256 = TEST_BALANCE;
/// Address with all 0xee..ee in it. Used for testing.
pub const EEADDRESS: primitives.Address = [_]u8{0xee} ** 20;
/// BENCH_CALLER address
pub const BENCH_CALLER: primitives.Address = EEADDRESS;
/// BENCH_CALLER_BALANCE balance
pub const BENCH_CALLER_BALANCE: primitives.U256 = TEST_BALANCE;

/// Database error marker
pub fn DBErrorMarker(comptime T: type) type {
    return struct {
        const Self = @This();
        pub fn isDBError(_: T) bool {
            return true;
        }
    };
}

/// EVM database interface.
pub fn Database(comptime Self: type) type {
    return struct {
        const DatabaseTrait = @This();

        /// Gets basic account information.
        pub fn basic(self: *Self, address: primitives.Address) !?state.AccountInfo {
            return self.basic(address);
        }

        /// Gets account code by its hash.
        pub fn codeByHash(self: *Self, code_hash: primitives.Hash) !bytecode.Bytecode {
            return self.codeByHash(code_hash);
        }

        /// Gets storage value of address at index.
        pub fn storage(self: *Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
            return self.storage_map(address, index);
        }

        /// Gets block hash by block number.
        pub fn blockHash(self: *Self, number: u64) !primitives.Hash {
            return self.blockHash(number);
        }
    };
}

/// EVM database commit interface.
pub fn DatabaseCommit(comptime Self: type) type {
    return struct {
        const DatabaseCommitTrait = @This();

        /// Commit changes to the database.
        pub fn commit(self: *Self, changes: std.HashMap(primitives.Address, state.Account, std.hash_map.default_hash_fn(primitives.Address), std.hash_map.default_eql_fn(primitives.Address))) void {
            return self.commit(changes);
        }
    };
}

/// EVM database interface with immutable reference.
/// Contains the same methods as Database, but with immutable receivers instead of mutable ones.
pub fn DatabaseRef(comptime Self: type) type {
    return struct {
        const DatabaseRefTrait = @This();

        /// Gets basic account information.
        pub fn basicRef(self: Self, address: primitives.Address) !?state.AccountInfo {
            return self.basicRef(address);
        }

        /// Gets account code by its hash.
        pub fn codeByHashRef(self: Self, code_hash: primitives.Hash) !bytecode.Bytecode {
            return self.codeByHashRef(code_hash);
        }

        /// Gets storage value of address at index.
        pub fn storageRef(self: Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
            return self.storage_mapRef(address, index);
        }

        /// Gets block hash by block number.
        pub fn blockHashRef(self: Self, number: u64) !primitives.Hash {
            return self.blockHashRef(number);
        }
    };
}

/// Wraps a DatabaseRef to provide a Database implementation.
pub fn WrapDatabaseRef(comptime T: type) type {
    return struct {
        inner: T,

        const Self = @This();

        pub fn init(inner: T) Self {
            return Self{ .inner = inner };
        }

        pub fn basic(self: *Self, address: primitives.Address) !?state.AccountInfo {
            return self.inner.basicRef(address);
        }

        pub fn codeByHash(self: *Self, code_hash: primitives.Hash) !bytecode.Bytecode {
            return self.inner.codeByHashRef(code_hash);
        }

        pub fn storage(self: *Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
            return self.inner.storageRef(address, index);
        }

        pub fn blockHash(self: *Self, number: u64) !primitives.Hash {
            return self.inner.blockHashRef(number);
        }

        pub fn basicRef(self: Self, address: primitives.Address) !?state.AccountInfo {
            return self.inner.basicRef(address);
        }

        pub fn codeByHashRef(self: Self, code_hash: primitives.Hash) !bytecode.Bytecode {
            return self.inner.codeByHashRef(code_hash);
        }

        pub fn storageRef(self: Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
            return self.inner.storageRef(address, index);
        }

        pub fn blockHashRef(self: Self, number: u64) !primitives.Hash {
            return self.inner.blockHashRef(number);
        }
    };
}

/// Empty database implementation for testing and development.
pub const EmptyDB = struct {
    const Self = @This();

    pub fn basic(self: *Self, address: primitives.Address) !?state.AccountInfo {
        _ = self;
        _ = address;
        return null;
    }

    pub fn codeByHash(self: *Self, code_hash: primitives.Hash) !bytecode.Bytecode {
        _ = self;
        _ = code_hash;
        return bytecode.Bytecode.new();
    }

    pub fn storage(self: *Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
        _ = self;
        _ = address;
        _ = index;
        return primitives.U256.ZERO;
    }

    pub fn blockHash(self: *Self, number: u64) !primitives.Hash {
        _ = self;
        _ = number;
        return [_]u8{0} ** 32;
    }

    pub fn basicRef(self: Self, address: primitives.Address) !?state.AccountInfo {
        _ = self;
        _ = address;
        return null;
    }

    pub fn codeByHashRef(self: Self, code_hash: primitives.Hash) !bytecode.Bytecode {
        _ = self;
        _ = code_hash;
        return bytecode.Bytecode.new();
    }

    pub fn storageRef(self: Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
        _ = self;
        _ = address;
        _ = index;
        return primitives.U256.ZERO;
    }

    pub fn blockHashRef(self: Self, number: u64) !primitives.Hash {
        _ = self;
        _ = number;
        return [_]u8{0} ** 32;
    }
};

/// Storage key context for HashMap
const StorageKeyContext = struct {
    pub fn hash(ctx: @This(), key: struct { primitives.Address, primitives.StorageKey }) u64 {
        _ = ctx;
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, key[0]);
        std.hash.autoHash(&hasher, key[1]);
        return hasher.final();
    }
    pub fn eql(ctx: @This(), a: struct { primitives.Address, primitives.StorageKey }, b: struct { primitives.Address, primitives.StorageKey }) bool {
        _ = ctx;
        return std.mem.eql(u8, &a[0], &b[0]) and a[1].eql(b[1]);
    }
};

/// In-memory database implementation.
pub const InMemoryDB = struct {
    accounts: std.AutoHashMap(primitives.Address, state.AccountInfo),
    code: std.AutoHashMap(primitives.Hash, bytecode.Bytecode),
    storage_map: std.HashMap(struct { primitives.Address, primitives.StorageKey }, primitives.StorageValue, StorageKeyContext, std.hash_map.default_max_load_percentage),
    block_hashes: std.AutoHashMap(u64, primitives.Hash),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .accounts = std.AutoHashMap(primitives.Address, state.AccountInfo).init(allocator),
            .code = std.AutoHashMap(primitives.Hash, bytecode.Bytecode).init(allocator),
            .storage_map = std.HashMap(struct { primitives.Address, primitives.StorageKey }, primitives.StorageValue, StorageKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .block_hashes = std.AutoHashMap(u64, primitives.Hash).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.accounts.deinit();
        self.code.deinit();
        self.storage_map.deinit();
        self.block_hashes.deinit();
    }

    pub fn basic(self: *Self, address: primitives.Address) !?state.AccountInfo {
        return self.accounts.get(address);
    }

    pub fn codeByHash(self: *Self, code_hash: primitives.Hash) !bytecode.Bytecode {
        return self.code.get(code_hash) orelse bytecode.Bytecode.new();
    }

    pub fn storage(self: *Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
        return self.getStorage(address, index);
    }

    pub fn getStorage(self: *Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
        return self.storage_map.get(.{ address, index }) orelse primitives.U256.ZERO;
    }

    pub fn blockHash(self: *Self, number: u64) !primitives.Hash {
        return self.block_hashes.get(number) orelse [_]u8{0} ** 32;
    }

    pub fn basicRef(self: Self, address: primitives.Address) !?state.AccountInfo {
        return self.accounts.get(address);
    }

    pub fn codeByHashRef(self: Self, code_hash: primitives.Hash) !bytecode.Bytecode {
        return self.code.get(code_hash) orelse bytecode.Bytecode.new();
    }

    pub fn storageRef(self: Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
        return self.storage_map.get(.{ address, index }) orelse primitives.U256.ZERO;
    }

    pub fn blockHashRef(self: Self, number: u64) !primitives.Hash {
        return self.block_hashes.get(number) orelse [_]u8{0} ** 32;
    }

    pub fn commit(self: *Self, changes: std.HashMap(primitives.Address, state.Account, std.hash_map.default_hash_fn(primitives.Address), std.hash_map.default_eql_fn(primitives.Address))) void {
        var iterator = changes.iterator();
        while (iterator.next()) |entry| {
            const address = entry.key_ptr.*;
            const account = entry.value_ptr.*;

            // Update account info
            self.accounts.put(address, account.info) catch return;

            // Update storage
            var storage_iterator = account.storage.iterator();
            while (storage_iterator.next()) |storage_entry| {
                const key = storage_entry.key_ptr.*;
                const slot = storage_entry.value_ptr.*;
                self.storage_map.put(.{ address, key }, slot.presentValue()) catch return;
            }
        }
    }

    /// Insert an account into the database
    pub fn insertAccount(self: *Self, address: primitives.Address, account_info: state.AccountInfo) !void {
        try self.accounts.put(address, account_info);
    }

    /// Insert code into the database
    pub fn insertCode(self: *Self, code_hash: primitives.Hash, code: bytecode.Bytecode) !void {
        try self.code.put(code_hash, code);
    }

    /// Insert storage value into the database
    pub fn insertStorage(self: *Self, address: primitives.Address, key: primitives.StorageKey, value: primitives.StorageValue) !void {
        try self.storage_map.put(.{ address, key }, value);
    }

    /// Insert block hash into the database
    pub fn insertBlockHash(self: *Self, number: u64, hash: primitives.Hash) !void {
        try self.block_hashes.put(number, hash);
    }
};

/// State management and tracking structures
pub const State = struct {
    accounts: std.AutoHashMap(primitives.Address, state.Account),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .accounts = std.AutoHashMap(primitives.Address, state.Account).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.accounts.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.storage.deinit();
        }
        self.accounts.deinit();
    }

    /// Get account from state
    pub fn getAccount(self: *Self, address: primitives.Address) ?*state.Account {
        return self.accounts.getPtr(address);
    }

    /// Insert or update account in state
    pub fn insertAccount(self: *Self, address: primitives.Address, account: state.Account) !void {
        try self.accounts.put(address, account);
    }

    /// Remove account from state
    pub fn removeAccount(self: *Self, address: primitives.Address) ?state.Account {
        if (self.accounts.fetchRemove(address)) |kv| {
            return kv.value;
        }
        return null;
    }

    /// Get all accounts
    pub fn getAccounts(self: Self) std.AutoHashMap(primitives.Address, state.Account) {
        return self.accounts;
    }
};

/// Test module for database
pub const testing = struct {
    pub fn testEmptyDB() !void {
        var db = EmptyDB{};

        const address: primitives.Address = [_]u8{0x01} ** 20;
        const account = try db.basic(address);
        try std.testing.expect(account == null);

        const code_hash: primitives.Hash = [_]u8{0x02} ** 32;
        const code = try db.codeByHash(code_hash);
        try std.testing.expect(code.isEmpty());

        const storage_value = try db.storage(address, primitives.U256.ZERO);
        try std.testing.expect(storage_value.eql(primitives.U256.ZERO));

        const block_hash = try db.blockHash(1);
        try std.testing.expectEqual([_]u8{0} ** 32, block_hash);
    }

    pub fn testInMemoryDB() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var db = InMemoryDB.init(allocator);
        defer db.deinit();

        const address: primitives.Address = [_]u8{0x01} ** 20;
        const account_info = state.AccountInfo.fromBalance(primitives.U256.from(1000));

        try db.insertAccount(address, account_info);

        const retrieved_account = try db.basic(address);
        try std.testing.expect(retrieved_account != null);
        try std.testing.expect(retrieved_account.?.balance.eql(primitives.U256.from(1000)));

        const code_hash: primitives.Hash = [_]u8{0x02} ** 32;
        const code = bytecode.Bytecode.new();
        try db.insertCode(code_hash, code);

        const retrieved_code = try db.codeByHash(code_hash);
        try std.testing.expect(!retrieved_code.isEmpty());

        const storage_key = @as(primitives.StorageKey, 42);
        const storage_value = @as(primitives.StorageValue, 123);
        try db.insertStorage(address, storage_key, storage_value);

        const retrieved_storage = try db.storage(address, storage_key);
        try std.testing.expectEqual(storage_value, retrieved_storage);
    }

    pub fn testState() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var state_db = State.init(allocator);
        defer state_db.deinit();

        const address: primitives.Address = [_]u8{0x01} ** 20;
        const account = state.Account.default();

        try state_db.insertAccount(address, account);

        const retrieved_account = state_db.getAccount(address);
        try std.testing.expect(retrieved_account != null);
        try std.testing.expect(retrieved_account.?.isEmpty());

        const removed_account = state_db.removeAccount(address);
        try std.testing.expect(removed_account != null);

        const non_existent_account = state_db.getAccount(address);
        try std.testing.expect(non_existent_account == null);
    }
};
