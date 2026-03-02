// Spec test runner entry point.
// Reads JSON fixture files at runtime, parses test cases, and runs them.
// Usage: spec-test-runner [fixture-dir] [--fork=NAME] [--filter=SUBSTR] [--fail-fast] [--verbose]

const std = @import("std");
const runner = @import("runner");
const types = @import("types");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var fixture_dir: []const u8 = "spec-tests/fixtures/state_tests";
    var fork_filter: ?[]const u8 = null;
    var name_filter: ?[]const u8 = null;
    var fail_fast = false;
    var verbose = false;

    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--fork=")) {
            fork_filter = arg[7..];
        } else if (std.mem.startsWith(u8, arg, "--filter=")) {
            name_filter = arg[9..];
        } else if (std.mem.eql(u8, arg, "--fail-fast")) {
            fail_fast = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (!std.mem.startsWith(u8, arg, "--")) {
            fixture_dir = arg;
        }
    }

    var passed: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;
    var errors: usize = 0;

    var stdout_w = std.fs.File.stdout().writerStreaming(&.{});
    const stdout = &stdout_w.interface;

    var timer = try std.time.Timer.start();

    // Collect JSON file paths first so we can open a fresh dir handle per file
    var json_paths: std.ArrayList([]u8) = .{};
    defer {
        for (json_paths.items) |p| allocator.free(p);
        json_paths.deinit(allocator);
    }

    {
        var dir = std.fs.cwd().openDir(fixture_dir, .{ .iterate = true }) catch |err| {
            std.debug.print("Error: Cannot open fixture directory '{s}': {}\n", .{ fixture_dir, err });
            std.process.exit(1);
        };
        defer dir.close();

        var walker = try dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.basename, ".json")) continue;
            const full = try std.fs.path.join(allocator, &.{ fixture_dir, entry.path });
            try json_paths.append(allocator, full);
        }
    }

    for (json_paths.items) |json_path| {
        // Arena covers all allocations for this fixture file
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const file_data = std.fs.cwd().readFileAlloc(a, json_path, 256 * 1024 * 1024) catch |err| {
            std.debug.print("Warning: Could not read {s}: {}\n", .{ json_path, err });
            continue;
        };

        const parsed = std.json.parseFromSlice(std.json.Value, a, file_data, .{}) catch |err| {
            std.debug.print("Warning: Could not parse {s}: {}\n", .{ json_path, err });
            continue;
        };

        const root = parsed.value;
        if (root != .object) continue;

        // If any top-level key contains "fork_Osaka", skip matching "fork_Prague" entries
        var has_osaka = false;
        {
            var it = root.object.iterator();
            while (it.next()) |kv| {
                if (std.mem.indexOf(u8, kv.key_ptr.*, "fork_Osaka") != null) {
                    has_osaka = true;
                    break;
                }
            }
        }

        var test_iter = root.object.iterator();
        while (test_iter.next()) |test_entry| {
            const test_name = test_entry.key_ptr.*;
            const test_obj = test_entry.value_ptr.*;
            if (test_obj != .object) continue;
            if (has_osaka and std.mem.indexOf(u8, test_name, "fork_Prague") != null) continue;

            var cases: std.ArrayList(types.TestCase) = .{};
            parseTestCases(a, test_name, &test_obj.object, &cases) catch |err| {
                std.debug.print("Warning: Error parsing {s}: {}\n", .{ test_name, err });
                continue;
            };

            for (cases.items) |tc| {
                if (fork_filter) |ff| {
                    if (!std.mem.eql(u8, tc.fork, ff)) {
                        skipped += 1;
                        continue;
                    }
                }
                if (name_filter) |nf| {
                    if (std.mem.indexOf(u8, tc.name, nf) == null) {
                        skipped += 1;
                        continue;
                    }
                }

                const outcome = runner.runTestCase(tc, allocator);
                switch (outcome.result) {
                    .pass => {
                        passed += 1;
                        if (verbose) try stdout.print("PASS {s}\n", .{tc.name});
                    },
                    .fail => {
                        failed += 1;
                        try stdout.print("FAIL {s}\n", .{tc.name});
                        try printDetail(stdout, outcome.detail);
                        if (fail_fast) {
                            try stdout.print("\n--fail-fast: stopping after first failure\n", .{});
                            try printSummary(stdout, passed, failed, skipped, errors, timer.read());
                            std.process.exit(1);
                        }
                    },
                    .skip => skipped += 1,
                    .err => {
                        errors += 1;
                        try stdout.print("ERROR {s}\n", .{tc.name});
                        try printDetail(stdout, outcome.detail);
                        if (fail_fast) {
                            try stdout.print("\n--fail-fast: stopping after first error\n", .{});
                            try printSummary(stdout, passed, failed, skipped, errors, timer.read());
                            std.process.exit(1);
                        }
                    },
                }
            }
        }
    }

    try printSummary(stdout, passed, failed, skipped, errors, timer.read());

    if (failed > 0 or errors > 0) {
        std.process.exit(1);
    }
}

