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
        const base_iter = std.math.mul(u64, multiplier, exp_length - 32) catch return std.math.maxInt(u64);
        const highp_iter: u64 = if (bits > 0) bits - 1 else 0;
        return @max(std.math.add(u64, base_iter, highp_iter) catch std.math.maxInt(u64), 1);
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
    const words = (std.math.add(u64, max_len, 7) catch return std.math.maxInt(u64)) / 8;
    const complexity = std.math.mul(u64, words, words) catch return std.math.maxInt(u64);
    const gas = std.math.mul(u64, complexity, iteration_count) catch return std.math.maxInt(u64);
    return 200 +| (gas / 3);
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

    // EIP-7883: use max(1, iteration_count) so a zero exponent costs complexity, not 0
    const effective_iter = if (iteration_count == 0) @as(u64, 1) else iteration_count;
    const gas = complexity * effective_iter;
    return @max(@as(u64, 500), gas);
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

    // Extract base, exponent, and modulus.
    // EVM spec: reading calldata beyond its length gives zeros — zero-pad if input is short.
    const data_after_header = input[HEADER_LENGTH..];
    const total_data_len = base_len + exp_len + mod_len;
    var data_buf: ?[]u8 = null;
    const data: []const u8 = blk: {
        if (data_after_header.len >= total_data_len) {
            break :blk data_after_header[0..total_data_len];
        } else {
            const buf = std.heap.c_allocator.alloc(u8, total_data_len) catch
                return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
            @memset(buf, 0);
            @memcpy(buf[0..data_after_header.len], data_after_header);
            data_buf = buf;
            break :blk buf;
        }
    };
    defer if (data_buf) |buf| std.heap.c_allocator.free(buf);

    const base = if (base_len > 0) data[0..base_len] else &[_]u8{};
    const exp = if (exp_len > 0) data[base_len..][0..exp_len] else &[_]u8{};
    const modulus = if (mod_len > 0) data[base_len + exp_len ..][0..mod_len] else &[_]u8{};

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

    // For small values (fit in u64), use fast u128 square-and-multiply
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

    // For larger values: use big-integer modular exponentiation
    modexpBigInt(std.heap.c_allocator, base, exponent, modulus, output) catch {};
}

/// Big-integer modular exponentiation using std.math.big.int.Managed.
/// Computes base^exponent mod modulus and writes result into output (big-endian, left-padded).
fn modexpBigInt(
    allocator: std.mem.Allocator,
    base_bytes: []const u8,
    exp_bytes: []const u8,
    mod_bytes: []const u8,
    output: []u8,
) !void {
    const BigInt = std.math.big.int.Managed;

    var base = try BigInt.init(allocator);
    defer base.deinit();
    var exp_val = try BigInt.init(allocator);
    defer exp_val.deinit();
    var modulus = try BigInt.init(allocator);
    defer modulus.deinit();
    var result = try BigInt.init(allocator);
    defer result.deinit();
    var base_pow = try BigInt.init(allocator);
    defer base_pow.deinit();
    var tmp = try BigInt.init(allocator);
    defer tmp.deinit();
    var quot = try BigInt.init(allocator);
    defer quot.deinit();

    // Parse inputs from big-endian bytes
    try setManagedFromBeBytes(&base, base_bytes);
    try setManagedFromBeBytes(&exp_val, exp_bytes);
    try setManagedFromBeBytes(&modulus, mod_bytes);

    // modulus == 0: result is 0 (output already zero)
    if (modulus.eqlZero()) return;

    // base_pow = base % modulus (reduce base first)
    try BigInt.divFloor(&quot, &base_pow, &base, &modulus);

    // result = 1
    try result.set(1);

    // Right-to-left binary modular exponentiation
    while (!exp_val.eqlZero()) {
        if (exp_val.isOdd()) {
            // tmp = result * base_pow
            try tmp.mul(&result, &base_pow);
            // result = tmp % modulus
            try BigInt.divFloor(&quot, &result, &tmp, &modulus);
        }
        // tmp = base_pow^2
        try tmp.sqr(&base_pow);
        // base_pow = tmp % modulus
        try BigInt.divFloor(&quot, &base_pow, &tmp, &modulus);
        // exp_val >>= 1
        try exp_val.shiftRight(&exp_val, 1);
    }

    // Write result to output (big-endian, left-padded with zeros)
    writeManagedToBeBytes(result.toConst(), output);
}

/// Set a Managed big integer from big-endian bytes.
fn setManagedFromBeBytes(m: *std.math.big.int.Managed, bytes: []const u8) !void {
    // Trim leading zeros
    var start: usize = 0;
    while (start < bytes.len and bytes[start] == 0) start += 1;
    const trimmed = bytes[start..];

    if (trimmed.len == 0) {
        try m.set(0);
        return;
    }

    // Calculate number of limbs needed (each limb = @sizeOf(usize) bytes)
    const limb_bytes = @sizeOf(std.math.big.Limb);
    const n_limbs = (trimmed.len + limb_bytes - 1) / limb_bytes;

    try m.ensureCapacity(n_limbs);

    // Build limbs in little-endian order from big-endian bytes.
    // Process chunks of limb_bytes from the end of trimmed (least significant first).
    @memset(m.limbs[0..n_limbs], 0);
    var i: usize = trimmed.len;
    var limb_idx: usize = 0;
    while (i > 0 and limb_idx < n_limbs) {
        const chunk_size = @min(i, limb_bytes);
        const chunk_start = i - chunk_size;
        var limb_val: std.math.big.Limb = 0;
        for (trimmed[chunk_start..i]) |byte| {
            limb_val = (limb_val << 8) | byte;
        }
        m.limbs[limb_idx] = limb_val;
        limb_idx += 1;
        i -= chunk_size;
    }

    m.setMetadata(true, n_limbs);
    m.normalize(n_limbs);
}

/// Write a Managed big integer to output in big-endian format, left-padded with zeros.
fn writeManagedToBeBytes(val: std.math.big.int.Const, output: []u8) void {
    @memset(output, 0);
    const limbs = val.limbs;
    const limb_bytes = @sizeOf(std.math.big.Limb);

    // Iterate output bytes from LSB (rightmost) to MSB (leftmost)
    for (0..output.len) |i| {
        // byte i from the right: i=0 is the least significant byte
        const limb_idx = i / limb_bytes;
        const byte_in_limb: u6 = @intCast((i % limb_bytes) * 8);
        if (limb_idx < limbs.len) {
            output[output.len - 1 - i] = @truncate(limbs[limb_idx] >> byte_in_limb);
        }
    }
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
