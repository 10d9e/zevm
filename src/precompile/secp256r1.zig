const std = @import("std");
const primitives = @import("primitives");
const main = @import("main.zig");

/// P256Verify precompile (secp256r1 signature verification)
pub const P256VERIFY = main.Precompile.new(
    main.PrecompileId.P256Verify,
    main.u64ToAddress(256),
    p256Verify,
);

/// P256Verify precompile with Osaka gas cost
pub const P256VERIFY_OSAKA = main.Precompile.new(
    main.PrecompileId.P256Verify,
    main.u64ToAddress(256),
    p256VerifyOsaka,
);

/// Base gas fee for secp256r1 p256verify operation
pub const P256VERIFY_BASE_GAS_FEE: u64 = 3450;

/// Base gas fee for secp256r1 p256verify operation post Osaka
pub const P256VERIFY_BASE_GAS_FEE_OSAKA: u64 = 6900;

/// Input length: 32 (msg) + 32 (r) + 32 (s) + 32 (x) + 32 (y) = 160 bytes
const INPUT_LENGTH: usize = 160;

/// secp256r1 precompile logic (pre-Osaka)
/// Input format:
/// | signed message hash |  r  |  s  | public key x | public key y |
/// | :-----------------: | :-: | :-: | :----------: | :----------: |
/// |          32         | 32  | 32  |     32       |      32      |
pub fn p256Verify(input: []const u8, gas_limit: u64) main.PrecompileResult {
    return p256VerifyInner(input, gas_limit, P256VERIFY_BASE_GAS_FEE);
}

/// secp256r1 precompile logic with Osaka gas cost
pub fn p256VerifyOsaka(input: []const u8, gas_limit: u64) main.PrecompileResult {
    return p256VerifyInner(input, gas_limit, P256VERIFY_BASE_GAS_FEE_OSAKA);
}

fn p256VerifyInner(input: []const u8, gas_limit: u64, gas_cost: u64) main.PrecompileResult {
    if (gas_cost > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    if (verifyImpl(input)) {
        var result: [32]u8 = [_]u8{0} ** 32;
        result[31] = 1;
        const heap_out = std.heap.c_allocator.dupe(u8, &result) catch
            return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
        return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_cost, heap_out) };
    } else {
        return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_cost, &[_]u8{}) };
    }
}

const openssl_wrapper = @import("openssl_wrapper.zig");

/// Verify secp256r1 signature
/// Returns true if the signature is valid, false otherwise
fn verifyImpl(input: []const u8) bool {
    if (input.len != INPUT_LENGTH) {
        return false;
    }

    // msg signed (msg is already the hash of the original message)
    const msg_bytes: [32]u8 = input[0..32].*;
    // r, s: signature
    const sig_bytes: [64]u8 = input[32..96].*;
    // x, y: public key
    const pk_bytes: [64]u8 = input[96..160].*;

    return openssl_wrapper.verifyP256(msg_bytes, sig_bytes, pk_bytes);
}
