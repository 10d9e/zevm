// Spec test runner: sets up pre-state, executes bytecode, validates storage.

const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const interpreter = @import("interpreter");
const context = @import("context");
const types = @import("types");

const U256 = primitives.U256;
const InstructionResult = interpreter.InstructionResult;
const Host = interpreter.Host;

/// Convert a big-endian [32]u8 to U256
fn u256FromBeBytes(bytes: [32]u8) U256 {
    return @byteSwap(@as(U256, @bitCast(bytes)));
}

/// Convert a U256 to big-endian [32]u8
fn u256ToBeBytes(val: U256) [32]u8 {
    return @bitCast(@byteSwap(val));
}

pub const TestResult = enum {
    pass,
    fail,
    skip,
    err,
};

pub const FailureDetail = struct {
    reason: []const u8,
    address: ?[20]u8 = null,
    storage_key: ?[32]u8 = null,
    expected: ?[32]u8 = null,
    actual: ?[32]u8 = null,
    exec_result: ?InstructionResult = null,
    opcode: ?u8 = null,
};

pub const TestOutcome = struct {
    result: TestResult,
    detail: FailureDetail,
};

/// Format a [20]u8 address as "0xabcd...ef12" (first 4 + last 4 hex chars = first 2 + last 2 bytes).
pub fn fmtAddress(addr: [20]u8) [14]u8 {
    const hex = "0123456789abcdef";
    var buf: [14]u8 = undefined;
    buf[0] = '0';
    buf[1] = 'x';
    buf[2] = hex[addr[0] >> 4];
    buf[3] = hex[addr[0] & 0xf];
    buf[4] = hex[addr[1] >> 4];
    buf[5] = hex[addr[1] & 0xf];
    buf[6] = '.';
    buf[7] = '.';
    buf[8] = hex[addr[18] >> 4];
    buf[9] = hex[addr[18] & 0xf];
    buf[10] = hex[addr[19] >> 4];
    buf[11] = hex[addr[19] & 0xf];
    buf[12] = ' ';
    buf[13] = ' ';
    return buf;
}

/// Format a [32]u8 big-endian value as "0xNN" with leading zeros trimmed.
/// Returns the number of valid bytes written to the output buffer.
pub fn fmtU256Bytes(val: [32]u8, buf: *[68]u8) usize {
    const hex = "0123456789abcdef";
    buf[0] = '0';
    buf[1] = 'x';

    // Find first non-zero byte
    var first_nonzero: usize = 32;
    for (val, 0..) |b, i| {
        if (b != 0) {
            first_nonzero = i;
            break;
        }
    }

    if (first_nonzero == 32) {
        buf[2] = '0';
        buf[3] = '0';
        return 4;
    }

    var pos: usize = 2;
    for (val[first_nonzero..]) |b| {
        buf[pos] = hex[b >> 4];
        buf[pos + 1] = hex[b & 0xf];
        pos += 2;
    }
    return pos;
}

// --- TestHost: mock Host implementation for spec tests ---

const StorageMapKey = struct {
    address: [20]u8,
    key: U256,
};

