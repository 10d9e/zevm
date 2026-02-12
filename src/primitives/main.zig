const std = @import("std");

/// Core primitive types and constants for the Ethereum Virtual Machine (EVM) implementation.
/// This module provides:
/// - EVM constants and limits (gas, stack, code size)
/// - Ethereum hard fork management and version control
/// - EIP-specific constants and configuration values
/// - Type aliases for common EVM concepts (storage keys/values)
pub const Address = [20]u8;
pub const Hash = [32]u8;
pub const U256 = @import("u256.zig").U256;
pub const U128 = u128;
pub const U64 = u64;
pub const U32 = u32;
pub const U16 = u16;
pub const U8 = u8;

/// Type alias for EVM storage keys (256-bit unsigned integers).
/// Used to identify storage slots within smart contract storage.
pub const StorageKey = U256;

/// Type alias for EVM storage values (256-bit unsigned integers).
/// Used to store data values in smart contract storage slots.
pub const StorageValue = U256;

/// Type alias for byte arrays
pub const Bytes = []u8;

/// Log entry for EVM events
pub const Log = struct {
    address: Address,
    topics: []const Hash,
    data: []const u8,
};

/// Optimize short address access.
pub const SHORT_ADDRESS_CAP: usize = 300;

/// Returns the short address from Address.
/// Short address is considered address that has 18 leading zeros
/// and last two bytes are less than SHORT_ADDRESS_CAP.
pub fn shortAddress(address: Address) ?usize {
    for (address[0..18]) |b| {
        if (b != 0) return null;
    }
    const short_address = std.mem.readInt(u16, address[18..20], .big);
    if (short_address < SHORT_ADDRESS_CAP) {
        return @intCast(short_address);
    }
    return null;
}

/// 1 ether = 10^18 wei
pub const ONE_ETHER: u128 = 1_000_000_000_000_000_000;

/// 1 gwei = 10^9 wei
pub const ONE_GWEI: u128 = 1_000_000_000;

/// Global constants for the EVM
/// Here you can find constants that don't belong to any EIP and are there for the genesis.
/// Number of block hashes that EVM can access in the past (pre-Prague)
pub const BLOCK_HASH_HISTORY: u64 = 256;

/// The address of precompile 3, which is handled specially in a few places
pub const PRECOMPILE3: Address = [20]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 };

/// EVM interpreter stack limit
pub const STACK_LIMIT: usize = 1024;

/// EVM call stack limit
pub const CALL_STACK_LIMIT: u64 = 1024;

/// Blob base fee update fraction for Prague hardfork
pub const BLOB_BASE_FEE_UPDATE_FRACTION_PRAGUE: u64 = 3338477;

/// Transaction gas limit cap (EIP-7825)
pub const TX_GAS_LIMIT_CAP: u64 = 30000000;

/// The Keccak-256 hash of the empty string "".
pub const KECCAK_EMPTY: Hash = [32]u8{
    0xc5, 0xd2, 0x46, 0x01, 0x86, 0xf7, 0x23, 0x3c,
    0x92, 0x7e, 0x7d, 0xb2, 0xdc, 0xc7, 0x03, 0xc0,
    0xe5, 0x00, 0xb6, 0x53, 0xca, 0x82, 0x27, 0x3b,
    0x7b, 0xfa, 0xd8, 0x04, 0x5d, 0x85, 0xa4, 0x70,
};

