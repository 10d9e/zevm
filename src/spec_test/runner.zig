// Spec test runner: sets up pre-state, executes bytecode, validates storage.

const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const interpreter = @import("interpreter");
const types = @import("types");

const U256 = primitives.U256;
const Stack = interpreter.Stack;
const Gas = interpreter.Gas;
const Memory = interpreter.Memory;
const InstructionResult = interpreter.InstructionResult;
const opcodes = interpreter.opcodes;

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
        // No code to execute — check if expected storage is empty
        if (tc.expected_storage.len == 0) {
            return .{ .result = .pass, .detail = .{ .reason = "no code, no expectations" } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "no code but storage expected" } };
    }

    // Set up pre-state storage (for SLOAD)
    var pre_storage = std.AutoHashMap(StorageMapKey, U256).init(allocator);
    defer pre_storage.deinit();
    for (tc.pre_accounts) |acct| {
        for (acct.storage) |entry| {
            pre_storage.put(.{
                .address = acct.address,
                .key = U256.fromBytes(entry.key),
            }, U256.fromBytes(entry.value)) catch {
                return .{ .result = .err, .detail = .{ .reason = "OOM setting up pre-storage" } };
            };
        }
    }

    // Execute bytecode
    var stack = Stack.new();
    var gas = Gas.new(tc.gas_limit);
    var memory = Memory.new();
    defer memory.deinit();

    // Storage writes tracked during execution
    var storage_writes = std.AutoHashMap(StorageMapKey, U256).init(allocator);
    defer storage_writes.deinit();

    const code = target_code;
    var pc: usize = 0;

    const exec_result = executeLoop(
        &stack,
        &gas,
        &memory,
        code,
        &pc,
        &storage_writes,
        &pre_storage,
        tc,
    );

    // If we expect an exception, any non-success result is a pass
    if (tc.expect_exception) {
        if (exec_result != .stop and exec_result != .@"return") {
            return .{ .result = .pass, .detail = .{ .reason = "expected exception occurred", .exec_result = exec_result } };
        }
        return .{ .result = .fail, .detail = .{ .reason = "expected exception but execution succeeded", .exec_result = exec_result } };
    }

    // Check for execution errors
    if (exec_result.isError()) {
        const opcode: ?u8 = if (exec_result == .invalid_opcode and pc < code.len) code[pc] else null;
        return .{ .result = .err, .detail = .{ .reason = "execution error", .exec_result = exec_result, .opcode = opcode } };
    }

    // Validate expected storage
    for (tc.expected_storage) |expected_acct| {
        for (expected_acct.storage) |entry| {
            const key = U256.fromBytes(entry.key);
            const expected_val = U256.fromBytes(entry.value);

            // Check writes first, then pre-state
            const actual_val = storage_writes.get(.{
                .address = expected_acct.address,
                .key = key,
            }) orelse pre_storage.get(.{
                .address = expected_acct.address,
                .key = key,
            }) orelse U256.ZERO;

            if (!actual_val.eql(expected_val)) {
                return .{ .result = .fail, .detail = .{
                    .reason = "storage mismatch",
                    .address = expected_acct.address,
                    .storage_key = entry.key,
                    .expected = entry.value,
                    .actual = actual_val.toBytes(),
                } };
            }
        }
    }

    return .{ .result = .pass, .detail = .{ .reason = "ok" } };
}

const StorageMapKey = struct {
    address: [20]u8,
    key: U256,
};

