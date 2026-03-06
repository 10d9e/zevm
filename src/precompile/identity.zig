const std = @import("std");
const primitives = @import("primitives");
const main = @import("main.zig");

/// Identity precompile
pub const FUN = main.Precompile.new(
    main.PrecompileId.Identity,
    main.u64ToAddress(4),
    identityRun,
);

/// The base cost of the operation
pub const IDENTITY_BASE: u64 = 15;
/// The cost per word
pub const IDENTITY_PER_WORD: u64 = 3;

/// Takes the input bytes, copies them, and returns it as the output.
///
/// See: https://ethereum.github.io/yellowpaper/paper.pdf
/// See: https://etherscan.io/address/0000000000000000000000000000000000000004
pub fn identityRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    const gas_used = main.calcLinearCost(input.len, IDENTITY_BASE, IDENTITY_PER_WORD);
    if (gas_used > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // Must return an owned copy: the caller's RETURNDATACOPY would alias their own
    // execution memory if we returned `input` directly (input is a slice of the
    // caller's memory buffer).
    const output = std.heap.c_allocator.dupe(u8, input) catch
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_used, output) };
}
