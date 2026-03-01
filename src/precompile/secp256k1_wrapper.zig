const std = @import("std");

// Import secp256k1 C API
const c = @cImport({
    @cInclude("secp256k1.h");
    @cInclude("secp256k1_recovery.h");
});

/// Wrapper for secp256k1 ECDSA signature recovery
pub const Secp256k1 = struct {
    ctx: *c.secp256k1_context,

    /// Initialize a new secp256k1 context
    pub fn init() Secp256k1 {
        const ctx = c.secp256k1_context_create(c.SECP256K1_CONTEXT_VERIFY | c.SECP256K1_CONTEXT_SIGN);
        std.debug.assert(ctx != null);
        return Secp256k1{ .ctx = ctx.? };
    }

    /// Clean up the secp256k1 context
    pub fn deinit(self: *Secp256k1) void {
        c.secp256k1_context_destroy(self.ctx);
        self.ctx = undefined;
    }

    /// Sign a 32-byte message hash with a private key.
    /// Returns the compact 64-byte signature and recovery ID, or null on failure.
    pub fn sign(self: Secp256k1, msg: [32]u8, seckey: [32]u8) ?struct { sig: [64]u8, recid: u8 } {
        var rec_sig: c.secp256k1_ecdsa_recoverable_signature = undefined;
        if (c.secp256k1_ecdsa_sign_recoverable(
            self.ctx,
            &rec_sig,
            &msg,
            &seckey,
            null,
            null,
        ) == 0) return null;

        var sig_bytes: [64]u8 = undefined;
        var recid: c_int = undefined;
        _ = c.secp256k1_ecdsa_recoverable_signature_serialize_compact(self.ctx, &sig_bytes, &recid, &rec_sig);

        return .{ .sig = sig_bytes, .recid = @intCast(recid) };
    }

    /// Recover public key from signature and message
    /// Returns the Ethereum address (last 20 bytes of Keccak256 hash of public key)
    /// Returns null if recovery fails
    pub fn ecrecover(
        self: Secp256k1,
        msg: [32]u8,
        sig: [64]u8,
        recid: u8,
    ) ?[20]u8 {
        // Create recoverable signature
        var recoverable_sig: c.secp256k1_ecdsa_recoverable_signature = undefined;
        const mut_recid: c_int = @intCast(recid);

        // Parse the compact signature with recovery ID
        if (c.secp256k1_ecdsa_recoverable_signature_parse_compact(
            self.ctx,
            &recoverable_sig,
            &sig,
            mut_recid,
        ) == 0) {
            return null;
        }

        // Recover the public key
        var pubkey: c.secp256k1_pubkey = undefined;
        if (c.secp256k1_ecdsa_recover(
            self.ctx,
            &pubkey,
            &recoverable_sig,
            &msg,
        ) == 0) {
            return null;
        }

        // Serialize public key (uncompressed, 65 bytes: 0x04 + 64 bytes)
        var pubkey_serialized: [65]u8 = undefined;
        var output_len: usize = 65;
        if (c.secp256k1_ec_pubkey_serialize(
            self.ctx,
            &pubkey_serialized,
            &output_len,
            &pubkey,
            c.SECP256K1_EC_UNCOMPRESSED,
        ) == 0) {
            return null;
        }

        // Hash the public key (skip first byte which is 0x04)
        // Ethereum uses Keccak-256, not SHA-3
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha3.Keccak256.hash(pubkey_serialized[1..], &hash, .{});

        // Return last 20 bytes as Ethereum address
        var address: [20]u8 = undefined;
        @memcpy(&address, hash[12..32]);
        return address;
    }
};

/// Global secp256k1 context (initialized on first use, thread-safe)
var global_ctx: ?Secp256k1 = null;
var global_ctx_mutex = std.Thread.Mutex{};

/// Get or create global secp256k1 context
/// This is thread-safe and reuses a single context for efficiency
pub fn getContext() ?Secp256k1 {
    global_ctx_mutex.lock();
    defer global_ctx_mutex.unlock();

    if (global_ctx == null) {
        global_ctx = Secp256k1.init();
    }
    return global_ctx;
}
