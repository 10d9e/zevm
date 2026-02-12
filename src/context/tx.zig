const std = @import("std");
const primitives = @import("primitives");

/// Transaction type enum
pub const TransactionType = enum(u8) {
    Legacy = 0,
    Eip2930 = 1,
    Eip1559 = 2,
    Eip4844 = 3,
    Eip7702 = 4,
    Custom = 0xFF,
};

/// Transaction kind enum
pub const TxKind = union(enum) {
    Call: primitives.Address,
    Create,

    pub fn isCall(self: TxKind) bool {
        return switch (self) {
            .Call => true,
            .Create => false,
        };
    }
};

/// Access list item
pub const AccessListItem = struct {
    address: primitives.Address,
    storage_keys: std.ArrayList(primitives.StorageKey),

    pub fn init(allocator: std.mem.Allocator) AccessListItem {
        return .{
            .address = [_]u8{0} ** 20,
            .storage_keys = std.ArrayList(primitives.StorageKey).init(allocator),
        };
    }

    pub fn deinit(self: *AccessListItem) void {
        self.storage_keys.deinit(std.heap.c_allocator);
    }
};

/// Access list
pub const AccessList = struct {
    items: ?std.ArrayList(AccessListItem),

    pub fn init(allocator: std.mem.Allocator) AccessList {
        _ = allocator;
        return .{
            .items = null,
        };
    }

    pub fn deinit(self: *AccessList) void {
        if (self.items) |*items| {
            for (items.items) |*item| {
                item.deinit();
            }
            items.deinit(std.heap.c_allocator);
        }
    }

    pub fn len(self: AccessList) usize {
        return if (self.items) |items| items.items.len else 0;
    }
};

/// Authorization for EIP-7702
pub const Authorization = struct {
    chain_id: primitives.U256,
    address: primitives.Address,
    nonce: u64,
};

/// Recovered authority
pub const RecoveredAuthority = union(enum) {
    Valid: primitives.Address,
    Invalid,
};

/// Recovered authorization
pub const RecoveredAuthorization = struct {
    auth: Authorization,
    authority: RecoveredAuthority,

    pub fn newUnchecked(auth: Authorization, authority: RecoveredAuthority) RecoveredAuthorization {
        return .{
            .auth = auth,
            .authority = authority,
        };
    }
};

/// Signed authorization
pub const SignedAuthorization = struct {
    auth: Authorization,
    signature: [65]u8, // ECDSA signature
};

/// Either type for authorization list
pub const Either = union(enum) {
    Left: SignedAuthorization,
    Right: RecoveredAuthorization,
};

