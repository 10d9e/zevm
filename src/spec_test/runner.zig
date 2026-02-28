// Spec test runner: sets up pre-state, executes bytecode, validates storage.

const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const interpreter = @import("interpreter");
const context = @import("context");
const database = @import("database");
const state_mod = @import("state");
const types = @import("types");

const U256 = primitives.U256;
const InstructionResult = interpreter.InstructionResult;

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

pub fn runTestCase(tc: types.TestCase, allocator: std.mem.Allocator) TestOutcome {
    if (!std.mem.eql(u8, tc.fork, "Osaka") and !std.mem.eql(u8, tc.fork, "Prague")) {
        return .{ .result = .skip, .detail = .{ .reason = "unsupported fork" } };
    }

    const spec: primitives.SpecId = if (std.mem.eql(u8, tc.fork, "Prague")) .prague else .osaka;

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

    // Build InMemoryDB from pre_accounts
    var db = database.InMemoryDB.init(allocator);
    for (tc.pre_accounts) |acct| {
        var acct_info = state_mod.AccountInfo{
            .balance = u256FromBeBytes(acct.balance),
            .nonce = acct.nonce,
            .code_hash = primitives.KECCAK_EMPTY,
            .code = bytecode_mod.Bytecode.new(),
        };
        if (acct.code.len > 0) {
            const code_bc = bytecode_mod.Bytecode.newLegacy(acct.code);
            acct_info.code_hash = code_bc.hashSlow();
            acct_info.code = code_bc;
        }
        db.insertAccount(acct.address, acct_info) catch {
            return .{ .result = .err, .detail = .{ .reason = "OOM inserting account" } };
        };
        for (acct.storage) |entry| {
            db.insertStorage(acct.address, u256FromBeBytes(entry.key), u256FromBeBytes(entry.value)) catch {
                return .{ .result = .err, .detail = .{ .reason = "OOM inserting storage" } };
            };
        }
    }

    // Build context (db is moved into Context by value)
    var ctx = context.Context.new(db, spec);

    // Pre-load all pre-state accounts into the journal so that sload/sstore can
    // find them in evm_state (they require accounts to be loaded before access).
    for (tc.pre_accounts) |acct| {
        _ = ctx.journaled_state.loadAccount(acct.address) catch {
            return .{ .result = .err, .detail = .{ .reason = "OOM loading account into journal" } };
        };
    }

    // Set block env
    ctx.setBlock(context.BlockEnv{
        .number = u256FromBeBytes(tc.block_number),
        .beneficiary = tc.coinbase,
        .timestamp = u256FromBeBytes(tc.block_timestamp),
        .gas_limit = tc.block_gaslimit,
        .basefee = tc.block_basefee,
        .difficulty = u256FromBeBytes(tc.block_difficulty),
        .prevrandao = tc.prevrandao,
        .blob_excess_gas_and_price = null,
    });

    // Set tx env
    var tx_env = context.TxEnv.default();
    tx_env.gas_price = tc.gas_price;
    tx_env.caller = tc.caller;
    ctx.setTx(tx_env);

    // Get protocol schedule (instruction table + precompiles)
    const schedule = interpreter.ProtocolSchedule.forSpec(spec);

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
        spec,
        tc.gas_limit,
    );
    defer interp.deinit();

    // Build host and execute
    var host = interpreter.Host{
        .ctx = &ctx,
        .run_sub_call = interpreter.protocol_schedule.runSubCallDefault,
        .precompiles = &schedule.precompiles,
    };
    const exec_result = interp.runWithHost(&schedule.instructions, &host);

    // If we expect an exception, any non-success result is a pass
    if (tc.expect_exception) {
        if (exec_result != .stop and exec_result != .@"return") {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception occurred", .exec_result = exec_result } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "expected exception but execution succeeded", .exec_result = exec_result } };
    }

    // Check for execution errors
    if (exec_result.isError()) {
        return .{ .result = .err, .detail = .{ .reason = "execution error", .exec_result = exec_result, .opcode = interp.last_opcode } };
    }

    // Validate expected storage by reading from the journal's evm_state.
    // Slots written during execution are in evm_state[addr].storage[key].present_value.
    // Slots not accessed fall back to the pre-populated DB.
    const evm_state = &ctx.journaled_state.inner.evm_state;
    for (tc.expected_storage) |expected_acct| {
        for (expected_acct.storage) |entry| {
            const key = u256FromBeBytes(entry.key);
            const expected_val = u256FromBeBytes(entry.value);

            var actual_val: U256 = 0;
            if (evm_state.get(expected_acct.address)) |account| {
                if (account.storage.get(key)) |slot| {
                    actual_val = slot.presentValue();
                } else {
                    // Slot not touched during execution — read from pre-state DB
                    actual_val = ctx.journaled_state.database.getStorage(expected_acct.address, key) catch 0;
                }
            } else {
                // Account not loaded during execution — read from pre-state DB
                actual_val = ctx.journaled_state.database.getStorage(expected_acct.address, key) catch 0;
            }

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