// ---------------------------------------------------------------------------
// JSON parsing — produces types.TestCase values from fixture objects
// ---------------------------------------------------------------------------

fn parseTestCases(
    a: std.mem.Allocator,
    test_name: []const u8,
    obj: *const std.json.ObjectMap,
    out: *std.ArrayList(types.TestCase),
) !void {
    const env_val = obj.get("env") orelse return;
    if (env_val != .object) return;
    const pre_val = obj.get("pre") orelse return;
    if (pre_val != .object) return;
    const tx_val = obj.get("transaction") orelse return;
    if (tx_val != .object) return;
    const post_val = obj.get("post") orelse return;
    if (post_val != .object) return;

    // Block env
    const coinbase = try parseAddress(getStr(env_val.object, "currentCoinbase") orelse return);
    const block_number = try parseU256Hex(getStr(env_val.object, "currentNumber") orelse "0x0");
    const block_timestamp = try parseU256Hex(getStr(env_val.object, "currentTimestamp") orelse "0x0");
    const block_gaslimit = try parseU64Hex(getStr(env_val.object, "currentGasLimit") orelse "0x0");
    const block_basefee = try parseU64Hex(getStr(env_val.object, "currentBaseFee") orelse "0x0");
    const block_difficulty = try parseU256Hex(getStr(env_val.object, "currentDifficulty") orelse "0x0");
    const prevrandao = try parseU256Hex(
        getStr(env_val.object, "currentRandom") orelse
            getStr(env_val.object, "currentDifficulty") orelse "0x0",
    );

    // Transaction scalar fields
    const tx_sender = try parseAddress(getStr(tx_val.object, "sender") orelse return);
    const tx_to_str = getStr(tx_val.object, "to") orelse "";
    const is_create = tx_to_str.len == 0;
    const tx_to: [20]u8 = if (is_create) [_]u8{0} ** 20 else try parseAddress(tx_to_str);
    // For EIP-1559 txs (maxFeePerGas present): store max_fee and tip separately.
    // The handler computes effective_gas_price = min(max_fee, baseFee + tip) internally.
    // Balance validation must use max_fee (worst-case), not effective price.
    // For legacy txs (gasPrice present): gas_price = gasPrice, max_priority_fee = null.
    const tx_gas_price: u128 = blk: {
        if (getStr(tx_val.object, "gasPrice")) |gp| {
            // Legacy tx: gas_price is the single gasPrice field.
            // Saturate on overflow so balance check will reject (expect_exception).
            break :blk parseU128Hex(gp) catch std.math.maxInt(u128);
        } else if (getStr(tx_val.object, "maxFeePerGas")) |mfpg| {
            // EIP-1559 tx: store maxFeePerGas (not effective price) for correct balance validation.
            break :blk parseU128Hex(mfpg) catch std.math.maxInt(u128);
        } else {
            break :blk 0;
        }
    };
    // max_priority_fee: null for legacy txs, Some(tip) for EIP-1559 (even when tip == 0).
    // The ?u128 type lets the runner distinguish legacy from EIP-1559 with zero tip.
    const tx_max_priority_fee: ?u128 = blk: {
        if (getStr(tx_val.object, "maxPriorityFeePerGas")) |tip_str| {
            break :blk parseU128Hex(tip_str) catch 0;
        }
        break :blk null; // legacy tx — no priority fee field
    };

    // Transaction arrays
    const tx_data_arr = tx_val.object.get("data") orelse return;
    if (tx_data_arr != .array) return;
    const tx_gas_arr = tx_val.object.get("gasLimit") orelse return;
    if (tx_gas_arr != .array) return;
    const tx_value_arr = tx_val.object.get("value") orelse return;
    if (tx_value_arr != .array) return;

    // Pre-state accounts (shared across all post entries for this test)
    var pre_list: std.ArrayList(types.PreAccount) = .{};
    {
        var pre_iter = pre_val.object.iterator();
        while (pre_iter.next()) |pe| {
            const acct = pe.value_ptr.*;
            if (acct != .object) continue;
            const addr = parseAddress(pe.key_ptr.*) catch continue;
            const balance = parseU256Hex(getStr(acct.object, "balance") orelse "0x0") catch continue;
            const nonce = parseU64Hex(getStr(acct.object, "nonce") orelse "0x0") catch continue;
            const code = hexToBytes(a, getStr(acct.object, "code") orelse "0x") catch continue;

            var stor_list: std.ArrayList(types.StorageEntry) = .{};
            if (acct.object.get("storage")) |sv| {
                if (sv == .object) {
                    var si = sv.object.iterator();
                    while (si.next()) |se| {
                        const k = parseU256Hex(se.key_ptr.*) catch continue;
                        const v = parseU256Hex(getJsonStr(se.value_ptr.*) orelse continue) catch continue;
                        stor_list.append(a, .{ .key = k, .value = v }) catch continue;
                    }
                }
            }

            pre_list.append(a, .{
                .address = addr,
                .balance = balance,
                .nonce = nonce,
                .code = code,
                .storage = stor_list.items,
            }) catch continue;
        }
    }

    // Prefer Osaka, fall back to Prague
    const fork_priority = [_][]const u8{ "Osaka", "Prague" };
    var fork_name: []const u8 = undefined;
    var post_fork: std.json.Value = undefined;
    var found = false;
    for (fork_priority) |fn_| {
        if (post_val.object.get(fn_)) |pf| {
            if (pf == .array) {
                fork_name = fn_;
                post_fork = pf;
                found = true;
                break;
            }
        }
    }
    if (!found) return;

    for (post_fork.array.items) |post_entry| {
        if (post_entry != .object) continue;
        const indexes = post_entry.object.get("indexes") orelse continue;
        if (indexes != .object) continue;

        const di = getUint(indexes.object, "data") orelse continue;
        const gi = getUint(indexes.object, "gas") orelse continue;
        const vi = getUint(indexes.object, "value") orelse continue;

        if (di >= tx_data_arr.array.items.len) continue;
        if (gi >= tx_gas_arr.array.items.len) continue;
        if (vi >= tx_value_arr.array.items.len) continue;

        const calldata = hexToBytes(a, getJsonStr(tx_data_arr.array.items[di]) orelse continue) catch continue;
        const gas_limit = parseU64Hex(getJsonStr(tx_gas_arr.array.items[gi]) orelse continue) catch continue;
        const value = parseU256Hex(getJsonStr(tx_value_arr.array.items[vi]) orelse continue) catch continue;

        // EIP-2930: parse access list for this variation (per-data-index or shared)
        var al_addr_count: u32 = 0;
        var al_slot_count: u32 = 0;
        var al_entries: std.ArrayList(types.AccessListEntry) = .{};
        {
            const al_opt: ?std.json.Value = blk: {
                if (tx_val.object.get("accessLists")) |als| {
                    if (als == .array and di < als.array.items.len) break :blk als.array.items[di];
                }
                break :blk tx_val.object.get("accessList");
            };
            if (al_opt) |al| {
                if (al == .array) {
                    al_addr_count = @intCast(al.array.items.len);
                    for (al.array.items) |item| {
                        if (item != .object) continue;
                        const item_addr = parseAddress(getStr(item.object, "address") orelse continue) catch continue;
                        var key_list: std.ArrayList([32]u8) = .{};
                        if (item.object.get("storageKeys")) |sk| {
                            if (sk == .array) {
                                al_slot_count += @intCast(sk.array.items.len);
                                for (sk.array.items) |key_val| {
                                    const key_str = getJsonStr(key_val) orelse continue;
                                    const key_bytes = parseU256Hex(key_str) catch continue;
                                    key_list.append(a, key_bytes) catch continue;
                                }
                            }
                        }
                        al_entries.append(a, .{
                            .address = item_addr,
                            .storage_keys = key_list.items,
                        }) catch continue;
                    }
                }
            }
        }

        // EIP-7702: count authorization tuples for intrinsic gas (25000 per tuple)
        // Extract (authority → delegation target) pairs for code setting.
        // Also capture chain_id and nonce for validity checking in the runner.
        // has_authorization_list: true when the JSON field exists (even for empty lists),
        // so the runner can set tx.authorization_list = Some([]) and trigger empty-list rejection.
        var auth_count: u32 = 0;
        var has_authorization_list = false;
        var auth_entries: std.ArrayList(types.AuthorizationEntry) = .{};
        if (tx_val.object.get("authorizationList")) |al| {
            if (al == .array) {
                has_authorization_list = true;
                auth_count = @intCast(al.array.items.len);
                for (al.array.items) |entry| {
                    if (entry != .object) continue;
                    const signer_str = getStr(entry.object, "signer") orelse continue;
                    const signer_addr = parseAddress(signer_str) catch continue;
                    const delegate_str = getStr(entry.object, "address") orelse continue;
                    const delegate_addr = parseAddress(delegate_str) catch continue;
                    const chain_id = parseU64Hex(getStr(entry.object, "chainId") orelse "0x0") catch 0;
                    const entry_nonce = parseU64Hex(getStr(entry.object, "nonce") orelse "0x0") catch 0;
                    auth_entries.append(a, .{
                        .authority = signer_addr,
                        .address = delegate_addr,
                        .chain_id = chain_id,
                        .nonce = entry_nonce,
                    }) catch {};
                }
            }
        }

        // EIP-4844: parse blob fields
        var blob_hashes_count: u32 = 0;
        var blob_hash_list: std.ArrayList([32]u8) = .{};
        if (tx_val.object.get("blobVersionedHashes")) |bvh| {
            if (bvh == .array) {
                blob_hashes_count = @intCast(bvh.array.items.len);
                for (bvh.array.items) |hash_val| {
                    const hash_str = getJsonStr(hash_val) orelse continue;
                    const hash_bytes = parseU256Hex(hash_str) catch continue;
                    blob_hash_list.append(a, hash_bytes) catch continue;
                }
            }
        }
        const max_fee_per_blob_gas = parseU128Hex(
            getStr(tx_val.object, "maxFeePerBlobGas") orelse "0x0",
        ) catch 0;
        const excess_blob_gas = parseU64Hex(
            getStr(env_val.object, "currentExcessBlobGas") orelse "0x0",
        ) catch 0;

        const expect_exception = post_entry.object.get("expectException") != null;

        const expected_state = post_entry.object.get("state") orelse continue;
        if (expected_state != .object) continue;

        var exp_list: std.ArrayList(types.ExpectedAccount) = .{};
        {
            var ei = expected_state.object.iterator();
            while (ei.next()) |ee| {
                const ea = ee.value_ptr.*;
                if (ea != .object) continue;
                const addr2 = parseAddress(ee.key_ptr.*) catch continue;

                // Parse balance, nonce, code (always present in fixture post.state entries)
                const balance = parseU256Hex(getStr(ea.object, "balance") orelse "0x0") catch [_]u8{0} ** 32;
                const nonce = parseU64Hex(getStr(ea.object, "nonce") orelse "0x0") catch 0;
                const code = hexToBytes(a, getStr(ea.object, "code") orelse "0x") catch &[_]u8{};

                // Parse storage (may be absent or empty)
                var sl: std.ArrayList(types.StorageEntry) = .{};
                if (ea.object.get("storage")) |sv| {
                    if (sv == .object) {
                        var si2 = sv.object.iterator();
                        while (si2.next()) |se2| {
                            const k = parseU256Hex(se2.key_ptr.*) catch continue;
                            const v = parseU256Hex(getJsonStr(se2.value_ptr.*) orelse continue) catch continue;
                            sl.append(a, .{ .key = k, .value = v }) catch continue;
                        }
                    }
                }

                exp_list.append(a, .{
                    .address = addr2,
                    .balance = balance,
                    .nonce = nonce,
                    .code = code,
                    .storage = sl.items,
                }) catch continue;
            }
        }

        const name = try std.fmt.allocPrint(a, "{s}_{s}_{d}_{d}_{d}", .{ test_name, fork_name, di, gi, vi });

        try out.append(a, .{
            .name = name,
            .fork = fork_name,
            .coinbase = coinbase,
            .block_number = block_number,
            .block_timestamp = block_timestamp,
            .block_gaslimit = block_gaslimit,
            .block_basefee = block_basefee,
            .block_difficulty = block_difficulty,
            .prevrandao = prevrandao,
            .caller = tx_sender,
            .target = tx_to,
            .is_create = is_create,
            .value = value,
            .calldata = calldata,
            .gas_limit = gas_limit,
            .gas_price = tx_gas_price,
            .max_priority_fee_per_gas = tx_max_priority_fee,
            .access_list_addr_count = al_addr_count,
            .access_list_slot_count = al_slot_count,
            .access_list = al_entries.items,
            .authorization_count = auth_count,
            .has_authorization_list = has_authorization_list,
            .authorization_entries = auth_entries.items,
            .blob_versioned_hashes_count = blob_hashes_count,
            .blob_versioned_hashes = blob_hash_list.items,
            .max_fee_per_blob_gas = max_fee_per_blob_gas,
            .excess_blob_gas = excess_blob_gas,
            .pre_accounts = pre_list.items,
            .expected_storage = exp_list.items,
            .expect_exception = expect_exception,
        });
    }
}