/// The Transaction Environment is a struct that contains all fields that can be found in all Ethereum transaction,
/// including EIP-4844, EIP-7702, EIP-7873, etc.
pub const TxEnv = struct {
    /// Transaction type
    tx_type: u8,
    /// Caller aka Author aka transaction signer
    caller: primitives.Address,
    /// The gas limit of the transaction.
    gas_limit: u64,
    /// The gas price of the transaction.
    ///
    /// For EIP-1559 transaction this represent max_gas_fee.
    gas_price: u128,
    /// The destination of the transaction
    kind: TxKind,
    /// The value sent to `transact_to`
    value: primitives.U256,
    /// The data of the transaction
    data: ?std.ArrayList(u8),
    /// The nonce of the transaction
    nonce: u64,
    /// The chain ID of the transaction
    ///
    /// Incorporated as part of the Spurious Dragon upgrade via EIP-155.
    chain_id: ?u64,
    /// A list of addresses and storage keys that the transaction plans to access
    ///
    /// Added in EIP-2930.
    access_list: AccessList,
    /// The priority fee per gas
    ///
    /// Incorporated as part of the London upgrade via EIP-1559.
    gas_priority_fee: ?u128,
    /// The list of blob versioned hashes
    ///
    /// Per EIP there should be at least one blob present if `max_fee_per_blob_gas` is `Some`.
    ///
    /// Incorporated as part of the Cancun upgrade via EIP-4844.
    blob_hashes: ?std.ArrayList(primitives.Hash),
    /// The max fee per blob gas
    ///
    /// Incorporated as part of the Cancun upgrade via EIP-4844.
    max_fee_per_blob_gas: u128,
    /// List of authorizations
    ///
    /// `authorization_list` contains the signature that authorizes this
    /// caller to place the code to signer account.
    ///
    /// Set EOA account code for one transaction via EIP-7702.
    authorization_list: ?std.ArrayList(Either),

    pub fn default() TxEnv {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        return .{
            .tx_type = 0,
            .caller = [_]u8{0} ** 20,
            .gas_limit = primitives.TX_GAS_LIMIT_CAP,
            .gas_price = 0,
            .kind = TxKind{ .Call = [_]u8{0} ** 20 },
            .value = primitives.U256.ZERO,
            .data = null,
            .nonce = 0,
            .chain_id = 1, // Mainnet chain ID is 1
            .access_list = AccessList.init(allocator),
            .gas_priority_fee = null,
            .blob_hashes = null,
            .max_fee_per_blob_gas = 0,
            .authorization_list = null,
        };
    }

    pub fn deinit(self: *TxEnv) void {
        if (self.data) |*data| {
            data.deinit(std.heap.c_allocator);
        }
        self.access_list.deinit();
        if (self.blob_hashes) |*blob_hashes| {
            blob_hashes.deinit(std.heap.c_allocator);
        }
        if (self.authorization_list) |*authorization_list| {
            authorization_list.deinit(std.heap.c_allocator);
        }
    }

    /// Creates a new TxEnv with benchmark-specific values.
    pub fn newBench() TxEnv {
        var tx = TxEnv.default();
        tx.caller = primitives.BENCH_CALLER;
        tx.kind = TxKind{ .Call = primitives.BENCH_TARGET };
        tx.gas_limit = 1_000_000_000;
        return tx;
    }

    /// Derives tx type from transaction fields and sets it to `tx_type`.
    /// Returns error in case some fields were not set correctly.
    pub fn deriveTxType(self: *TxEnv) !void {
        if (self.access_list.len() > 0) {
            self.tx_type = @intFromEnum(TransactionType.Eip2930);
        }

        if (self.gas_priority_fee != null) {
            self.tx_type = @intFromEnum(TransactionType.Eip1559);
        }

        if (self.blob_hashes.items.len > 0 or self.max_fee_per_blob_gas > 0) {
            if (self.kind == .Call) {
                self.tx_type = @intFromEnum(TransactionType.Eip4844);
                return;
            } else {
                return error.MissingTargetForEip4844;
            }
        }

        if (self.authorization_list.items.len > 0) {
            if (self.kind == .Call) {
                self.tx_type = @intFromEnum(TransactionType.Eip7702);
                return;
            } else {
                return error.MissingTargetForEip7702;
            }
        }
    }

    /// Insert a list of signed authorizations into the authorization list.
    pub fn setSignedAuthorization(self: *TxEnv, auth: []const SignedAuthorization) !void {
        self.authorization_list.clearRetainingCapacity();
        for (auth) |a| {
            try self.authorization_list.append(Either{ .Left = a });
        }
    }

    /// Insert a list of recovered authorizations into the authorization list.
    pub fn setRecoveredAuthorization(self: *TxEnv, auth: []const RecoveredAuthorization) !void {
        self.authorization_list.clearRetainingCapacity();
        for (auth) |a| {
            try self.authorization_list.append(Either{ .Right = a });
        }
    }

    pub fn txType(self: TxEnv) u8 {
        return self.tx_type;
    }

    pub fn getKind(self: TxEnv) TxKind {
        return self.kind;
    }

    pub fn getCaller(self: TxEnv) primitives.Address {
        return self.caller;
    }

    pub fn gasLimit(self: TxEnv) u64 {
        return self.gas_limit;
    }

    pub fn gasPrice(self: TxEnv) u128 {
        return self.gas_price;
    }

    pub fn getValue(self: TxEnv) primitives.U256 {
        return self.value;
    }

    pub fn getNonce(self: TxEnv) u64 {
        return self.nonce;
    }

    pub fn chainId(self: TxEnv) ?u64 {
        return self.chain_id;
    }

    pub fn accessList(self: TxEnv) ?[]const AccessListItem {
        if (self.access_list.len() == 0) return null;
        return self.access_list.items.items;
    }

    pub fn maxFeePerGas(self: TxEnv) u128 {
        return self.gas_price;
    }

    pub fn maxFeePerBlobGas(self: TxEnv) u128 {
        return self.max_fee_per_blob_gas;
    }

    pub fn authorizationListLen(self: TxEnv) usize {
        return self.authorization_list.items.len;
    }

    pub fn authorizationList(self: TxEnv) []const Either {
        return self.authorization_list.items.items;
    }

    pub fn input(self: TxEnv) []const u8 {
        return self.data.items.items;
    }

    pub fn blobVersionedHashes(self: TxEnv) []const primitives.Hash {
        return self.blob_hashes.items.items;
    }

    pub fn maxPriorityFeePerGas(self: TxEnv) ?u128 {
        return self.gas_priority_fee;
    }

    /// Calculate effective gas price based on base fee
    pub fn effectiveGasPrice(self: TxEnv, base_fee: u128) u128 {
        return switch (@as(TransactionType, @enumFromInt(self.tx_type))) {
            .Legacy, .Eip2930 => self.gas_price,
            .Eip1559, .Eip4844, .Eip7702 => {
                const priority_fee = self.gas_priority_fee orelse 0;
                return @min(self.gas_price, base_fee + priority_fee);
            },
            .Custom => self.gas_price,
        };
    }
};

