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

    // For CREATE transactions: the bytecode is the init code (calldata), run in context of the
    // newly created contract. For CALL transactions: the bytecode is the code at the target address.
    const run_code: []const u8 = if (tc.is_create) tc.calldata else blk: {
        var target_code: []const u8 = &.{};
        for (tc.pre_accounts) |acct| {
            if (std.mem.eql(u8, &acct.address, &tc.target)) {
                target_code = acct.code;
                break;
            }
        }
        break :blk target_code;
    };

    if (!tc.is_create and run_code.len == 0) {
        if (tc.expect_exception) {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception with no code" } };
        }
        if (tc.expected_storage.len == 0) {
            return .{ .result = .pass, .detail = .{ .reason = "no code, no expectations" } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "no code but storage expected" } };
    }

    const tx_value = u256FromBeBytes(tc.value);

    // For CREATE transactions, compute the created contract address from sender + nonce
    // before building the DB (so we can pre-populate the account).
    var effective_target: [20]u8 = tc.target;
    if (tc.is_create) {
        var sender_nonce: u64 = 0;
        for (tc.pre_accounts) |acct| {
            if (std.mem.eql(u8, &acct.address, &tc.caller)) {
                sender_nonce = acct.nonce;
                break;
            }
        }
        effective_target = interpreter.host_module.createAddress(tc.caller, sender_nonce);

        // EIP-7610 / pre-existing CREATE collision check:
        // If the target address already exists with non-empty code, nonce, balance, or storage,
        // the CREATE fails immediately (no initcode runs). State is unchanged.
        for (tc.pre_accounts) |acct| {
            if (!std.mem.eql(u8, &acct.address, &effective_target)) continue;
            var has_collision = u256FromBeBytes(acct.balance) != 0 or
                acct.nonce != 0 or
                acct.code.len > 0;
            if (!has_collision) {
                for (acct.storage) |entry| {
                    if (!std.mem.eql(u8, &entry.value, &([_]u8{0} ** 32))) {
                        has_collision = true;
                        break;
                    }
                }
            }
            if (has_collision) {
                if (tc.expect_exception) {
                    return .{ .result = .pass, .detail = .{ .reason = "expected CREATE collision" } };
                }
                // No exception expected: CREATE fails silently, pre-state is unchanged.
                // Validate expected storage against pre-state accounts (no initcode ran).
                for (tc.expected_storage) |expected_acct| {
                    for (expected_acct.storage) |entry| {
                        const expected_val = u256FromBeBytes(entry.value);
                        // Look for the slot in pre_accounts
                        var pre_val: U256 = 0;
                        for (tc.pre_accounts) |pa| {
                            if (!std.mem.eql(u8, &pa.address, &expected_acct.address)) continue;
                            for (pa.storage) |ps| {
                                if (std.mem.eql(u8, &ps.key, &entry.key)) {
                                    pre_val = u256FromBeBytes(ps.value);
                                    break;
                                }
                            }
                            break;
                        }
                        if (pre_val != expected_val) {
                            return .{ .result = .fail, .detail = .{
                                .reason = "storage mismatch after CREATE collision",
                                .address = expected_acct.address,
                                .storage_key = entry.key,
                                .expected = entry.value,
                                .actual = u256ToBeBytes(pre_val),
                            } };
                        }
                    }
                }
                return .{ .result = .pass, .detail = .{ .reason = "ok" } };
            }
            break;
        }
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

    // For CREATE transactions, pre-insert the new contract account so the journal can find it.
    if (tc.is_create) {
        const created_info = state_mod.AccountInfo{
            .balance = tx_value,
            .nonce = 1,
            .code_hash = primitives.KECCAK_EMPTY,
            .code = bytecode_mod.Bytecode.new(),
        };
        db.insertAccount(effective_target, created_info) catch {};
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
    // Also pre-load the CREATE target (if any) into the journal.
    if (tc.is_create) {
        _ = ctx.journaled_state.loadAccount(effective_target) catch {};
    }

    // Apply tx value transfer: credit effective_target with tc.value (debit from caller).
    // This models the ETH transfer that occurs when a transaction with value is processed.
    // (For CREATE, the value is already included in the created account's balance above.)
    if (tx_value > 0 and !tc.is_create) {
        if (ctx.journaled_state.inner.evm_state.getPtr(effective_target)) |acct| {
            acct.info.balance += tx_value;
        }
        if (ctx.journaled_state.inner.evm_state.getPtr(tc.caller)) |acct| {
            acct.info.balance -|= tx_value;
        }
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

    // Pre-warm precompile addresses (EIP-2929: precompiles are always warm at tx start)
    {
        var addr_buf: [32]primitives.Address = undefined;
        var count: usize = 0;
        var it = schedule.precompiles.addresses.keyIterator();
        while (it.next()) |addr| {
            if (count < addr_buf.len) {
                addr_buf[count] = addr.*;
                count += 1;
            }
        }
        ctx.journaled_state.warmPrecompiles(addr_buf[0..count]) catch {};
    }

    // Pre-warm coinbase (EIP-3651: warm coinbase since Shanghai, which Prague/Osaka include)
    ctx.journaled_state.warmCoinbaseAccount(tc.coinbase);

    // EIP-3860: initcode size limit and intrinsic gas (Shanghai+, applies to Prague/Osaka)
    var effective_gas_limit = tc.gas_limit;
    if (tc.is_create) {
        const MAX_INITCODE_SIZE: usize = 49152; // 2 * MAX_CODE_SIZE
        if (run_code.len > MAX_INITCODE_SIZE) {
            if (tc.expect_exception) {
                return .{ .result = .pass, .detail = .{ .reason = "expected initcode too large" } };
            }
            return .{ .result = .fail, .detail = .{ .reason = "initcode too large" } };
        }
        const initcode_gas: u64 = 2 * @as(u64, @intCast((run_code.len + 31) / 32));
        if (initcode_gas > effective_gas_limit) {
            if (tc.expect_exception) {
                return .{ .result = .pass, .detail = .{ .reason = "expected initcode gas OOG" } };
            }
            return .{ .result = .fail, .detail = .{ .reason = "initcode gas OOG" } };
        }
        effective_gas_limit -= initcode_gas;
    }

    // Build interpreter inputs
    const inputs = interpreter.InputsImpl{
        .caller = tc.caller,
        .target = effective_target,
        .value = tx_value,
        .data = @constCast(tc.calldata),
        .gas_limit = effective_gas_limit,
        .scheme = .call,
        .is_static = false,
        .depth = 0,
    };

    // Build interpreter
    const ext_bytecode = interpreter.ExtBytecode.new(bytecode_mod.Bytecode.newLegacy(run_code));
    var interp = interpreter.Interpreter.new(
        interpreter.Memory.new(),
        ext_bytecode,
        inputs,
        false,
        spec,
        effective_gas_limit,
    );
    defer interp.deinit();

    // Build host and execute
    var host = interpreter.Host{
        .ctx = &ctx,
        .run_sub_call = interpreter.protocol_schedule.runSubCallDefault,
        .precompiles = &schedule.precompiles,
        // Cache the instruction table pointer so sub-calls reuse it instead of
        // allocating a fresh 4 KB table on the native stack per recursive EVM call.
        .instruction_table = &schedule.instructions,
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
        // Top-level OOG/revert reverts ALL state changes back to pre-state.
        // Validate expected storage against the pre-state DB (not the journal).
        for (tc.expected_storage) |expected_acct| {
            for (expected_acct.storage) |entry| {
                const key = u256FromBeBytes(entry.key);
                const expected_val = u256FromBeBytes(entry.value);
                const actual_val = ctx.journaled_state.database.getStorage(expected_acct.address, key) catch 0;
                if (actual_val != expected_val) {
                    return .{ .result = .fail, .detail = .{
                        .reason = "execution error",
                        .exec_result = exec_result,
                        .opcode = interp.last_opcode,
                    } };
                }
            }
        }
        return .{ .result = .pass, .detail = .{ .reason = "ok (reverted)" } };
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