// ---------------------------------------------------------------------------
// Parsing helpers (ported from generator.zig)
// ---------------------------------------------------------------------------

fn getStr(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    return getJsonStr(obj.get(key) orelse return null);
}

fn getJsonStr(val: std.json.Value) ?[]const u8 {
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

fn getUint(obj: std.json.ObjectMap, key: []const u8) ?usize {
    return switch (obj.get(key) orelse return null) {
        .integer => |i| @intCast(i),
        else => null,
    };
}

fn parseAddress(hex: []const u8) ![20]u8 {
    const s = stripPrefix(hex);
    var addr: [20]u8 = [_]u8{0} ** 20;
    if (s.len == 0) return addr;
    const start: usize = if (s.len > 40) s.len - 40 else 0;
    const padded = s.len - start;
    const byte_len = (padded + 1) / 2;
    const offset = 20 - byte_len;
    var i: usize = 0;
    var si = start;
    if (padded % 2 == 1) {
        addr[offset] = try hexDigit(s[si]);
        si += 1;
        i = 1;
    }
    while (si + 1 < s.len) {
        addr[offset + i] = (try hexDigit(s[si])) << 4 | try hexDigit(s[si + 1]);
        si += 2;
        i += 1;
    }
    return addr;
}

fn parseU256Hex(hex: []const u8) ![32]u8 {
    const s = stripPrefix(hex);
    var result: [32]u8 = [_]u8{0} ** 32;
    if (s.len == 0) return result;
    const byte_len = (s.len + 1) / 2;
    if (byte_len > 32) return error.Overflow;
    const offset = 32 - byte_len;
    var i: usize = 0;
    var si: usize = 0;
    if (s.len % 2 == 1) {
        result[offset] = try hexDigit(s[0]);
        si = 1;
        i = 1;
    }
    while (si + 1 < s.len) {
        result[offset + i] = (try hexDigit(s[si])) << 4 | try hexDigit(s[si + 1]);
        si += 2;
        i += 1;
    }
    return result;
}

fn parseU64Hex(hex: []const u8) !u64 {
    const s = stripPrefix(hex);
    if (s.len == 0) return 0;
    var result: u64 = 0;
    for (s) |c| {
        result = std.math.mul(u64, result, 16) catch return error.Overflow;
        result = std.math.add(u64, result, try hexDigit(c)) catch return error.Overflow;
    }
    return result;
}

fn parseU128Hex(hex: []const u8) !u128 {
    const s = stripPrefix(hex);
    if (s.len == 0) return 0;
    var result: u128 = 0;
    for (s) |c| {
        result = std.math.mul(u128, result, 16) catch return error.Overflow;
        result = std.math.add(u128, result, try hexDigit(c)) catch return error.Overflow;
    }
    return result;
}

fn hexToBytes(a: std.mem.Allocator, hex: []const u8) ![]u8 {
    const s = stripPrefix(hex);
    if (s.len == 0) return a.alloc(u8, 0);
    const byte_len = (s.len + 1) / 2;
    const bytes = try a.alloc(u8, byte_len);
    var i: usize = 0;
    var si: usize = 0;
    if (s.len % 2 == 1) {
        bytes[0] = try hexDigit(s[0]);
        si = 1;
        i = 1;
    }
    while (si + 1 < s.len) {
        bytes[i] = (try hexDigit(s[si])) << 4 | try hexDigit(s[si + 1]);
        si += 2;
        i += 1;
    }
    return bytes;
}

fn stripPrefix(hex: []const u8) []const u8 {
    if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
        return hex[2..];
    return hex;
}

fn hexDigit(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidHexChar,
    };
}

