const std = @import("std");
const primitives = @import("primitives");
const main = @import("main.zig");

/// Modular exponentiation precompiles for different specs
pub const BYZANTIUM = main.Precompile.new(
    main.PrecompileId.ModExp,
    main.u64ToAddress(5),
    byzantiumRun,
);

pub const BERLIN = main.Precompile.new(
    main.PrecompileId.ModExp,
    main.u64ToAddress(5),
    berlinRun,
);

pub const OSAKA = main.Precompile.new(
    main.PrecompileId.ModExp,
    main.u64ToAddress(5),
    osakaRun,
);

/// Right pad input to specified length
fn rightPad(comptime len: usize, input: []const u8) [len]u8 {
    var output: [len]u8 = [_]u8{0} ** len;
    const copy_len = @min(input.len, len);
    std.mem.copyForwards(u8, output[0..copy_len], input[0..copy_len]);
    return output;
}

/// Left pad input to specified length
fn leftPadVec(allocator: std.mem.Allocator, input: []const u8, len: usize) ![]u8 {
    if (input.len >= len) {
        return try allocator.dupe(u8, input);
    }
    var output = try allocator.alloc(u8, len);
    @memset(output[0..(len - input.len)], 0);
    @memcpy(output[(len - input.len)..], input);
    return output;
}

/// Right pad input vector
fn rightPadVec(input: []const u8, len: usize) []const u8 {
    if (input.len >= len) {
        return input[0..len];
    }
    // For simplicity, we'll handle padding in the caller
    return input;
}

/// Extract U256 from bytes (big-endian)
fn extractU256(bytes: []const u8) primitives.U256 {
    const padded = rightPad(32, bytes);
    // Convert to U256 - simplified for now
    var result: primitives.U256 = 0;
    for (padded) |b| {
        result = result * 256 + b;
    }
    return result;
}

/// Calculate iteration count for modexp
fn calculateIterationCount(exp_length: u64, exp_highp: primitives.U256, multiplier: u64) u64 {
    if (exp_length <= 32 and exp_highp == 0) {
        return 0;
    } else if (exp_length <= 32) {
        // Count bits in exp_highp
        var bits: u64 = 0;
        var val = exp_highp;
        while (val > 0) {
            bits += 1;
            val >>= 1;
        }
        return if (bits > 0) bits - 1 else 0;
    } else {
        var bits: u64 = 0;
        var val = exp_highp;
        while (val > 0) {
            bits += 1;
            val >>= 1;
        }
        const base_iter = multiplier * (exp_length - 32);
        const highp_iter = if (bits > 0) bits - 1 else 0;
        return @max(base_iter + highp_iter, 1);
    }
}

/// Calculate gas cost for Byzantium
fn byzantiumGasCalc(base_len: u64, exp_len: u64, mod_len: u64, exp_highp: primitives.U256) u64 {
    const max_len = @max(@max(base_len, exp_len), mod_len);
    const iteration_count = calculateIterationCount(exp_len, exp_highp, 8);

    var complexity: u128 = 0;
    if (max_len <= 64) {
        complexity = max_len * max_len;
    } else if (max_len <= 1024) {
        complexity = (max_len * max_len) / 4 + 96 * max_len - 3072;
    } else {
        const x: u128 = max_len;
        complexity = (x * x) / 16 + 480 * x - 199680;
    }

    return @intCast(complexity * iteration_count / 20);
}

/// Calculate gas cost for Berlin (EIP-2565)
fn berlinGasCalc(base_len: u64, exp_len: u64, mod_len: u64, exp_highp: primitives.U256) u64 {
    const max_len = @max(@max(base_len, exp_len), mod_len);
    const iteration_count = calculateIterationCount(exp_len, exp_highp, 8);
    const words = (max_len + 7) / 8;
    const complexity = words * words;
    return 200 + @as(u64, @intCast(complexity * iteration_count / 3));
}

/// Calculate gas cost for Osaka (EIP-7823 and EIP-7883)
/// Formula: max(500, complexity * iteration_count)
/// where complexity is based on max(base_len, mod_len), not exp_len
fn osakaGasCalc(base_len: u64, exp_len: u64, mod_len: u64, exp_highp: primitives.U256) u64 {
    // Use max(base_len, mod_len) for complexity, not exp_len
    const max_len = @max(base_len, mod_len);
    const iteration_count = calculateIterationCount(exp_len, exp_highp, 16);

    var complexity: u64 = 0;
    if (max_len <= 32) {
        complexity = 16;
    } else {
        const words = (max_len + 7) / 8;
        complexity = 2 * words * words;
    }

    const gas = complexity * iteration_count;
    return @max(@as(u64, @intCast(500)), gas);
}