/// Specification IDs and their activation block
/// Information was obtained from the Ethereum Execution Specifications.
pub const SpecId = enum(u8) {
    /// Frontier hard fork - Activated at block 0
    frontier = 0,
    /// Frontier Thawing hard fork - Activated at block 200000
    frontier_thawing,
    /// Homestead hard fork - Activated at block 1150000
    homestead,
    /// DAO Fork hard fork - Activated at block 1920000
    dao_fork,
    /// Tangerine Whistle hard fork - Activated at block 2463000
    tangerine,
    /// Spurious Dragon hard fork - Activated at block 2675000
    spurious_dragon,
    /// Byzantium hard fork - Activated at block 4370000
    byzantium,
    /// Constantinople hard fork - Activated at block 7280000 is overwritten with PETERSBURG
    constantinople,
    /// Petersburg hard fork - Activated at block 7280000
    petersburg,
    /// Istanbul hard fork - Activated at block 9069000
    istanbul,
    /// Muir Glacier hard fork - Activated at block 9200000
    muir_glacier,
    /// Berlin hard fork - Activated at block 12244000
    berlin,
    /// London hard fork - Activated at block 12965000
    london,
    /// Arrow Glacier hard fork - Activated at block 13773000
    arrow_glacier,
    /// Gray Glacier hard fork - Activated at block 15050000
    gray_glacier,
    /// Paris/Merge hard fork - Activated at block 15537394 (TTD: 58750000000000000000000)
    merge,
    /// Shanghai hard fork - Activated at block 17034870 (Timestamp: 1681338455)
    shanghai,
    /// Cancun hard fork - Activated at block 19426587 (Timestamp: 1710338135)
    cancun,
    /// Prague hard fork - Activated at block 22431084 (Timestamp: 1746612311)
    prague,
    /// Osaka hard fork - Activated at block TBD
    osaka,
    /// Amsterdam hard fork - Activated at block TBD
    amsterdam,
};

/// Returns the SpecId for the given u8.
pub fn specIdFromU8(spec_id: u8) ?SpecId {
    return @enumFromInt(spec_id);
}

/// Returns true if the given specification ID is enabled in this spec.
pub fn isEnabledIn(self: SpecId, other: SpecId) bool {
    return @intFromEnum(self) >= @intFromEnum(other);
}

/// String identifiers for hardforks.
pub const HardforkName = struct {
    pub const FRONTIER = "Frontier";
    pub const FRONTIER_THAWING = "Frontier Thawing";
    pub const HOMESTEAD = "Homestead";
    pub const DAO_FORK = "DAO Fork";
    pub const TANGERINE = "Tangerine";
    pub const SPURIOUS_DRAGON = "Spurious";
    pub const BYZANTIUM = "Byzantium";
    pub const CONSTANTINOPLE = "Constantinople";
    pub const PETERSBURG = "Petersburg";
    pub const ISTANBUL = "Istanbul";
    pub const MUIR_GLACIER = "MuirGlacier";
    pub const BERLIN = "Berlin";
    pub const LONDON = "London";
    pub const ARROW_GLACIER = "Arrow Glacier";
    pub const GRAY_GLACIER = "Gray Glacier";
    pub const MERGE = "Merge";
    pub const SHANGHAI = "Shanghai";
    pub const CANCUN = "Cancun";
    pub const PRAGUE = "Prague";
    pub const OSAKA = "Osaka";
    pub const AMSTERDAM = "Amsterdam";
    pub const LATEST = "Latest";
};

/// Error type for unknown hardfork names.
pub const UnknownHardfork = error{UnknownHardfork};