fn executeLoop(
    stack: *Stack,
    gas: *Gas,
    memory: *Memory,
    code: []const u8,
    pc: *usize,
    storage_writes: *std.AutoHashMap(StorageMapKey, U256),
    pre_storage: *std.AutoHashMap(StorageMapKey, U256),
    tc: types.TestCase,
) InstructionResult {
    const bytecode_obj = bytecode_mod.Bytecode.newLegacy(code);
    const jump_table = bytecode_obj.legacyJumpTable();

    while (pc.* < code.len) {
        const opcode = code[pc.*];

        const result = switch (opcode) {
            // Stop & Arithmetic
            bytecode_mod.STOP => return .stop,
            bytecode_mod.ADD => opcodes.opAdd(stack, gas),
            bytecode_mod.MUL => opcodes.opMul(stack, gas),
            bytecode_mod.SUB => opcodes.opSub(stack, gas),
            bytecode_mod.DIV => opcodes.opDiv(stack, gas),
            bytecode_mod.SDIV => opcodes.opSdiv(stack, gas),
            bytecode_mod.MOD => opcodes.opMod(stack, gas),
            bytecode_mod.SMOD => opcodes.opSmod(stack, gas),
            bytecode_mod.ADDMOD => opcodes.opAddmod(stack, gas),
            bytecode_mod.MULMOD => opcodes.opMulmod(stack, gas),
            bytecode_mod.EXP => opcodes.opExp(stack, gas),
            bytecode_mod.SIGNEXTEND => opcodes.opSignextend(stack, gas),

            // Comparison
            bytecode_mod.LT => opcodes.opLt(stack, gas),
            bytecode_mod.GT => opcodes.opGt(stack, gas),
            bytecode_mod.SLT => opcodes.opSlt(stack, gas),
            bytecode_mod.SGT => opcodes.opSgt(stack, gas),
            bytecode_mod.EQ => opcodes.opEq(stack, gas),
            bytecode_mod.ISZERO => opcodes.opIsZero(stack, gas),

            // Bitwise
            bytecode_mod.AND => opcodes.opAnd(stack, gas),
            bytecode_mod.OR => opcodes.opOr(stack, gas),
            bytecode_mod.XOR => opcodes.opXor(stack, gas),
            bytecode_mod.NOT => opcodes.opNot(stack, gas),
            bytecode_mod.BYTE => opcodes.opByte(stack, gas),
            bytecode_mod.SHL => opcodes.opShl(stack, gas),
            bytecode_mod.SHR => opcodes.opShr(stack, gas),
            bytecode_mod.SAR => opcodes.opSar(stack, gas),

            // Keccak
            bytecode_mod.KECCAK256 => opcodes.opKeccak256(stack, gas, memory),

            // Environmental info
            bytecode_mod.ADDRESS => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(addressToU256(tc.target));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.CALLER => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(addressToU256(tc.caller));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.CALLVALUE => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.fromBytes(tc.value));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.CALLDATALOAD => blk: {
                if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(3)) break :blk InstructionResult.out_of_gas;
                const offset_val = stack.peekUnsafe(0);
                const offset_u64 = offset_val.toU64() orelse {
                    stack.setTopUnsafe().* = U256.ZERO;
                    break :blk InstructionResult.continue_;
                };
                const offset: usize = @intCast(@min(offset_u64, tc.calldata.len));
                var buf: [32]u8 = [_]u8{0} ** 32;
                const available = if (offset < tc.calldata.len) tc.calldata.len - offset else 0;
                const to_copy = @min(available, 32);
                if (to_copy > 0) {
                    @memcpy(buf[0..to_copy], tc.calldata[offset .. offset + to_copy]);
                }
                stack.setTopUnsafe().* = U256.fromBytes(buf);
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.CALLDATASIZE => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.from(@intCast(tc.calldata.len)));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.CALLDATACOPY => blk: {
                if (!stack.hasItems(3)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(3)) break :blk InstructionResult.out_of_gas;
                const dest_offset = stack.peekUnsafe(0);
                const src_offset = stack.peekUnsafe(1);
                const length = stack.peekUnsafe(2);
                stack.shrinkUnsafe(3);

                const len_u64 = length.toU64() orelse break :blk InstructionResult.memory_limit_oog;
                if (len_u64 == 0) break :blk InstructionResult.continue_;

                const dest_u64 = dest_offset.toU64() orelse break :blk InstructionResult.memory_limit_oog;
                const src_u64 = src_offset.toU64() orelse 0;
                const dest: usize = @intCast(dest_u64);
                const len: usize = @intCast(len_u64);
                const new_size = dest + len;

                // Memory expansion
                if (new_size > memory.size()) {
                    memory.buffer.resize(std.heap.c_allocator, new_size) catch break :blk InstructionResult.memory_limit_oog;
                }

                const src: usize = @intCast(@min(src_u64, tc.calldata.len));
                var i: usize = 0;
                while (i < len) : (i += 1) {
                    const src_pos = src + i;
                    memory.buffer.items[dest + i] = if (src_pos < tc.calldata.len) tc.calldata[src_pos] else 0;
                }
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.CODESIZE => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.from(@intCast(code.len)));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.CODECOPY => blk: {
                if (!stack.hasItems(3)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(3)) break :blk InstructionResult.out_of_gas;
                const dest_offset = stack.peekUnsafe(0);
                const src_offset = stack.peekUnsafe(1);
                const length = stack.peekUnsafe(2);
                stack.shrinkUnsafe(3);

                const len_u64 = length.toU64() orelse break :blk InstructionResult.memory_limit_oog;
                if (len_u64 == 0) break :blk InstructionResult.continue_;

                const dest_u64 = dest_offset.toU64() orelse break :blk InstructionResult.memory_limit_oog;
                const src_u64 = src_offset.toU64() orelse 0;
                const dest: usize = @intCast(dest_u64);
                const src: usize = @intCast(@min(src_u64, code.len));
                const len: usize = @intCast(len_u64);
                const new_size = dest + len;

                if (new_size > memory.size()) {
                    memory.buffer.resize(std.heap.c_allocator, new_size) catch break :blk InstructionResult.memory_limit_oog;
                }

                var i: usize = 0;
                while (i < len) : (i += 1) {
                    const src_pos = src + i;
                    memory.buffer.items[dest + i] = if (src_pos < code.len) code[src_pos] else 0;
                }
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.GASPRICE => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.fromU128(tc.gas_price));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.ORIGIN => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(addressToU256(tc.caller));
                break :blk InstructionResult.continue_;
            },

            // Block info
            bytecode_mod.COINBASE => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(addressToU256(tc.coinbase));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.TIMESTAMP => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.fromBytes(tc.block_timestamp));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.NUMBER => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.fromBytes(tc.block_number));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.DIFFICULTY => blk: {
                // Post-merge: returns prevrandao
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.fromBytes(tc.prevrandao));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.GASLIMIT => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.from(tc.block_gaslimit));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.BASEFEE => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.from(tc.block_basefee));
                break :blk InstructionResult.continue_;
            },

            // Memory ops
            bytecode_mod.MLOAD => opcodes.opMload(stack, gas, memory),
            bytecode_mod.MSTORE => opcodes.opMstore(stack, gas, memory),
            bytecode_mod.MSTORE8 => opcodes.opMstore8(stack, gas, memory),
            bytecode_mod.MSIZE => opcodes.opMsize(stack, gas, memory),
            bytecode_mod.MCOPY => opcodes.opMcopy(stack, gas, memory),

            // Storage operations
            bytecode_mod.SLOAD => blk: {
                if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(100)) break :blk InstructionResult.out_of_gas; // Warm SLOAD cost
                const key = stack.peekUnsafe(0);
                // Check writes first, then pre-state
                const val = storage_writes.get(.{
                    .address = tc.target,
                    .key = key,
                }) orelse pre_storage.get(.{
                    .address = tc.target,
                    .key = key,
                }) orelse U256.ZERO;
                stack.setTopUnsafe().* = val;
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.SSTORE => blk: {
                if (!stack.hasItems(2)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(100)) break :blk InstructionResult.out_of_gas; // Simplified gas
                const key = stack.peekUnsafe(0);
                const value = stack.peekUnsafe(1);
                stack.shrinkUnsafe(2);
                storage_writes.put(.{
                    .address = tc.target,
                    .key = key,
                }, value) catch break :blk InstructionResult.out_of_gas;
                break :blk InstructionResult.continue_;
            },

            // Stack operations
            bytecode_mod.POP => opcodes.opPop(stack, gas),
            bytecode_mod.PUSH0 => opcodes.opPush0(stack, gas),

            // PUSH1-PUSH32
            inline bytecode_mod.PUSH1...bytecode_mod.PUSH32 => |push_op| blk: {
                const n: u8 = push_op - bytecode_mod.PUSH1 + 1;
                const r = opcodes.opPushN(stack, gas, code, pc, n);
                break :blk r;
            },

            // DUP1-DUP16
            inline bytecode_mod.DUP1...bytecode_mod.DUP16 => |dup_op| blk: {
                const n: u8 = dup_op - bytecode_mod.DUP1 + 1;
                break :blk opcodes.opDupN(stack, gas, n);
            },

            // SWAP1-SWAP16
            inline bytecode_mod.SWAP1...bytecode_mod.SWAP16 => |swap_op| blk: {
                const n: u8 = swap_op - bytecode_mod.SWAP1 + 1;
                break :blk opcodes.opSwapN(stack, gas, n);
            },

            // Control flow
            bytecode_mod.JUMP => blk: {
                if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(8)) break :blk InstructionResult.out_of_gas;
                const dest = stack.popUnsafe();
                const dest_u64 = dest.toU64() orelse break :blk InstructionResult.invalid_jump;
                const dest_usize: usize = @intCast(dest_u64);
                if (dest_usize >= code.len) break :blk InstructionResult.invalid_jump;
                if (jump_table) |jt| {
                    if (!jt.isValid(dest_usize)) break :blk InstructionResult.invalid_jump;
                } else {
                    if (code[dest_usize] != bytecode_mod.JUMPDEST) break :blk InstructionResult.invalid_jump;
                }
                pc.* = dest_usize;
                continue; // Don't increment pc
            },
            bytecode_mod.JUMPI => blk: {
                if (!stack.hasItems(2)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(10)) break :blk InstructionResult.out_of_gas;
                const dest = stack.peekUnsafe(0);
                const cond = stack.peekUnsafe(1);
                stack.shrinkUnsafe(2);
                if (!cond.eql(U256.ZERO)) {
                    const dest_u64 = dest.toU64() orelse break :blk InstructionResult.invalid_jump;
                    const dest_usize: usize = @intCast(dest_u64);
                    if (dest_usize >= code.len) break :blk InstructionResult.invalid_jump;
                    if (jump_table) |jt| {
                        if (!jt.isValid(dest_usize)) break :blk InstructionResult.invalid_jump;
                    } else {
                        if (code[dest_usize] != bytecode_mod.JUMPDEST) break :blk InstructionResult.invalid_jump;
                    }
                    pc.* = dest_usize;
                    continue; // Don't increment pc
                }
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.JUMPDEST => opcodes.opJumpdest(stack, gas),
            bytecode_mod.PC => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.from(@intCast(pc.*)));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.GAS => opcodes.opGas(stack, gas),

            // Return / Revert
            bytecode_mod.RETURN => return .@"return",
            bytecode_mod.REVERT => return .revert,
            bytecode_mod.INVALID => return .invalid_opcode,

            // LOG0-LOG4 (consume gas and stack, but don't affect storage)
            inline bytecode_mod.LOG0...bytecode_mod.LOG4 => |log_op| blk: {
                const topic_count: u8 = log_op - bytecode_mod.LOG0;
                const items_needed: u8 = topic_count + 2;
                if (!stack.hasItems(items_needed)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(375)) break :blk InstructionResult.out_of_gas; // Base LOG cost
                stack.shrinkUnsafe(items_needed);
                break :blk InstructionResult.continue_;
            },

            // BALANCE, EXTCODESIZE, etc. - simplified stubs
            bytecode_mod.BALANCE => blk: {
                if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                // Look up balance in pre_accounts
                var addr_bytes: [20]u8 = [_]u8{0} ** 20;
                const addr_val = stack.peekUnsafe(0);
                const full = addr_val.toBytes();
                @memcpy(&addr_bytes, full[12..32]);
                var balance = U256.ZERO;
                for (tc.pre_accounts) |acct| {
                    if (std.mem.eql(u8, &acct.address, &addr_bytes)) {
                        balance = U256.fromBytes(acct.balance);
                        break;
                    }
                }
                stack.setTopUnsafe().* = balance;
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.SELFBALANCE => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(5)) break :blk InstructionResult.out_of_gas;
                var balance = U256.ZERO;
                for (tc.pre_accounts) |acct| {
                    if (std.mem.eql(u8, &acct.address, &tc.target)) {
                        balance = U256.fromBytes(acct.balance);
                        break;
                    }
                }
                stack.pushUnsafe(balance);
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.EXTCODESIZE => blk: {
                if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                var addr_bytes: [20]u8 = [_]u8{0} ** 20;
                const addr_val = stack.peekUnsafe(0);
                const full = addr_val.toBytes();
                @memcpy(&addr_bytes, full[12..32]);
                var code_size: usize = 0;
                for (tc.pre_accounts) |acct| {
                    if (std.mem.eql(u8, &acct.address, &addr_bytes)) {
                        code_size = acct.code.len;
                        break;
                    }
                }
                stack.setTopUnsafe().* = U256.from(@intCast(code_size));
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.EXTCODEHASH => blk: {
                if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                var addr_bytes: [20]u8 = [_]u8{0} ** 20;
                const addr_val = stack.peekUnsafe(0);
                const full = addr_val.toBytes();
                @memcpy(&addr_bytes, full[12..32]);
                var found = false;
                for (tc.pre_accounts) |acct| {
                    if (std.mem.eql(u8, &acct.address, &addr_bytes)) {
                        if (acct.code.len == 0) {
                            stack.setTopUnsafe().* = U256.ZERO;
                        } else {
                            var hash: [32]u8 = undefined;
                            std.crypto.hash.sha3.Keccak256.hash(acct.code, &hash, .{});
                            stack.setTopUnsafe().* = U256.fromBytes(hash);
                        }
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    stack.setTopUnsafe().* = U256.ZERO;
                }
                break :blk InstructionResult.continue_;
            },

            // BLOCKHASH, CHAINID, etc.
            bytecode_mod.BLOCKHASH => blk: {
                if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(20)) break :blk InstructionResult.out_of_gas;
                stack.setTopUnsafe().* = U256.ZERO; // Simplified
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.CHAINID => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.from(1)); // Mainnet chain ID
                break :blk InstructionResult.continue_;
            },

            // Transient storage (EIP-1153)
            bytecode_mod.TLOAD => blk: {
                if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                stack.setTopUnsafe().* = U256.ZERO; // Simplified: always 0
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.TSTORE => blk: {
                if (!stack.hasItems(2)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                stack.shrinkUnsafe(2); // Discard key and value
                break :blk InstructionResult.continue_;
            },

            // RETURNDATASIZE, RETURNDATACOPY (no sub-calls, so always 0)
            bytecode_mod.RETURNDATASIZE => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.ZERO);
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.RETURNDATACOPY => blk: {
                if (!stack.hasItems(3)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(3)) break :blk InstructionResult.out_of_gas;
                stack.shrinkUnsafe(3);
                break :blk InstructionResult.continue_;
            },

            // BLOBHASH, BLOBBASEFEE
            bytecode_mod.BLOBHASH => blk: {
                if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(3)) break :blk InstructionResult.out_of_gas;
                stack.setTopUnsafe().* = U256.ZERO;
                break :blk InstructionResult.continue_;
            },
            bytecode_mod.BLOBBASEFEE => blk: {
                if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                stack.pushUnsafe(U256.ZERO);
                break :blk InstructionResult.continue_;
            },

            // EXTCODECOPY
            bytecode_mod.EXTCODECOPY => blk: {
                if (!stack.hasItems(4)) break :blk InstructionResult.stack_underflow;
                if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                stack.shrinkUnsafe(4);
                break :blk InstructionResult.continue_;
            },

            // CALL family, CREATE - not supported in this runner
            bytecode_mod.CALL,
            bytecode_mod.CALLCODE,
            bytecode_mod.DELEGATECALL,
            bytecode_mod.STATICCALL,
            bytecode_mod.CREATE,
            bytecode_mod.CREATE2,
            => blk: {
                // Push 0 (failure) for CALL family, they have varying stack args
                break :blk InstructionResult.invalid_opcode;
            },

            bytecode_mod.SELFDESTRUCT => return .selfdestruct,

            else => return .invalid_opcode,
        };

        switch (result) {
            .continue_ => {
                pc.* += 1;
            },
            .stop => return .stop,
            .@"return" => return .@"return",
            .revert => return .revert,
            else => return result,
        }
    }

    // Fell off the end of bytecode — implicit STOP
    return .stop;
}

fn addressToU256(addr: [20]u8) U256 {
    var buf: [32]u8 = [_]u8{0} ** 32;
    @memcpy(buf[12..32], &addr);
    return U256.fromBytes(buf);
}
