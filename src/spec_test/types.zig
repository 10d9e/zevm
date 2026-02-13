// Shared data types for Ethereum execution spec test runner.
// Used by both the generator (to write) and the runner (to read).

pub const StorageEntry = struct {
    key: [32]u8, // U256 as big-endian bytes
    value: [32]u8, // U256 as big-endian bytes
};

pub const PreAccount = struct {
    address: [20]u8,
    balance: [32]u8,
    nonce: u64,
    code: []const u8,
    storage: []const StorageEntry,
};

pub const ExpectedAccount = struct {
    address: [20]u8,
    storage: []const StorageEntry,
};

pub const TestCase = struct {
    name: []const u8,
    fork: []const u8,
    // Block env
    coinbase: [20]u8,
    block_number: [32]u8,
    block_timestamp: [32]u8,
    block_gaslimit: u64,
    block_basefee: u64,
    block_difficulty: [32]u8,
    prevrandao: [32]u8,
    // Tx
    caller: [20]u8,
    target: [20]u8,
    is_create: bool,
    value: [32]u8,
    calldata: []const u8,
    gas_limit: u64,
    gas_price: u128,
    // State
    pre_accounts: []const PreAccount,
    expected_storage: []const ExpectedAccount,
    expect_exception: bool,
};