/// Error type for deriving transaction type
pub const DeriveTxTypeError = error{
    MissingTargetForEip4844,
    MissingTargetForEip7702,
    MissingTargetForEip7873,
};

/// Error type for building [`TxEnv`]
pub const TxEnvBuildError = error{
    DeriveErr,
    MissingGasPriorityFeeForEip1559,
    MissingBlobHashesForEip4844,
    MissingAuthorizationListForEip7702,
    MissingTargetForEip4844,
};

/// Builder for constructing [`TxEnv`] instances
pub const TxEnvBuilder = struct {
    tx_type: ?u8,
    caller: primitives.Address,
    gas_limit: u64,
    gas_price: u128,
    kind: TxKind,
    value: primitives.U256,
    data: ?std.ArrayList(u8),
    nonce: u64,
    chain_id: ?u64,
    access_list: AccessList,
    gas_priority_fee: ?u128,
    blob_hashes: ?std.ArrayList(primitives.Hash),
    max_fee_per_blob_gas: u128,
    authorization_list: ?std.ArrayList(Either),

    pub fn new() TxEnvBuilder {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        return .{
            .tx_type = null,
            .caller = [_]u8{0} ** 20,
            .gas_limit = primitives.TX_GAS_LIMIT_CAP,
            .gas_price = 0,
            .kind = TxKind{ .Call = [_]u8{0} ** 20 },
            .value = primitives.U256.ZERO,
            .data = null,
            .nonce = 0,
            .chain_id = 1, // Mainnet chain ID is 1
            .access_list = AccessList.init(allocator),
            .gas_priority_fee = null,
            .blob_hashes = null,
            .max_fee_per_blob_gas = 0,
            .authorization_list = null,
        };
    }

    pub fn deinit(self: *TxEnvBuilder) void {
        self.data.items.deinit();
        self.access_list.deinit();
        if (self.blob_hashes) |*blob_hashes| {
            blob_hashes.deinit(std.heap.c_allocator);
        }
        if (self.authorization_list) |*authorization_list| {
            authorization_list.deinit(std.heap.c_allocator);
        }
    }

    /// Set the transaction type
    pub fn txType(self: TxEnvBuilder, tx_type: ?u8) TxEnvBuilder {
        return .{
            .tx_type = tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Get the transaction type
    pub fn getTxType(self: TxEnvBuilder) ?u8 {
        return self.tx_type;
    }

    /// Set the caller address
    pub fn setCaller(self: TxEnvBuilder, caller: primitives.Address) TxEnvBuilder {
        return .{
            .tx_type = self.tx_type,
            .caller = caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the gas limit
    pub fn gasLimit(self: TxEnvBuilder, gas_limit: u64) TxEnvBuilder {
        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the max fee per gas.
    pub fn maxFeePerGas(self: TxEnvBuilder, max_fee_per_gas: u128) TxEnvBuilder {
        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = max_fee_per_gas,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the gas price
    pub fn gasPrice(self: TxEnvBuilder, gas_price: u128) TxEnvBuilder {
        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the transaction kind
    pub fn setKind(self: TxEnvBuilder, kind: TxKind) TxEnvBuilder {
        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the transaction kind to call
    pub fn call(self: TxEnvBuilder, target: primitives.Address) TxEnvBuilder {
        return self.setKind(TxKind{ .Call = target });
    }

    /// Set the transaction kind to create
    pub fn create(self: TxEnvBuilder) TxEnvBuilder {
        return self.setKind(TxKind.Create);
    }

    /// Set the transaction kind to call
    pub fn to(self: TxEnvBuilder, target: primitives.Address) TxEnvBuilder {
        return self.call(target);
    }

    /// Set the transaction value
    pub fn setValue(self: TxEnvBuilder, value: primitives.U256) TxEnvBuilder {
        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the transaction data
    pub fn setData(self: TxEnvBuilder, data: ?std.ArrayList(u8)) TxEnvBuilder {
        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the transaction nonce
    pub fn setNonce(self: TxEnvBuilder, nonce: u64) TxEnvBuilder {
        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the chain ID
    pub fn chainId(self: TxEnvBuilder, chain_id: ?u64) TxEnvBuilder {
        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the access list
    pub fn accessList(self: TxEnvBuilder, access_list: AccessList) TxEnvBuilder {
        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the gas priority fee
    pub fn gasPriorityFee(self: TxEnvBuilder, gas_priority_fee: ?u128) TxEnvBuilder {
        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the blob hashes
    pub fn blobHashes(self: TxEnvBuilder, blob_hashes: []const primitives.Hash) !TxEnvBuilder {
        var new_blob_hashes = std.ArrayList(primitives.Hash).init(self.blob_hashes.allocator);
        try new_blob_hashes.appendSlice(blob_hashes);

        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = new_blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the max fee per blob gas
    pub fn maxFeePerBlobGas(self: TxEnvBuilder, max_fee_per_blob_gas: u128) TxEnvBuilder {
        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };
    }

    /// Set the authorization list
    pub fn authorizationList(self: TxEnvBuilder, authorization_list: []const Either) !TxEnvBuilder {
        var new_auth_list = std.ArrayList(Either).init(self.authorization_list.allocator);
        try new_auth_list.appendSlice(authorization_list);

        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = new_auth_list,
        };
    }

    /// Insert a list of signed authorizations into the authorization list.
    pub fn authorizationListSigned(self: TxEnvBuilder, auth: []const SignedAuthorization) !TxEnvBuilder {
        var new_auth_list = std.ArrayList(Either).init(self.authorization_list.allocator);
        for (auth) |a| {
            try new_auth_list.append(Either{ .Left = a });
        }

        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = new_auth_list,
        };
    }

    /// Insert a list of recovered authorizations into the authorization list.
    pub fn authorizationListRecovered(self: TxEnvBuilder, auth: []const RecoveredAuthorization) !TxEnvBuilder {
        var new_auth_list = std.ArrayList(Either).init(self.authorization_list.allocator);
        for (auth) |a| {
            try new_auth_list.append(Either{ .Right = a });
        }

        return .{
            .tx_type = self.tx_type,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = new_auth_list,
        };
    }

    /// Build the final [`TxEnv`] with default values for missing fields.
    pub fn buildFill(self: TxEnvBuilder) !TxEnv {
        var tx = TxEnv{
            .tx_type = self.tx_type orelse 0,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };

        // if tx_type is not set, derive it from fields and fix errors.
        if (self.tx_type == null) {
            tx.deriveTxType() catch |err| switch (err) {
                error.MissingTargetForEip4844 => {
                    tx.kind = TxKind{ .Call = [_]u8{0} ** 20 };
                },
                error.MissingTargetForEip7702 => {
                    tx.kind = TxKind{ .Call = [_]u8{0} ** 20 };
                },
                error.MissingTargetForEip7873 => {
                    tx.kind = TxKind{ .Call = [_]u8{0} ** 20 };
                },
            };
        }

        return tx;
    }

    /// Build the final [`TxEnv`], returns error if some fields are wrongly set.
    /// If it is fine to fill missing fields with default values, use [`TxEnvBuilder::buildFill`] instead.
    pub fn build(self: TxEnvBuilder) !TxEnv {
        // if tx_type is set, check if all needed fields are set correctly.
        if (self.tx_type) |tx_type| {
            switch (@as(TransactionType, @enumFromInt(tx_type))) {
                .Legacy => {
                    // do nothing
                },
                .Eip2930 => {
                    // do nothing, all fields are set. Access list can be empty.
                },
                .Eip1559 => {
                    // gas priority fee is required
                    if (self.gas_priority_fee == null) {
                        return error.MissingGasPriorityFeeForEip1559;
                    }
                },
                .Eip4844 => {
                    // gas priority fee is required
                    if (self.gas_priority_fee == null) {
                        return error.MissingGasPriorityFeeForEip1559;
                    }

                    // blob hashes can be empty
                    if (self.blob_hashes.items.len == 0) {
                        return error.MissingBlobHashesForEip4844;
                    }

                    // target is required
                    if (self.kind != .Call) {
                        return error.MissingTargetForEip4844;
                    }
                },
                .Eip7702 => {
                    // gas priority fee is required
                    if (self.gas_priority_fee == null) {
                        return error.MissingGasPriorityFeeForEip1559;
                    }

                    // authorization list can be empty
                    if (self.authorization_list.items.len == 0) {
                        return error.MissingAuthorizationListForEip7702;
                    }

                    // target is required
                    if (self.kind != .Call) {
                        return error.MissingTargetForEip7702;
                    }
                },
                .Custom => {
                    // do nothing, custom transaction type is handled by the caller.
                },
            }
        }

        var tx = TxEnv{
            .tx_type = self.tx_type orelse 0,
            .caller = self.caller,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = self.kind,
            .value = self.value,
            .data = self.data,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = self.access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = self.blob_hashes,
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = self.authorization_list,
        };

        // Derive tx type from fields, if some fields are wrongly set it will return an error.
        if (self.tx_type == null) {
            try tx.deriveTxType();
        }

        return tx;
    }
};

/// Create a new builder for constructing a [`TxEnv`]
pub fn builder() TxEnvBuilder {
    return TxEnvBuilder.new();
}

/// Create a new builder for constructing a [`TxEnv`] with benchmark-specific values.
pub fn builderForBench() TxEnvBuilder {
    return TxEnv.newBench().modify();
}

/// Modify the [`TxEnv`] by using builder pattern.
pub fn modify(self: TxEnv) TxEnvBuilder {
    return TxEnvBuilder{
        .tx_type = self.tx_type,
        .caller = self.caller,
        .gas_limit = self.gas_limit,
        .gas_price = self.gas_price,
        .kind = self.kind,
        .value = self.value,
        .data = self.data,
        .nonce = self.nonce,
        .chain_id = self.chain_id,
        .access_list = self.access_list,
        .gas_priority_fee = self.gas_priority_fee,
        .blob_hashes = self.blob_hashes,
        .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
        .authorization_list = self.authorization_list,
    };
}
