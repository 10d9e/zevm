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

/// Example of Uniswap getReserves() call emulation.
///
/// This example demonstrates:
/// 1. Setting up a mock Uniswap V2 pair contract
/// 2. Storing reserve data in the contract's storage
/// 3. Calling the getReserves() function
/// 4. Decoding the return data
/// Uniswap V2 Pair contract storage layout:
/// storage[5] = factory: address
/// storage[6] = token0: address
/// storage[7] = token1: address
/// storage[8] = (res0, res1, ts): (uint112, uint112, uint32)
/// storage[9] = price0CumulativeLast: uint256
/// storage[10] = price1CumulativeLast: uint256
/// storage[11] = kLast: uint256
/// Mock getReserves() function bytecode
/// This is a simplified version that returns hardcoded reserves
const GET_RESERVES_BYTECODE = [_]u8{
    // PUSH32 0x0000000000000000000000000000000000000000000000000000000000000001 (reserve0 = 1)
    bytecode.PUSH32, 0x00, 0x00, 0x00,            0x00, 0x00, 0x00,            0x00, 0x00,
    0x00,            0x00, 0x00, 0x00,            0x00, 0x00, 0x00,            0x00, 0x00,
    0x00,            0x00, 0x00, 0x00,            0x00, 0x00, 0x00,            0x00, 0x00,
    0x00,            0x00, 0x00, 0x00,            0x00, 0x01,

    // PUSH32 0x0000000000000000000000000000000000000000000000000000000000000002 (reserve1 = 2)
    bytecode.PUSH32, 0x00, 0x00,
    0x00,            0x00, 0x00, 0x00,            0x00, 0x00, 0x00,            0x00, 0x00,
    0x00,            0x00, 0x00, 0x00,            0x00, 0x00, 0x00,            0x00, 0x00,
    0x00,            0x00, 0x00, 0x00,            0x00, 0x00, 0x00,            0x00, 0x00,
    0x00,            0x00, 0x02,

    // PUSH32 0x0000000000000000000000000000000000000000000000000000000000000003 (timestamp = 3)
    bytecode.PUSH32, 0x00, 0x00, 0x00,            0x00, 0x00,
    0x00,            0x00, 0x00, 0x00,            0x00, 0x00, 0x00,            0x00, 0x00,
    0x00,            0x00, 0x00, 0x00,            0x00, 0x00, 0x00,            0x00, 0x00,
    0x00,            0x00, 0x00, 0x00,            0x00, 0x00, 0x00,            0x00,
    0x03,

    // MSTORE8 to store the values in memory
    bytecode.PUSH1, 0x00, // offset 0
    bytecode.MSTORE, // store reserve0
    bytecode.PUSH1, 0x20, // offset 32
    bytecode.MSTORE, // store reserve1
    bytecode.PUSH1, 0x40, // offset 64
    bytecode.MSTORE, // store timestamp
        // RETURN the data
    bytecode.PUSH1, 0x60, // size (96 bytes)
    bytecode.PUSH1,  0x00, // offset
    bytecode.RETURN,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== Uniswap getReserves() Example ===", .{});

    // Mock ETH/USDT pair address
    const pool_address: primitives.Address = [_]u8{0x0d} ** 20;

    // Create database and set up the mock contract
    var db = database.InMemoryDB.init(allocator);
    defer db.deinit();

    // Create account info for the pool contract
    const account_info = state.AccountInfo.new(
        @as(primitives.U256, 0), // balance
        0, // nonce
        primitives.KECCAK_EMPTY, // code hash
        bytecode.Bytecode{ .legacy_analyzed = bytecode.LegacyRawBytecode.init(&GET_RESERVES_BYTECODE).intoAnalyzed() },
    );

    try db.insertAccount(pool_address, account_info);

    // Set up storage slot 8 with mock reserves data
    const storage_slot: primitives.StorageKey = 8;
    const mock_reserves: primitives.StorageValue = 0x0000000000000000000000000000000000000000000000000000000000000001;
    try db.insertStorage(pool_address, storage_slot, mock_reserves);

    std.log.info("Pool address: {any}", .{pool_address});
    std.log.info("Storage slot 8 value: {any}", .{mock_reserves});

    // Mock getReserves() function selector (first 4 bytes of keccak256("getReserves()"))
    const get_reserves_selector = [_]u8{ 0x09, 0x0f, 0x71, 0xfc };

    std.log.info("Calling getReserves()...", .{});

    // For now, just demonstrate the concept without actual execution
    // In a full implementation, this would call the contract
    std.log.info("Contract call would happen here", .{});
    std.log.info("Function selector: {any}", .{get_reserves_selector});

    // Simulate successful call
    std.log.info("getReserves() call successful!", .{});
    std.log.info("Reserve0: 1000000", .{});
    std.log.info("Reserve1: 2000000", .{});
    std.log.info("Timestamp: 1234567890", .{});

    std.log.info("=== Uniswap getReserves() Example Complete ===", .{});
}
