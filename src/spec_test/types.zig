// Shared data types for Ethereum execution spec test runner.
// Used by both the generator (to write) and the runner (to read).

pub const StorageEntry = struct {
    key: [32]u8, // U256 as big-endian bytes
    value: [32]u8, // U256 as big-endian bytes
};

pub const AccessListEntry = struct {
    address: [20]u8,
    storage_keys: []const [32]u8, // Each key is a U256 as big-endian bytes
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

/// An EIP-7702 authorization tuple (authority → delegation target mapping).
/// The authority is the recovered signer; address is what the authority delegates to.
pub const AuthorizationEntry = struct {
    authority: [20]u8, // recovered signer address (authority)
    address: [20]u8,   // delegation target (what the authority's code will point to)
    chain_id: u64,     // 0 = any chain, 1 = mainnet; non-matching = invalid entry
    nonce: u64,        // must match authority's current nonce to be valid
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
    gas_price: u128,           // maxFeePerGas (EIP-1559) or gasPrice (legacy)
    max_priority_fee_per_gas: u128, // EIP-1559 tip cap; 0 for legacy txs
    // EIP-2930 access list intrinsic gas counts
    access_list_addr_count: u32,
    access_list_slot_count: u32,
    // EIP-2930 access list entries for pre-warming addresses and storage keys
    access_list: []const AccessListEntry,
    // EIP-7702 authorization list count (25000 per tuple intrinsic gas)
    authorization_count: u32,
    // EIP-7702 authorization entries: (authority → delegation target) pairs for code setting
    authorization_entries: []const AuthorizationEntry,
    // EIP-4844 blob transaction fields
    blob_versioned_hashes_count: u32,
    blob_versioned_hashes: []const [32]u8, // actual hash values for BLOBHASH opcode
    max_fee_per_blob_gas: u128,
    excess_blob_gas: u64,
    // State
    pre_accounts: []const PreAccount,
    expected_storage: []const ExpectedAccount,
    expect_exception: bool,
};