/// Parse a hardfork name string to SpecId.
pub fn specIdFromString(s: []const u8) UnknownHardfork!SpecId {
    if (std.mem.eql(u8, s, HardforkName.FRONTIER)) return .frontier;
    if (std.mem.eql(u8, s, HardforkName.FRONTIER_THAWING)) return .frontier_thawing;
    if (std.mem.eql(u8, s, HardforkName.HOMESTEAD)) return .homestead;
    if (std.mem.eql(u8, s, HardforkName.DAO_FORK)) return .dao_fork;
    if (std.mem.eql(u8, s, HardforkName.TANGERINE)) return .tangerine;
    if (std.mem.eql(u8, s, HardforkName.SPURIOUS_DRAGON)) return .spurious_dragon;
    if (std.mem.eql(u8, s, HardforkName.BYZANTIUM)) return .byzantium;
    if (std.mem.eql(u8, s, HardforkName.CONSTANTINOPLE)) return .constantinople;
    if (std.mem.eql(u8, s, HardforkName.PETERSBURG)) return .petersburg;
    if (std.mem.eql(u8, s, HardforkName.ISTANBUL)) return .istanbul;
    if (std.mem.eql(u8, s, HardforkName.MUIR_GLACIER)) return .muir_glacier;
    if (std.mem.eql(u8, s, HardforkName.BERLIN)) return .berlin;
    if (std.mem.eql(u8, s, HardforkName.LONDON)) return .london;
    if (std.mem.eql(u8, s, HardforkName.ARROW_GLACIER)) return .arrow_glacier;
    if (std.mem.eql(u8, s, HardforkName.GRAY_GLACIER)) return .gray_glacier;
    if (std.mem.eql(u8, s, HardforkName.MERGE)) return .merge;
    if (std.mem.eql(u8, s, HardforkName.SHANGHAI)) return .shanghai;
    if (std.mem.eql(u8, s, HardforkName.CANCUN)) return .cancun;
    if (std.mem.eql(u8, s, HardforkName.PRAGUE)) return .prague;
    if (std.mem.eql(u8, s, HardforkName.OSAKA)) return .osaka;
    if (std.mem.eql(u8, s, HardforkName.AMSTERDAM)) return .amsterdam;
    return UnknownHardfork.UnknownHardfork;
}

/// Convert SpecId to string representation.
pub fn specIdToString(spec_id: SpecId) []const u8 {
    return switch (spec_id) {
        .frontier => HardforkName.FRONTIER,
        .frontier_thawing => HardforkName.FRONTIER_THAWING,
        .homestead => HardforkName.HOMESTEAD,
        .dao_fork => HardforkName.DAO_FORK,
        .tangerine => HardforkName.TANGERINE,
        .spurious_dragon => HardforkName.SPURIOUS_DRAGON,
        .byzantium => HardforkName.BYZANTIUM,
        .constantinople => HardforkName.CONSTANTINOPLE,
        .petersburg => HardforkName.PETERSBURG,
        .istanbul => HardforkName.ISTANBUL,
        .muir_glacier => HardforkName.MUIR_GLACIER,
        .berlin => HardforkName.BERLIN,
        .london => HardforkName.LONDON,
        .arrow_glacier => HardforkName.ARROW_GLACIER,
        .gray_glacier => HardforkName.GRAY_GLACIER,
        .merge => HardforkName.MERGE,
        .shanghai => HardforkName.SHANGHAI,
        .cancun => HardforkName.CANCUN,
        .prague => HardforkName.PRAGUE,
        .osaka => HardforkName.OSAKA,
        .amsterdam => HardforkName.AMSTERDAM,
    };
}

/// Format SpecId for display.
pub fn formatSpecId(spec_id: SpecId, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try writer.writeAll(specIdToString(spec_id));
}

/// Test module for primitives
pub const testing = struct {
    pub fn testShortAddress() !void {
        const address1: Address = [20]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 100 };
        const result1 = shortAddress(address1);
        try std.testing.expectEqual(@as(?usize, 100), result1);

        const address2: Address = [20]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
        const result2 = shortAddress(address2);
        try std.testing.expectEqual(@as(?usize, 0), result2);

        const address3: Address = [20]u8{ 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 100 };
        const result3 = shortAddress(address3);
        try std.testing.expectEqual(@as(?usize, null), result3);
    }

    pub fn testSpecId() !void {
        // Test string conversion
        try std.testing.expectEqual(SpecId.frontier, specIdFromString("Frontier"));
        try std.testing.expectEqual(SpecId.prague, specIdFromString("Prague"));

        // Test enabled check
        try std.testing.expect(isEnabledIn(.petersburg, .byzantium));
        try std.testing.expect(!isEnabledIn(.byzantium, .petersburg));

        // Test string representation
        try std.testing.expectEqualStrings("Frontier", specIdToString(.frontier));
        try std.testing.expectEqualStrings("Prague", specIdToString(.prague));
    }
};
