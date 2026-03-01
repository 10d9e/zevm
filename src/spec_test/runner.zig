// Spec test runner: sets up pre-state, executes via MainnetHandler, validates storage.

const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const interpreter = @import("interpreter");
const context = @import("context");
const database = @import("database");
const state_mod = @import("state");
const types = @import("types");
const handler_mod = @import("handler");

const U256 = primitives.U256;
const InstructionResult = interpreter.InstructionResult;
const MainnetHandler = handler_mod.MainnetHandler;
const ValidationError = handler_mod.ValidationError;

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

    const tx_value = u256FromBeBytes(tc.value);

    // For CREATE transactions, compute the created contract address from sender + nonce
    // before building the DB (so we can pre-populate the account).
    var effective_target: [20]u8 = tc.target;
    var sender_nonce: u64 = 0;
    for (tc.pre_accounts) |acct| {
        if (std.mem.eql(u8, &acct.address, &tc.caller)) {
            sender_nonce = acct.nonce;
            break;
        }
    }

    if (tc.is_create) {
        effective_target = interpreter.host_module.createAddress(tc.caller, sender_nonce);

        // EIP-7610 / pre-existing CREATE collision check (must run before DB build):
        // If the target address already exists with non-zero nonce, non-empty code, or non-empty
        // storage, the CREATE fails immediately. Balance alone does NOT cause collision.
        for (tc.pre_accounts) |acct| {
            if (!std.mem.eql(u8, &acct.address, &effective_target)) continue;
            var has_collision = acct.nonce != 0 or acct.code.len > 0;
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
                // No exception expected: CREATE fails silently, validate against pre-state.
                for (tc.expected_storage) |expected_acct| {
                    for (expected_acct.storage) |entry| {
                        const expected_val = u256FromBeBytes(entry.value);
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
            // EIP-7702: if code is a delegation designator (0xef0100 || 20-byte-addr),
            // create an eip7702 bytecode so isEip7702() returns true during CALL dispatch.
            const code_bc = blk: {
                if (acct.code.len == 23 and
                    acct.code[0] == 0xef and acct.code[1] == 0x01 and acct.code[2] == 0x00)
                {
                    var delegation_addr: [20]u8 = undefined;
                    @memcpy(&delegation_addr, acct.code[3..23]);
                    break :blk bytecode_mod.Bytecode{
                        .eip7702 = bytecode_mod.Eip7702Bytecode.new(delegation_addr),
                    };
                }
                break :blk bytecode_mod.Bytecode.newLegacy(acct.code);
            };
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
    // InMemoryDB uses the GPA allocator; free its hash maps on all exit paths.
    defer ctx.journaled_state.database.deinit();

    // Osaka: EIP-7825 transaction gas limit cap = 2^24
    if (spec == .osaka) {
        ctx.cfg.tx_gas_limit_cap = 1 << 24;
    }
    // Disable tx chain_id check — spec test transactions don't carry chain_id
    ctx.cfg.tx_chain_id_check = false;

    // Pre-load all pre-state accounts into the journal so that sload/sstore can find them.
    for (tc.pre_accounts) |acct| {
        _ = ctx.journaled_state.loadAccount(acct.address) catch {
            return .{ .result = .err, .detail = .{ .reason = "OOM loading account into journal" } };
        };
    }

    // EIP-7702: Pre-load authority accounts into journal BEFORE the transaction_id bump.
    // This ensures setCode() can find them in evm_state, while the bump makes them appear
    // cold during execution (authorities are NOT pre-warmed per EIP-7702 spec).
    for (tc.authorization_entries) |auth_entry| {
        _ = ctx.journaled_state.loadAccount(auth_entry.authority) catch {};
    }

    // Bump transaction_id so pre-loaded accounts appear cold on first EVM access.
    // EIP-2929: only tx sender, recipient, precompiles, and access list entries are warm at tx start.
    ctx.journaled_state.inner.transaction_id += 1;

    // Set block env
    const blob_excess_gas_and_price: ?context.BlobExcessGasAndPrice =
        if (tc.blob_versioned_hashes_count > 0 or tc.excess_blob_gas > 0)
            context.BlobExcessGasAndPrice.new(tc.excess_blob_gas, primitives.BLOB_BASE_FEE_UPDATE_FRACTION_PRAGUE)
        else
            null;
    ctx.setBlock(context.BlockEnv{
        .number = u256FromBeBytes(tc.block_number),
        .beneficiary = tc.coinbase,
        .timestamp = u256FromBeBytes(tc.block_timestamp),
        .gas_limit = tc.block_gaslimit,
        .basefee = tc.block_basefee,
        .difficulty = u256FromBeBytes(tc.block_difficulty),
        .prevrandao = tc.prevrandao,
        .blob_excess_gas_and_price = blob_excess_gas_and_price,
    });

    // Build access list for TxEnv
    var access_list_items = std.ArrayList(context.AccessListItem){};
    for (tc.access_list) |entry| {
        var al_item = context.AccessListItem{
            .address = entry.address,
            .storage_keys = std.ArrayList(primitives.StorageKey){},
        };
        for (entry.storage_keys) |key_bytes| {
            al_item.storage_keys.append(std.heap.page_allocator, u256FromBeBytes(key_bytes)) catch {};
        }
        access_list_items.append(std.heap.page_allocator, al_item) catch {};
    }

    // Build authorization list for TxEnv.
    // Pad with Invalid entries so items.len == authorization_count (for correct intrinsic gas).
    var auth_list_items = std.ArrayList(context.Either){};
    for (tc.authorization_entries) |auth_entry| {
        const recovered = context.RecoveredAuthorization.newUnchecked(
            context.Authorization{
                .chain_id = @as(primitives.U256, auth_entry.chain_id),
                .address = auth_entry.address,
                .nonce = auth_entry.nonce,
            },
            context.RecoveredAuthority{ .Valid = auth_entry.authority },
        );
        auth_list_items.append(std.heap.page_allocator, context.Either{ .Right = recovered }) catch {};
    }
    // Pad invalid entries to ensure len == authorization_count for intrinsic gas calculation
    while (auth_list_items.items.len < @as(usize, tc.authorization_count)) {
        const invalid_auth = context.RecoveredAuthorization.newUnchecked(
            context.Authorization{ .chain_id = 0, .address = [_]u8{0} ** 20, .nonce = 0 },
            context.RecoveredAuthority.Invalid,
        );
        auth_list_items.append(std.heap.page_allocator, context.Either{ .Right = invalid_auth }) catch break;
    }

    // Build blob hashes list.
    // Set to Some([]) (not null) when max_fee_per_blob_gas > 0 OR hashes exist, so that
    // type_3 transactions with 0 blob hashes are detected and rejected by validateBlobTx.
    var blob_hashes_list: ?std.ArrayList(primitives.Hash) = null;
    if (tc.blob_versioned_hashes.len > 0 or tc.max_fee_per_blob_gas > 0) {
        var bh_list = std.ArrayList(primitives.Hash){};
        for (tc.blob_versioned_hashes) |hash| {
            bh_list.append(std.heap.page_allocator, hash) catch {};
        }
        blob_hashes_list = bh_list;
    }

    // Build calldata list
    var calldata_list: ?std.ArrayList(u8) = null;
    if (tc.calldata.len > 0) {
        var cd_list = std.ArrayList(u8){};
        cd_list.appendSlice(std.heap.page_allocator, tc.calldata) catch {};
        calldata_list = cd_list;
    }

    // Build TxEnv with all required fields
    const tx_env = context.TxEnv{
        .tx_type = 0,
        .caller = tc.caller,
        .gas_limit = tc.gas_limit,
        .gas_price = tc.gas_price,
        .kind = if (tc.is_create) context.TxKind.Create else context.TxKind{ .Call = effective_target },
        .value = tx_value,
        .data = calldata_list,
        .nonce = sender_nonce,
        .chain_id = null, // chain_id check disabled via cfg.tx_chain_id_check = false
        .access_list = context.AccessList{ .items = if (access_list_items.items.len > 0) access_list_items else null },
        .gas_priority_fee = tc.max_priority_fee_per_gas,
        .blob_hashes = blob_hashes_list,
        .max_fee_per_blob_gas = tc.max_fee_per_blob_gas,
        .authorization_list = if (tc.has_authorization_list) auth_list_items else null,
    };
    ctx.setTx(tx_env);

    // Build Evm (stack-allocated — instructions, precompiles, frame_stack are locals here)
    var instructions = handler_mod.Instructions.new(spec);
    var precompiles = handler_mod.Precompiles.new(spec);
    var frame_stack = handler_mod.FrameStack.new();
    var evm = handler_mod.Evm.init(&ctx, null, &instructions, &precompiles, &frame_stack);

    // ---------------------------------------------------------------------------
    // Validate: env checks, intrinsic gas, nonce, balance, blob fees
    // ---------------------------------------------------------------------------
    var initial_gas = handler_mod.InitialAndFloorGas{ .initial_gas = 0, .floor_gas = 0 };
    MainnetHandler.validate(&evm, &initial_gas) catch |err| {
        // Any validation error → expect_exception determines pass/fail
        if (tc.expect_exception) {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception: validation" } };
        }
        return .{ .result = .fail, .detail = .{ .reason = @errorName(err) } };
    };

    // ---------------------------------------------------------------------------
    // Pre-execution: warm precompiles, coinbase, access list, EIP-7702 delegation
    // ---------------------------------------------------------------------------
    MainnetHandler.preExecution(&evm) catch {
        if (tc.expect_exception) {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception: preExecution" } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "unexpected preExecution failure" } };
    };

    // ---------------------------------------------------------------------------
    // Execute frame
    // ---------------------------------------------------------------------------
    var frame_result = MainnetHandler.executeFrame(&evm, initial_gas.initial_gas) catch {
        if (tc.expect_exception) {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception: execution error" } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "unexpected execution error" } };
    };

    // ---------------------------------------------------------------------------
    // Post-execution: gas refund, floor gas, reimburse caller, pay beneficiary, commit
    // ---------------------------------------------------------------------------
    MainnetHandler.postExecution(&evm, &frame_result, initial_gas) catch {
        if (tc.expect_exception) {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception: postExecution" } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "unexpected postExecution failure" } };
    };

    // ---------------------------------------------------------------------------
    // Result handling
    // ---------------------------------------------------------------------------

    const exec_status = frame_result.result.status;
    const exec_succeeded = exec_status == .Success;

    // If we expect an exception, any non-success result is a pass
    if (tc.expect_exception) {
        if (!exec_succeeded) {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception occurred" } };
        }
        // Execution succeeded but exception was expected → fail
        return .{ .result = .fail, .detail = .{ .reason = "expected exception but execution succeeded" } };
    }

    if (!exec_succeeded) {
        // Execution failed/reverted — validate expected storage against pre-state DB
        // (all state changes were rolled back by executeFrame's checkpoint revert)
        for (tc.expected_storage) |expected_acct| {
            for (expected_acct.storage) |entry| {
                const key = u256FromBeBytes(entry.key);
                const expected_val = u256FromBeBytes(entry.value);
                const actual_val = ctx.journaled_state.database.getStorage(expected_acct.address, key) catch 0;
                if (actual_val != expected_val) {
                    return .{ .result = .fail, .detail = .{
                        .reason = "storage mismatch after revert",
                        .address = expected_acct.address,
                        .storage_key = entry.key,
                        .expected = entry.value,
                        .actual = u256ToBeBytes(actual_val),
                    } };
                }
            }
        }
        return .{ .result = .pass, .detail = .{ .reason = "ok (reverted)" } };
    }

    // ---------------------------------------------------------------------------
    // Validate expected storage (success path) — read from journal's evm_state
    // ---------------------------------------------------------------------------
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
                    actual_val = ctx.journaled_state.database.getStorage(expected_acct.address, key) catch 0;
                }
            } else {
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
