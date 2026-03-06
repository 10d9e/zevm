const std = @import("std");
const primitives = @import("primitives");
const main = @import("main.zig");
const ripemd160_impl = @import("ripemd160.zig");

/// SHA-256 precompile
pub const SHA256 = main.Precompile.new(
    main.PrecompileId.Sha256,
    main.u64ToAddress(2),
    sha256Run,
);

/// RIPEMD-160 precompile
pub const RIPEMD160 = main.Precompile.new(
    main.PrecompileId.Ripemd160,
    main.u64ToAddress(3),
    ripemd160Run,
);

/// Computes the SHA-256 hash of the input data
///
/// This function follows specifications defined in the following references:
/// - Ethereum Yellow Paper
/// - Solidity Documentation on Mathematical and Cryptographic Functions
/// - Address 0x02
pub fn sha256Run(input: []const u8, gas_limit: u64) main.PrecompileResult {
    const cost = main.calcLinearCost(input.len, 60, 12);
    if (cost > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // Use Zig's built-in SHA-256
    var output: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &output, .{});

    const heap_out = std.heap.c_allocator.dupe(u8, &output) catch
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(cost, heap_out) };
}

/// Computes the RIPEMD-160 hash of the input data
///
/// This function follows specifications defined in the following references:
/// - Ethereum Yellow Paper
/// - Solidity Documentation on Mathematical and Cryptographic Functions
/// - Address 0x03
pub fn ripemd160Run(input: []const u8, gas_limit: u64) main.PrecompileResult {
    const gas_used = main.calcLinearCost(input.len, 600, 120);
    if (gas_used > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // Use RIPEMD-160 implementation
    const output = ripemd160_impl.ripemd160(input);

    // Pad to 32 bytes as per EVM specification
    var padded_output: [32]u8 = [_]u8{0} ** 32;
    std.mem.copyForwards(u8, padded_output[12..32], &output);

    const heap_out = std.heap.c_allocator.dupe(u8, &padded_output) catch
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_used, heap_out) };
}