// ---------------------------------------------------------------------------
// Output helpers (unchanged from original main.zig)
// ---------------------------------------------------------------------------

fn printDetail(stdout: anytype, detail: runner.FailureDetail) !void {
    if (detail.address != null and detail.storage_key != null and detail.expected != null and detail.actual != null) {
        // Storage mismatch: addr  key=... expected=... actual=...
        const addr_fmt = runner.fmtAddress(detail.address.?);
        var key_buf: [68]u8 = undefined;
        const key_len = runner.fmtU256Bytes(detail.storage_key.?, &key_buf);
        var exp_buf: [68]u8 = undefined;
        const exp_len = runner.fmtU256Bytes(detail.expected.?, &exp_buf);
        var act_buf: [68]u8 = undefined;
        const act_len = runner.fmtU256Bytes(detail.actual.?, &act_buf);
        try stdout.print("      {s} at {s} key={s} expected={s} actual={s}\n", .{
            detail.reason,
            addr_fmt[0..12],
            key_buf[0..key_len],
            exp_buf[0..exp_len],
            act_buf[0..act_len],
        });
    } else if (detail.address != null and detail.expected != null and detail.actual != null) {
        // Balance/nonce mismatch: addr  expected=... actual=...
        const addr_fmt = runner.fmtAddress(detail.address.?);
        var exp_buf: [68]u8 = undefined;
        const exp_len = runner.fmtU256Bytes(detail.expected.?, &exp_buf);
        var act_buf: [68]u8 = undefined;
        const act_len = runner.fmtU256Bytes(detail.actual.?, &act_buf);
        try stdout.print("      {s} at {s} expected={s} actual={s}\n", .{
            detail.reason,
            addr_fmt[0..12],
            exp_buf[0..exp_len],
            act_buf[0..act_len],
        });
    } else if (detail.address != null) {
        // Code mismatch or other per-address failure
        const addr_fmt = runner.fmtAddress(detail.address.?);
        try stdout.print("      {s} at {s}\n", .{ detail.reason, addr_fmt[0..12] });
    } else if (detail.exec_result) |er| {
        if (detail.opcode) |op| {
            try stdout.print("      {s}: {s} (opcode 0x{x:0>2})\n", .{ detail.reason, @tagName(er), op });
        } else {
            try stdout.print("      {s}: {s}\n", .{ detail.reason, @tagName(er) });
        }
    } else {
        try stdout.print("      {s}\n", .{detail.reason});
    }
}

fn printSummary(stdout: anytype, passed: usize, failed: usize, skipped: usize, errors: usize, elapsed_ns: u64) !void {
    const total = passed + failed + skipped + errors;
    try stdout.print("\n=== Spec Test Results ===\n", .{});
    try stdout.print("Total:   {d}\n", .{total});
    try stdout.print("Passed:  {d}\n", .{passed});
    try stdout.print("Failed:  {d}\n", .{failed});
    try stdout.print("Skipped: {d}\n", .{skipped});
    try stdout.print("Errors:  {d}\n", .{errors});
    if (elapsed_ns < std.time.ns_per_ms) {
        try stdout.print("Time:    {d}us\n", .{elapsed_ns / std.time.ns_per_us});
    } else if (elapsed_ns < std.time.ns_per_s) {
        try stdout.print("Time:    {d}ms\n", .{elapsed_ns / std.time.ns_per_ms});
    } else {
        const ms = elapsed_ns / std.time.ns_per_ms;
        try stdout.print("Time:    {d}.{d:0>3}s\n", .{ ms / 1000, ms % 1000 });
    }
}
