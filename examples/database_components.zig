const std = @import("std");
const primitives = @import("primitives");
const bytecode = @import("bytecode");
const state = @import("state");
const database = @import("database");
const context = @import("context");
const interpreter = @import("interpreter");
const precompile = @import("precompile");
const handler = @import("handler");
const inspector = @import("inspector");

/// Example demonstrating database components and state management.
///
/// This example demonstrates:
/// 1. Custom database implementations
/// 2. State management and tracking
/// 3. Block hash storage and retrieval
/// 4. Account state transitions
/// 5. Storage operations
/// Custom database that tracks all operations
pub const TrackingDB = struct {
    base_db: database.InMemoryDB,
    operations: std.ArrayList(Operation),
    allocator: std.mem.Allocator,

    const Operation = struct {
        op_type: OpType,
        address: primitives.Address,
        key: ?primitives.StorageKey,
        value: ?primitives.StorageValue,
        timestamp: u64,

        const OpType = enum {
            account_insert,
            account_get,
            storage_insert,
            storage_get,
            block_hash_insert,
            block_hash_get,
        };
    };

    pub fn init(allocator: std.mem.Allocator) !TrackingDB {
        return TrackingDB{
            .base_db = database.InMemoryDB.init(allocator),
            .operations = try std.ArrayList(Operation).initCapacity(allocator, 100),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TrackingDB) void {
        self.base_db.deinit();
        self.operations.deinit(self.allocator);
    }

    pub fn insertAccount(self: *TrackingDB, address: primitives.Address, account_info: state.AccountInfo) !void {
        try self.base_db.insertAccount(address, account_info);
        try self.operations.append(self.allocator, Operation{
            .op_type = .account_insert,
            .address = address,
            .key = null,
            .value = null,
            .timestamp = @as(u64, @intCast(std.time.timestamp())),
        });
    }

    pub fn getAccount(self: *TrackingDB, address: primitives.Address) !?state.AccountInfo {
        try self.operations.append(self.allocator, Operation{
            .op_type = .account_get,
            .address = address,
            .key = null,
            .value = null,
            .timestamp = @as(u64, @intCast(std.time.timestamp())),
        });
        return self.base_db.basic(address);
    }

    pub fn insertStorage(self: *TrackingDB, address: primitives.Address, key: primitives.StorageKey, value: primitives.StorageValue) !void {
        try self.base_db.insertStorage(address, key, value);
        try self.operations.append(self.allocator, Operation{
            .op_type = .storage_insert,
            .address = address,
            .key = key,
            .value = value,
            .timestamp = @as(u64, @intCast(std.time.timestamp())),
        });
    }

    pub fn getStorage(self: *TrackingDB, address: primitives.Address, key: primitives.StorageKey) !primitives.StorageValue {
        try self.operations.append(self.allocator, Operation{
            .op_type = .storage_get,
            .address = address,
            .key = key,
            .value = null,
            .timestamp = @as(u64, @intCast(std.time.timestamp())),
        });
        return self.base_db.getStorage(address, key);
    }

    pub fn insertBlockHash(self: *TrackingDB, number: u64, hash: primitives.Hash) !void {
        try self.base_db.insertBlockHash(number, hash);
        try self.operations.append(self.allocator, Operation{
            .op_type = .block_hash_insert,
            .address = [_]u8{0} ** 20, // Not applicable
            .key = primitives.U256.from(number),
            .value = null,
            .timestamp = @as(u64, @intCast(std.time.timestamp())),
        });
    }

    pub fn getBlockHash(self: *TrackingDB, number: u64) !primitives.Hash {
        try self.operations.append(self.allocator, Operation{
            .op_type = .block_hash_get,
            .address = [_]u8{0} ** 20, // Not applicable
            .key = primitives.U256.from(number),
            .value = null,
            .timestamp = @as(u64, @intCast(std.time.timestamp())),
        });
        return self.base_db.blockHash(number);
    }

    pub fn printOperations(self: *TrackingDB) void {
        std.log.info("=== Database Operations Log ===", .{});
        for (self.operations.items, 0..) |op, i| {
            std.log.info("Operation {}: {} at {any}", .{ i, op.op_type, op.address });
            if (op.key) |key| {
                std.log.info("  Key: {any}", .{key});
            }
            if (op.value) |value| {
                std.log.info("  Value: {any}", .{value});
            }
            std.log.info("  Timestamp: {}", .{op.timestamp});
        }
        std.log.info("Total operations: {}", .{self.operations.items.len});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== Database Components Example ===", .{});

    // Create tracking database
    var tracking_db = try TrackingDB.init(allocator);
    defer tracking_db.deinit();

    // Demonstrate account operations
    try demonstrateAccountOperations(&tracking_db);

    // Demonstrate storage operations
    try demonstrateStorageOperations(&tracking_db);

    // Demonstrate block hash operations
    try demonstrateBlockHashOperations(&tracking_db);

    // Demonstrate state transitions
    try demonstrateStateTransitions(&tracking_db);

    // Print all operations
    tracking_db.printOperations();

    std.log.info("=== Database Components Example Complete ===", .{});
}

fn demonstrateAccountOperations(tracking_db: *TrackingDB) !void {
    std.log.info("--- Account Operations ---", .{});

    const address1: primitives.Address = [_]u8{0x01} ** 20;
    const address2: primitives.Address = [_]u8{0x02} ** 20;

    // Create account info
    const account1 = state.AccountInfo.new(
        primitives.U256.from(1000), // balance
        5, // nonce
        primitives.KECCAK_EMPTY, // code hash
        bytecode.Bytecode.new(),
    );

    const account2 = state.AccountInfo.new(
        primitives.U256.from(2000), // balance
        10, // nonce
        primitives.KECCAK_EMPTY, // code hash
        bytecode.Bytecode.new(),
    );

    // Insert accounts
    try tracking_db.insertAccount(address1, account1);
    try tracking_db.insertAccount(address2, account2);

    // Retrieve accounts
    const retrieved_account1 = try tracking_db.getAccount(address1);
    const retrieved_account2 = try tracking_db.getAccount(address2);

    if (retrieved_account1) |acc1| {
        std.log.info("Account 1 - Balance: {any}, Nonce: {}", .{ acc1.balance, acc1.nonce });
    }

    if (retrieved_account2) |acc2| {
        std.log.info("Account 2 - Balance: {any}, Nonce: {}", .{ acc2.balance, acc2.nonce });
    }
}

fn demonstrateStorageOperations(tracking_db: *TrackingDB) !void {
    std.log.info("--- Storage Operations ---", .{});

    const contract_address: primitives.Address = [_]u8{0x03} ** 20;

    // Create contract account
    const contract_account = state.AccountInfo.new(
        primitives.U256.ZERO, // balance
        0, // nonce
        primitives.KECCAK_EMPTY, // code hash
        bytecode.Bytecode.new(),
    );

    try tracking_db.insertAccount(contract_address, contract_account);

    // Set storage values
    const storage_key1 = primitives.U256.ZERO;
    const storage_key2 = primitives.U256.ONE;
    const storage_key3 = primitives.U256.from(0x123456789ABCDEF0);

    try tracking_db.insertStorage(contract_address, storage_key1, primitives.U256.from(0x1111));
    try tracking_db.insertStorage(contract_address, storage_key2, primitives.U256.from(0x2222));
    try tracking_db.insertStorage(contract_address, storage_key3, primitives.U256.from(0x3333));

    // Retrieve storage values
    const value1 = try tracking_db.getStorage(contract_address, storage_key1);
    const value2 = try tracking_db.getStorage(contract_address, storage_key2);
    const value3 = try tracking_db.getStorage(contract_address, storage_key3);

    std.log.info("Storage slot 0: 0x{x}", .{value1.toNative()});
    std.log.info("Storage slot 1: 0x{x}", .{value2.toNative()});
    std.log.info("Storage slot 0x123456789ABCDEF0: 0x{x}", .{value3.toNative()});
}

fn demonstrateBlockHashOperations(tracking_db: *TrackingDB) !void {
    std.log.info("--- Block Hash Operations ---", .{});

    // Insert block hashes
    const block_hash1: primitives.Hash = [_]u8{0xAA} ** 32;
    const block_hash2: primitives.Hash = [_]u8{0xBB} ** 32;
    const block_hash3: primitives.Hash = [_]u8{0xCC} ** 32;

    try tracking_db.insertBlockHash(100, block_hash1);
    try tracking_db.insertBlockHash(101, block_hash2);
    try tracking_db.insertBlockHash(102, block_hash3);

    // Retrieve block hashes
    const retrieved_hash1 = try tracking_db.getBlockHash(100);
    const retrieved_hash2 = try tracking_db.getBlockHash(101);
    const retrieved_hash3 = try tracking_db.getBlockHash(102);

    std.log.info("Block 100 hash: {any}", .{retrieved_hash1});
    std.log.info("Block 101 hash: {any}", .{retrieved_hash2});
    std.log.info("Block 102 hash: {any}", .{retrieved_hash3});
}

fn demonstrateStateTransitions(tracking_db: *TrackingDB) !void {
    std.log.info("--- State Transitions ---", .{});

    const sender: primitives.Address = [_]u8{0x04} ** 20;
    const receiver: primitives.Address = [_]u8{0x05} ** 20;

    // Create initial accounts
    const sender_account = state.AccountInfo.new(
        primitives.U256.from(10000), // balance
        0, // nonce
        primitives.KECCAK_EMPTY, // code hash
        bytecode.Bytecode.new(),
    );

    const receiver_account = state.AccountInfo.new(
        primitives.U256.ZERO, // balance
        0, // nonce
        primitives.KECCAK_EMPTY, // code hash
        bytecode.Bytecode.new(),
    );

    try tracking_db.insertAccount(sender, sender_account);
    try tracking_db.insertAccount(receiver, receiver_account);

    std.log.info("Initial state:", .{});
    std.log.info("  Sender balance: {any}", .{(try tracking_db.getAccount(sender) orelse return).balance});
    std.log.info("  Receiver balance: {any}", .{(try tracking_db.getAccount(receiver) orelse return).balance});

    // Simulate a transfer transaction
    const transfer_amount = primitives.U256.from(1000);

    // Update sender account (decrease balance, increase nonce)
    const updated_sender = state.AccountInfo.new(
        primitives.U256.from(9000), // balance - transfer_amount
        1, // nonce + 1
        primitives.KECCAK_EMPTY, // code hash
        bytecode.Bytecode.new(),
    );

    // Update receiver account (increase balance)
    const updated_receiver = state.AccountInfo.new(
        transfer_amount, // balance + transfer_amount
        0, // nonce unchanged
        primitives.KECCAK_EMPTY, // code hash
        bytecode.Bytecode.new(),
    );

    try tracking_db.insertAccount(sender, updated_sender);
    try tracking_db.insertAccount(receiver, updated_receiver);

    std.log.info("After transfer:", .{});
    std.log.info("  Sender balance: {any}", .{(try tracking_db.getAccount(sender) orelse return).balance});
    std.log.info("  Receiver balance: {any}", .{(try tracking_db.getAccount(receiver) orelse return).balance});
    std.log.info("  Sender nonce: {}", .{(try tracking_db.getAccount(sender) orelse return).nonce});
}