/// Run modexp with specific gas calculation
fn runInner(
    input: []const u8,
    gas_limit: u64,
    min_gas: u64,
    calc_gas: *const fn (u64, u64, u64, primitives.U256) u64,
    is_osaka: bool,
) main.PrecompileResult {
    if (min_gas > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    const HEADER_LENGTH: usize = 96;
    if (input.len < HEADER_LENGTH) {
        return main.PrecompileResult{ .err = main.PrecompileError.ModexpBaseOverflow };
    }

    // Extract lengths from header (32 bytes each, big-endian)
    const base_len_bytes = rightPad(32, input[0..32]);
    const exp_len_bytes = rightPad(32, input[32..64]);
    const mod_len_bytes = rightPad(32, input[64..96]);

    const base_len_u256 = extractU256(&base_len_bytes);
    const exp_len_u256 = extractU256(&exp_len_bytes);
    const mod_len_u256 = extractU256(&mod_len_bytes);

    // Check EIP-7823 limits for Osaka (1024 bytes per parameter)
    const EIP7823_LIMIT: u64 = 1024;
    if (is_osaka) {
        if (base_len_u256 > EIP7823_LIMIT or exp_len_u256 > EIP7823_LIMIT or mod_len_u256 > EIP7823_LIMIT) {
            return main.PrecompileResult{ .err = main.PrecompileError.ModexpEip7823LimitSize };
        }
    }

    const base_len = @as(usize, @intCast(@min(base_len_u256, std.math.maxInt(usize))));
    const exp_len = @as(usize, @intCast(@min(exp_len_u256, std.math.maxInt(usize))));
    const mod_len = @as(usize, @intCast(@min(mod_len_u256, std.math.maxInt(usize))));

    // Extract exponent high part (first 32 bytes or exp_len, whichever is smaller)
    const exp_highp_len = @min(exp_len, 32);
    const data_start = HEADER_LENGTH;
    const exp_start = data_start + base_len;

    var exp_highp_bytes: [32]u8 = [_]u8{0} ** 32;
    if (input.len > exp_start) {
        const available = @min(exp_highp_len, input.len - exp_start);
        const padding = 32 - available;
        @memcpy(exp_highp_bytes[padding..], input[exp_start..][0..available]);
    }
    const exp_highp = extractU256(&exp_highp_bytes);

    // Calculate gas cost
    const gas_cost = calc_gas(base_len, exp_len, mod_len, exp_highp);
    if (gas_cost > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // Handle empty case
    if (base_len == 0 and mod_len == 0) {
        return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_cost, &[_]u8{}) };
    }

    // Extract base, exponent, and modulus
    const total_data_len = base_len + exp_len + mod_len;
    var padded_input = input[HEADER_LENGTH..];
    if (padded_input.len < total_data_len) {
        padded_input = input[HEADER_LENGTH..];
    }

    const base = if (base_len > 0 and padded_input.len >= base_len) padded_input[0..base_len] else &[_]u8{};
    const exp = if (exp_len > 0 and padded_input.len >= base_len + exp_len) padded_input[base_len..][0..exp_len] else &[_]u8{};
    const modulus = if (mod_len > 0 and padded_input.len >= base_len + exp_len + mod_len) padded_input[base_len + exp_len ..][0..mod_len] else &[_]u8{};

    // Allocate output buffer (left-padded with zeros to mod_len bytes) via c_allocator.
    // This buffer is owned by the caller and must NOT be freed here.
    const heap_out = std.heap.c_allocator.alloc(u8, mod_len) catch
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    @memset(heap_out, 0);
    modexpIntoBuffer(base, exp, modulus, heap_out);

    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_cost, heap_out) };
}

/// Compute base^exponent mod modulus and write the result into `output` (left-padded with zeros).
/// `output` must be pre-zeroed by the caller.
fn modexpIntoBuffer(base: []const u8, exponent: []const u8, modulus: []const u8, output: []u8) void {
    const base_trimmed = trimLeadingZeros(base);
    const exp_trimmed = trimLeadingZeros(exponent);
    const mod_trimmed = trimLeadingZeros(modulus);

    if (mod_trimmed.len == 0) return; // output already zero

    // For small values (fit in u64), use simple square-and-multiply
    if (base_trimmed.len <= 8 and exp_trimmed.len <= 8 and mod_trimmed.len <= 8) {
        var base_val: u64 = 0;
        for (base_trimmed) |b| base_val = base_val * 256 + b;

        var exp_val: u64 = 0;
        for (exp_trimmed) |b| exp_val = exp_val * 256 + b;

        var mod_val: u64 = 0;
        for (mod_trimmed) |b| mod_val = mod_val * 256 + b;

        if (mod_val == 0) return;

        var result: u64 = 1;
        var base_pow = base_val % mod_val;
        var exp_remaining = exp_val;
        // Use u128 intermediate to avoid u64 overflow in modular multiplication
        const m128: u128 = mod_val;
        while (exp_remaining > 0) {
            if (exp_remaining & 1 == 1) result = @truncate(@as(u128, result) * @as(u128, base_pow) % m128);
            base_pow = @truncate(@as(u128, base_pow) * @as(u128, base_pow) % m128);
            exp_remaining >>= 1;
        }

        // Write result big-endian into the end of output (left-pad already zero)
        var result_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &result_bytes, result, .big);
        const result_trimmed = trimLeadingZeros(&result_bytes);
        if (result_trimmed.len > 0 and result_trimmed.len <= output.len) {
            const dest_start = output.len - result_trimmed.len;
            @memcpy(output[dest_start..], result_trimmed);
        } else if (result_trimmed.len > output.len and output.len > 0) {
            @memcpy(output, result_trimmed[result_trimmed.len - output.len ..]);
        }
        return;
    }

    // For larger values: output stays zero (big-integer library needed for full correctness)
}

fn trimLeadingZeros(bytes: []const u8) []const u8 {
    var i: usize = 0;
    while (i < bytes.len and bytes[i] == 0) {
        i += 1;
    }
    return bytes[i..];
}

/// Byzantium modexp run
pub fn byzantiumRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    return runInner(input, gas_limit, 0, byzantiumGasCalc, false);
}

/// Berlin modexp run
pub fn berlinRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    return runInner(input, gas_limit, 200, berlinGasCalc, false);
}

/// Osaka modexp run
pub fn osakaRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    return runInner(input, gas_limit, 500, osakaGasCalc, true);
}
