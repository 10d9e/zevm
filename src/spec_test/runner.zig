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

    // EIP-3607: Transaction sender must be an EOA (not a contract).
    // Exception: EIP-7702 delegation accounts (0xef0100 || 20-byte-addr = 23 bytes) are treated
    // as EOAs and may send transactions. Any other non-empty sender code => SENDER_NOT_EOA.
    {
        var sender_code: []const u8 = &.{};
        for (tc.pre_accounts) |acct| {
            if (std.mem.eql(u8, &acct.address, &tc.caller)) {
                sender_code = acct.code;
                break;
            }
        }
        if (sender_code.len > 0) {
            const is_delegation = sender_code.len == 23 and
                sender_code[0] == 0xef and
                sender_code[1] == 0x01 and
                sender_code[2] == 0x00;
            if (!is_delegation) {
                if (tc.expect_exception) {
                    return .{ .result = .pass, .detail = .{ .reason = "expected exception: SENDER_NOT_EOA" } };
                }
                return .{ .result = .fail, .detail = .{ .reason = "sender has contract code (EIP-3607)" } };
            }
        }
    }

    // EIP-1559 fee validation: maxFeePerGas must be >= baseFee, and maxPriorityFeePerGas
    // must not exceed maxFeePerGas. These are consensus-layer validity rules.
    {
        if (tc.gas_price < @as(u128, tc.block_basefee)) {
            if (tc.expect_exception) {
                return .{ .result = .pass, .detail = .{ .reason = "expected exception: INSUFFICIENT_MAX_FEE_PER_GAS" } };
            }
            return .{ .result = .fail, .detail = .{ .reason = "maxFeePerGas below baseFee" } };
        }
        if (tc.max_priority_fee_per_gas > tc.gas_price) {
            if (tc.expect_exception) {
                return .{ .result = .pass, .detail = .{ .reason = "expected exception: PRIORITY_GREATER_THAN_MAX_FEE_PER_GAS" } };
            }
            return .{ .result = .fail, .detail = .{ .reason = "maxPriorityFeePerGas exceeds maxFeePerGas" } };
        }
    }

    // EIP-7825 (Osaka+): transaction gas limit cap at 2^24 = 16_777_216
    if (spec == .osaka and tc.gas_limit > (1 << 24)) {
        if (tc.expect_exception) {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception: EIP-7825 gas limit cap" } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "EIP-7825 gas limit exceeded" } };
    }

    // Block gas limit: transaction gas limit must not exceed block gas limit.
    if (tc.gas_limit > tc.block_gaslimit) {
        if (tc.expect_exception) {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception: tx gas limit exceeds block gas limit" } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "tx gas limit exceeds block gas limit" } };
    }

    // EIP-4844 blob tx validity:
    //   1. A blob tx (has maxFeePerBlobGas) must have at least one blob versioned hash.
    //   2. A blob tx cannot be a CREATE transaction.
    //   3. All blob versioned hashes must have version byte 0x01.
    if (tc.max_fee_per_blob_gas > 0 and tc.blob_versioned_hashes_count == 0) {
        if (tc.expect_exception) {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception: blob tx with no blobs" } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "blob tx missing versioned hashes" } };
    }
    if (tc.is_create and tc.blob_versioned_hashes_count > 0) {
        if (tc.expect_exception) {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception: blob CREATE tx" } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "blob tx cannot be CREATE" } };
    }
    for (tc.blob_versioned_hashes) |hash| {
        if (hash[0] != 0x01) {
            if (tc.expect_exception) {
                return .{ .result = .pass, .detail = .{ .reason = "expected exception: invalid blob hash version" } };
            }
            return .{ .result = .fail, .detail = .{ .reason = "invalid blob hash version" } };
        }
    }

    // EIP-2681: for CREATE transactions, sender nonce must not be at u64 maximum.
    // A tx with nonce == MaxNonce would attempt to bump to MaxNonce+1, which is invalid.
    if (tc.is_create) {
        var sender_nonce: u64 = 0;
        for (tc.pre_accounts) |acct| {
            if (std.mem.eql(u8, &acct.address, &tc.caller)) {
                sender_nonce = acct.nonce;
                break;
            }
        }
        if (sender_nonce == std.math.maxInt(u64)) {
            if (tc.expect_exception) {
                return .{ .result = .pass, .detail = .{ .reason = "expected exception: NONCE_IS_MAX" } };
            }
            return .{ .result = .fail, .detail = .{ .reason = "CREATE with max sender nonce (EIP-2681)" } };
        }
    }

    // For CREATE transactions: the bytecode is the init code (calldata), run in context of the
    // newly created contract. For CALL transactions: the bytecode is the code at the target address.
    // NOTE: This is the initial pre-EIP-7702 code. For CALL txs where the target is an EIP-7702
    // authority, run_code will be updated below after EIP-7702 processing.
    var run_code: []const u8 = if (tc.is_create) tc.calldata else blk: {
        var target_code: []const u8 = &.{};
        for (tc.pre_accounts) |acct| {
            if (std.mem.eql(u8, &acct.address, &tc.target)) {
                target_code = acct.code;
                break;
            }
        }
        break :blk target_code;
    };

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

    // EIP-7702: Pre-load authority accounts into journal BEFORE the transaction_id bump.
    // This ensures setCode() can find them in evm_state, while the bump makes them appear
    // cold during execution (authorities are NOT pre-warmed per EIP-7702 spec).
    for (tc.authorization_entries) |auth_entry| {
        _ = ctx.journaled_state.loadAccount(auth_entry.authority) catch {};
    }

    // Bump transaction_id so pre-loaded accounts appear cold on first EVM access.
    // EIP-2929: only tx sender, recipient, precompiles, and access list entries are warm at
    // tx start. Pre-loaded accounts get transaction_id=0; incrementing the journal's
    // transaction_id to 1 causes isColdTransactionId(1) to return true for those accounts.
    // Addresses in warm_addresses (precompiles, coinbase) override this and stay warm.
    ctx.journaled_state.inner.transaction_id += 1;

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

    // Pre-deduct gas cost from sender balance before execution, and bump sender nonce.
    // EVM spec: sender pays gas_limit * effective_gas_price upfront, before any code runs.
    // The nonce increment makes the sender "non-empty" even if balance drops to 0, preventing
    // incorrect 25000 "new account" charges in CALL/SELFDESTRUCT to the sender address.
    {
        const gas_cost: U256 = @as(U256, tc.gas_limit) * @as(U256, tc.gas_price);
        if (ctx.journaled_state.inner.evm_state.getPtr(tc.caller)) |acct| {
            acct.info.balance -|= gas_cost;
            acct.info.nonce +|= 1; // Tx sender nonce is always incremented before execution
        }
    }

    // EIP-4844: deduct blob fee from sender balance before execution.
    // Tests that read address(sender).balance during execution expect it to already reflect
    // the blob fee deduction. blob_fee = blob_count * GAS_PER_BLOB * blob_gasprice.
    if (tc.blob_versioned_hashes_count > 0) {
        const bp = context.BlobExcessGasAndPrice.new(tc.excess_blob_gas, primitives.BLOB_BASE_FEE_UPDATE_FRACTION_PRAGUE);
        const blob_fee: U256 = @as(U256, tc.blob_versioned_hashes_count) *
            @as(U256, primitives.GAS_PER_BLOB) *
            @as(U256, bp.blob_gasprice);
        if (ctx.journaled_state.inner.evm_state.getPtr(tc.caller)) |acct| {
            acct.info.balance -|= blob_fee;
        }
    }

    // Set block env (include blob gas info when relevant for EIP-4844)
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

    // Set tx env
    var tx_env = context.TxEnv.default();
    tx_env.gas_price = tc.gas_price;
    // EIP-1559: set priority fee so GASPRICE opcode returns min(basefee+tip, maxFee).
    // For legacy txs, max_priority_fee_per_gas == 0 and gas_priority_fee stays null.
    if (tc.max_priority_fee_per_gas > 0) {
        tx_env.gas_priority_fee = tc.max_priority_fee_per_gas;
    }
    tx_env.caller = tc.caller;
    // EIP-4844: set blob versioned hashes so BLOBHASH opcode returns the correct values.
    if (tc.blob_versioned_hashes.len > 0) {
        var bh_list = std.ArrayList(primitives.Hash){};
        for (tc.blob_versioned_hashes) |hash| {
            bh_list.append(std.heap.page_allocator, hash) catch {};
        }
        tx_env.blob_hashes = bh_list;
    }
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

    // Pre-warm EIP-2929: tx sender and destination are always warm at tx start
    {
        const warm_addresses = &ctx.journaled_state.inner.warm_addresses.access_list;
        for ([_][20]u8{ tc.caller, effective_target }) |addr| {
            const gop = warm_addresses.getOrPut(addr) catch continue;
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList(primitives.StorageKey){};
            }
        }
    }

    // Pre-warm EIP-2930 access list addresses and storage keys
    {
        const warm_addresses = &ctx.journaled_state.inner.warm_addresses.access_list;
        for (tc.access_list) |entry| {
            const gop = warm_addresses.getOrPut(entry.address) catch continue;
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList(primitives.StorageKey){};
            }
            for (entry.storage_keys) |key_bytes| {
                const key: primitives.StorageKey = u256FromBeBytes(key_bytes);
                gop.value_ptr.append(std.heap.page_allocator, key) catch {};
            }
        }
    }

    // EIP-7702: Apply code delegation and pre-warm authority addresses.
    // Per EIP-7702 spec, processing order for each tuple:
    //   Step 1: Verify chain_id == 0 or current chain (if wrong, skip entirely)
    //   Step 4: Add authority to accessed_addresses UNCONDITIONALLY (before code/nonce checks)
    //   Step 5: Verify authority code is empty or existing EIP-7702 delegation (if not, skip code setting)
    //   Step 6: Verify authority nonce matches (if wrong, skip code setting but authority already warmed)
    //   Step 8: Set code delegation
    //   Step 9: Increment authority nonce
    {
        // Track per-authority nonce bumps: after a valid entry, nonce increments.
        // Use a small stack buffer since authorization lists are typically short.
        const MAX_AUTH = 256;
        var nonce_track_addrs: [MAX_AUTH][20]u8 = undefined;
        var nonce_track_vals: [MAX_AUTH]u64 = undefined;
        var nonce_track_len: usize = 0;

        const warm_addresses = &ctx.journaled_state.inner.warm_addresses.access_list;

        for (tc.authorization_entries) |auth_entry| {
            // Step 1: chain_id must be 0 (any chain) or 1 (mainnet) - wrong chain skips entirely
            if (auth_entry.chain_id != 0 and auth_entry.chain_id != 1) continue;

            // Step 4: Add authority to accessed_addresses UNCONDITIONALLY for valid chain_id.
            // Even if nonce or code check fails, the authority is already in the access list.
            if (warm_addresses.getOrPut(auth_entry.authority)) |gop| {
                if (!gop.found_existing) {
                    gop.value_ptr.* = std.ArrayList(primitives.StorageKey){};
                }
            } else |_| {}

            // Step 5: authority must have empty code OR existing EIP-7702 delegation code.
            // Contract code (non-empty, non-delegation) makes the entry invalid for code setting.
            var auth_has_contract_code = false;
            for (tc.pre_accounts) |pa| {
                if (std.mem.eql(u8, &pa.address, &auth_entry.authority)) {
                    if (pa.code.len > 0) {
                        // EIP-7702 delegation designator: exactly 23 bytes starting with 0xef0100
                        const is_delegation = pa.code.len == 23 and
                            pa.code[0] == 0xef and
                            pa.code[1] == 0x01 and
                            pa.code[2] == 0x00;
                        auth_has_contract_code = !is_delegation;
                    }
                    break;
                }
            }
            if (auth_has_contract_code) continue; // authority already warmed above

            // Step 6: nonce must match authority's current nonce.
            // Start from pre_accounts nonce, then add any bumps from prior valid entries.
            var current_nonce: u64 = 0;
            for (tc.pre_accounts) |pa| {
                if (std.mem.eql(u8, &pa.address, &auth_entry.authority)) {
                    current_nonce = pa.nonce;
                    break;
                }
            }
            // Self-sponsored: if authority == tx sender, their nonce was already bumped
            // by tx validation before auth list processing begins.
            if (std.mem.eql(u8, &auth_entry.authority, &tc.caller)) {
                current_nonce +|= 1;
            }
            // Add bumps from prior valid entries targeting same authority
            for (0..nonce_track_len) |i| {
                if (std.mem.eql(u8, &nonce_track_addrs[i], &auth_entry.authority)) {
                    current_nonce +|= nonce_track_vals[i];
                }
            }
            if (auth_entry.nonce != current_nonce) continue; // authority already warmed above
            // Per EIP-7702: if nonce + 1 would overflow u64, skip this tuple.
            if (current_nonce == std.math.maxInt(u64)) continue; // nonce overflow: skip

            // Steps 8+9: Valid entry — apply code delegation and bump nonce tracking.
            // setCode() handles zero address → clearing code (sets KECCAK_EMPTY hash).
            const bc = bytecode_mod.Bytecode{ .eip7702 = bytecode_mod.Eip7702Bytecode.new(auth_entry.address) };
            ctx.journaled_state.inner.setCode(auth_entry.authority, bc);

            if (nonce_track_len < MAX_AUTH) {
                nonce_track_addrs[nonce_track_len] = auth_entry.authority;
                nonce_track_vals[nonce_track_len] = 1;
                nonce_track_len += 1;
            }
        }
    }

    // After EIP-7702 processing: for CALL transactions, update run_code to follow delegation.
    // The TX target may be an authority that just got delegation code set (e.g., self-delegating
    // tx where `to` = the authority). In that case, the effective code is the delegation target's.
    if (!tc.is_create) {
        if (ctx.journaled_state.inner.evm_state.getPtr(effective_target)) |acct| {
            if (acct.info.code) |code| {
                if (code.isEip7702()) {
                    const delegation_addr = code.eip7702.address;
                    // Look up the delegation target's code (journal first, then pre_accounts)
                    run_code = blk: {
                        if (ctx.journaled_state.inner.evm_state.getPtr(delegation_addr)) |del_acct| {
                            if (del_acct.info.code) |del_bc| {
                                // Nested delegation = empty per spec
                                if (del_bc.isEip7702()) break :blk &.{};
                                break :blk del_bc.originalBytes();
                            }
                        }
                        for (tc.pre_accounts) |pa| {
                            if (std.mem.eql(u8, &pa.address, &delegation_addr)) {
                                // Nested delegation not allowed
                                if (pa.code.len == 23 and pa.code[0] == 0xef and pa.code[1] == 0x01 and pa.code[2] == 0x00) {
                                    break :blk &.{};
                                }
                                break :blk pa.code;
                            }
                        }
                        break :blk &.{};
                    };
                }
            }
        }
        // Deferred "no code" check (now after EIP-7702 delegation is resolved)
        if (run_code.len == 0) {
            if (tc.expect_exception) {
                return .{ .result = .pass, .detail = .{ .reason = "expected exception with no code" } };
            }
            if (tc.expected_storage.len == 0) {
                return .{ .result = .pass, .detail = .{ .reason = "no code, no expectations" } };
            }
            // No code runs: storage is unchanged from pre-state.
            // Validate expected storage against pre-state DB.
            for (tc.expected_storage) |expected_acct| {
                for (expected_acct.storage) |entry| {
                    const key = u256FromBeBytes(entry.key);
                    const expected_val = u256FromBeBytes(entry.value);
                    const actual_val = ctx.journaled_state.database.getStorage(expected_acct.address, key) catch 0;
                    if (actual_val != expected_val) {
                        return .{ .result = .fail, .detail = .{
                            .reason = "storage mismatch (no code target)",
                            .address = expected_acct.address,
                            .storage_key = entry.key,
                            .expected = entry.value,
                            .actual = u256ToBeBytes(actual_val),
                        } };
                    }
                }
            }
            return .{ .result = .pass, .detail = .{ .reason = "no code, storage preserved" } };
        }
    }

    // Intrinsic gas validation: reject transactions whose gas_limit is below the minimum cost.
    // EIP-7623 (Prague+): Two separate minimums apply, gas_limit must satisfy both:
    //   1. standard_intrinsic = base + 4*zero + 16*nonzero + access_list_gas + auth_gas
    //   2. floor_gas = base + 10*zero + 40*nonzero  (calldata ONLY, no access list, no auth)
    // gas_limit must be >= max(standard_intrinsic, floor_gas).
    // standard_intrinsic is also used below to set the interpreter's starting gas correctly.
    const standard_intrinsic: u64 = blk: {
        const base_gas: u64 = if (tc.is_create) 53000 else 21000;
        var standard_calldata_gas: u64 = 0;
        var floor_calldata_gas: u64 = 0;
        for (tc.calldata) |byte| {
            if (byte == 0) {
                standard_calldata_gas += 4;
                floor_calldata_gas += 10;
            } else {
                standard_calldata_gas += 16;
                floor_calldata_gas += 40;
            }
        }
        const access_list_gas: u64 =
            @as(u64, tc.access_list_addr_count) * 2400 +
            @as(u64, tc.access_list_slot_count) * 1900;
        const auth_gas: u64 = @as(u64, tc.authorization_count) * 25000;
        // EIP-3860: initcode gas is part of intrinsic gas for CREATE (Shanghai+)
        const initcode_words: u64 = if (tc.is_create) @as(u64, @intCast((tc.calldata.len + 31) / 32)) else 0;
        const initcode_intrinsic: u64 = initcode_words * 2;
        // Note: EIP-4844 blob gas is a separate fee market, NOT part of execution intrinsic gas.
        // Blob fees are validated separately in the sender balance check below.
        const si = base_gas + standard_calldata_gas + access_list_gas + auth_gas + initcode_intrinsic;
        // EIP-7623 floor: always 21000 + floor_calldata (fixed base, excludes CREATE's extra
        // 32000, access list gas, and auth gas). Per EIP-7623 spec.
        const floor_gas = 21000 + floor_calldata_gas;
        const min_gas = @max(si, floor_gas);

        if (tc.gas_limit < min_gas) {
            if (tc.expect_exception) {
                return .{ .result = .pass, .detail = .{ .reason = "expected exception: intrinsic gas" } };
            }
            return .{ .result = .fail, .detail = .{ .reason = "gas_limit below intrinsic" } };
        }
        break :blk si;
    };

    // Sender balance check: sender must have sufficient ETH to cover gas cost + tx value + blob cost.
    // Sender not in pre-state has balance 0.
    {
        var sender_balance: U256 = 0;
        for (tc.pre_accounts) |acct| {
            if (std.mem.eql(u8, &acct.address, &tc.caller)) {
                sender_balance = u256FromBeBytes(acct.balance);
                break;
            }
        }
        const gas_cost: U256 = @as(U256, tc.gas_limit) * @as(U256, tc.gas_price);
        var total_cost = gas_cost + tx_value;
        // EIP-4844: blob cost = blob_count * GAS_PER_BLOB * blob_gasprice
        if (tc.blob_versioned_hashes_count > 0) {
            const blob_gasprice = context.BlobExcessGasAndPrice.new(
                tc.excess_blob_gas,
                primitives.BLOB_BASE_FEE_UPDATE_FRACTION_PRAGUE,
            ).blob_gasprice;
            const blob_cost: U256 = @as(U256, tc.blob_versioned_hashes_count) *
                @as(U256, primitives.GAS_PER_BLOB) *
                @as(U256, blob_gasprice);
            total_cost += blob_cost;
        }
        if (total_cost > sender_balance) {
            if (tc.expect_exception) {
                return .{ .result = .pass, .detail = .{ .reason = "expected exception: insufficient balance" } };
            }
            return .{ .result = .fail, .detail = .{ .reason = "insufficient sender balance" } };
        }
    }

    // EIP-3860: initcode size limit (Shanghai+, applies to Prague/Osaka).
    if (tc.is_create) {
        const MAX_INITCODE_SIZE: usize = 49152; // 2 * MAX_CODE_SIZE
        if (run_code.len > MAX_INITCODE_SIZE) {
            if (tc.expect_exception) {
                return .{ .result = .pass, .detail = .{ .reason = "expected initcode too large" } };
            }
            return .{ .result = .fail, .detail = .{ .reason = "initcode too large" } };
        }
    }

    // The interpreter starts with gas_limit minus the full intrinsic cost.
    // This ensures gas measurements (GAS opcode) reflect the actual execution budget
    // and that EVM execution does not "see" the gas used for intrinsic overhead.
    // standard_intrinsic already includes initcode_intrinsic for CREATE transactions.
    // EIP-4844: blob gas is a separate fee market and does NOT reduce the execution gas limit.
    const effective_gas_limit = tc.gas_limit - standard_intrinsic;

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

    // Check for execution errors or explicit REVERT
    if (exec_result.isError() or exec_result == .revert) {
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