const TestHost = struct {
    pre_storage: *std.AutoHashMap(StorageMapKey, U256),
    storage_writes: *std.AutoHashMap(StorageMapKey, U256),
    pre_accounts: []const types.PreAccount,

    fn host(self: *TestHost) Host {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    const vtable = Host.VTable{
        .sload = @ptrCast(&sloadFn),
        .sstore = @ptrCast(&sstoreFn),
        .balance = @ptrCast(&balanceFn),
        .code = @ptrCast(&codeFn),
        .codeSize = @ptrCast(&codeSizeFn),
        .codeHash = @ptrCast(&codeHashFn),
        .blockHash = @ptrCast(&blockHashFn),
    };

    fn sloadFn(self: *TestHost, addr: [20]u8, key: U256) U256 {
        return self.storage_writes.get(.{
            .address = addr,
            .key = key,
        }) orelse self.pre_storage.get(.{
            .address = addr,
            .key = key,
        }) orelse @as(U256, 0);
    }

    fn sstoreFn(self: *TestHost, addr: [20]u8, key: U256, val: U256) void {
        self.storage_writes.put(.{
            .address = addr,
            .key = key,
        }, val) catch {};
    }

    fn balanceFn(self: *TestHost, addr: [20]u8) U256 {
        for (self.pre_accounts) |acct| {
            if (std.mem.eql(u8, &acct.address, &addr)) {
                return u256FromBeBytes(acct.balance);
            }
        }
        return @as(U256, 0);
    }

    fn codeFn(self: *TestHost, addr: [20]u8) []const u8 {
        for (self.pre_accounts) |acct| {
            if (std.mem.eql(u8, &acct.address, &addr)) {
                return acct.code;
            }
        }
        return &.{};
    }

    fn codeSizeFn(self: *TestHost, addr: [20]u8) usize {
        for (self.pre_accounts) |acct| {
            if (std.mem.eql(u8, &acct.address, &addr)) {
                return acct.code.len;
            }
        }
        return 0;
    }

    fn codeHashFn(self: *TestHost, addr: [20]u8) U256 {
        for (self.pre_accounts) |acct| {
            if (std.mem.eql(u8, &acct.address, &addr)) {
                if (acct.code.len == 0) {
                    return @as(U256, 0);
                }
                var hash_buf: [32]u8 = undefined;
                std.crypto.hash.sha3.Keccak256.hash(acct.code, &hash_buf, .{});
                return u256FromBeBytes(hash_buf);
            }
        }
        return @as(U256, 0);
    }

    fn blockHashFn(_: *TestHost, _: U256) U256 {
        return @as(U256, 0);
    }
};

pub fn runTestCase(tc: types.TestCase, allocator: std.mem.Allocator) TestOutcome {
    if (!std.mem.eql(u8, tc.fork, "Osaka") and !std.mem.eql(u8, tc.fork, "Prague")) {
        return .{ .result = .skip, .detail = .{ .reason = "unsupported fork" } };
    }

    // Find target account's code in pre_accounts
    var target_code: []const u8 = &.{};
    for (tc.pre_accounts) |acct| {
        if (std.mem.eql(u8, &acct.address, &tc.target)) {
            target_code = acct.code;
            break;
        }
    }

    if (target_code.len == 0 and !tc.is_create) {
        if (tc.expect_exception) {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception with no code" } };
        }
        if (tc.expected_storage.len == 0) {
            return .{ .result = .pass, .detail = .{ .reason = "no code, no expectations" } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "no code but storage expected" } };
    }

    // Set up pre-state storage
    var pre_storage = std.AutoHashMap(StorageMapKey, U256).init(allocator);
    defer pre_storage.deinit();
    for (tc.pre_accounts) |acct| {
        for (acct.storage) |entry| {
            pre_storage.put(.{
                .address = acct.address,
                .key = u256FromBeBytes(entry.key),
            }, u256FromBeBytes(entry.value)) catch {
                return .{ .result = .err, .detail = .{ .reason = "OOM setting up pre-storage" } };
            };
        }
    }

    // Storage writes tracked during execution
    var storage_writes = std.AutoHashMap(StorageMapKey, U256).init(allocator);
    defer storage_writes.deinit();

    // Build TestHost
    var test_host = TestHost{
        .pre_storage = &pre_storage,
        .storage_writes = &storage_writes,
        .pre_accounts = tc.pre_accounts,
    };

    // Build block env
    const block_env = context.BlockEnv{
        .number = u256FromBeBytes(tc.block_number),
        .beneficiary = tc.coinbase,
        .timestamp = u256FromBeBytes(tc.block_timestamp),
        .gas_limit = tc.block_gaslimit,
        .basefee = tc.block_basefee,
        .difficulty = u256FromBeBytes(tc.block_difficulty),
        .prevrandao = tc.prevrandao,
        .blob_excess_gas_and_price = null,
    };

    // Build tx env (only fields the execute loop reads)
    var tx_env = context.TxEnv.default();
    tx_env.gas_price = tc.gas_price;
    tx_env.caller = tc.caller;
    // chain_id stays default (1)

    // Build interpreter inputs
    const inputs = interpreter.InputsImpl{
        .caller = tc.caller,
        .target = tc.target,
        .value = u256FromBeBytes(tc.value),
        .data = @constCast(tc.calldata),
        .gas_limit = tc.gas_limit,
        .scheme = .call,
        .is_static = false,
        .depth = 0,
    };

    // Build interpreter
    const ext_bytecode = interpreter.ExtBytecode.new(bytecode_mod.Bytecode.newLegacy(target_code));
    var interp = interpreter.Interpreter.new(
        interpreter.Memory.new(),
        ext_bytecode,
        inputs,
        false,
        primitives.SpecId.prague,
        tc.gas_limit,
    );
    defer interp.deinit();

    // Execute
    const exec_result = interp.execute(block_env, tx_env, test_host.host());

    // If we expect an exception, any non-success result is a pass
    if (tc.expect_exception) {
        if (exec_result != .stop and exec_result != .@"return") {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception occurred", .exec_result = exec_result } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "expected exception but execution succeeded", .exec_result = exec_result } };
    }

    // Check for execution errors
    if (exec_result.isError()) {
        return .{ .result = .err, .detail = .{ .reason = "execution error", .exec_result = exec_result } };
    }

    // Validate expected storage
    for (tc.expected_storage) |expected_acct| {
        for (expected_acct.storage) |entry| {
            const key = u256FromBeBytes(entry.key);
            const expected_val = u256FromBeBytes(entry.value);

            const actual_val = storage_writes.get(.{
                .address = expected_acct.address,
                .key = key,
            }) orelse pre_storage.get(.{
                .address = expected_acct.address,
                .key = key,
            }) orelse @as(U256, 0);

            if (actual_val != expected_val) {
                return .{ .result = .fail, .detail = .{
                    .reason = "storage mismatch",
                    .address = expected_acct.address,
                    .storage_key = entry.key,
                    .expected = entry.value,
                    .actual = u256ToBeBytes(actual_val),
                } };
            }
        }
    }

    return .{ .result = .pass, .detail = .{ .reason = "ok" } };
}
