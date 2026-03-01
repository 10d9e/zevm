//! OpenSSL wrapper for secp256r1 (P-256) signature verification
const std = @import("std");
const c = @cImport({
    @cInclude("openssl/ec.h");
    @cInclude("openssl/ecdsa.h");
    @cInclude("openssl/evp.h");
    @cInclude("openssl/obj_mac.h");
});

/// P-256 (secp256r1) field prime p = 2^256 - 2^224 + 2^192 + 2^96 - 1
const P256_FIELD_PRIME: [32]u8 = .{
    0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
};

/// Returns true if val (big-endian 32 bytes) is in [0, P256_FIELD_PRIME - 1].
fn isValidFieldElement(val: *const [32]u8) bool {
    for (val, &P256_FIELD_PRIME) |v, p| {
        if (v < p) return true;
        if (v > p) return false;
    }
    return false; // val == prime, which is out of range
}

/// Verify secp256r1 (P-256) ECDSA signature
/// msg: 32-byte message hash
/// sig: 64-byte signature (r || s, each 32 bytes)
/// pk: 64-byte public key (x || y, each 32 bytes)
pub fn verifyP256(msg: [32]u8, sig: [64]u8, pk: [64]u8) bool {
    // Validate public key coordinates are in the valid field range [0, p-1].
    // OpenSSL reduces coordinates mod p, which would accept invalid inputs.
    if (!isValidFieldElement(pk[0..32]) or !isValidFieldElement(pk[32..64])) return false;
    // Create EC key
    const group = c.EC_GROUP_new_by_curve_name(c.NID_X9_62_prime256v1);
    if (group == null) return false;
    defer c.EC_GROUP_free(group);

    // Create EC point for public key
    const point = c.EC_POINT_new(group);
    if (point == null) {
        return false;
    }
    defer c.EC_POINT_free(point);

    // Convert public key coordinates to BIGNUM
    const bn_ctx = c.BN_CTX_new();
    if (bn_ctx == null) return false;
    defer c.BN_CTX_free(bn_ctx);

    const x = c.BN_bin2bn(&pk[0], 32, null);
    if (x == null) return false;
    defer c.BN_free(x);

    const y = c.BN_bin2bn(&pk[32], 32, null);
    if (y == null) return false;
    defer c.BN_free(y);

    // Set point coordinates
    if (c.EC_POINT_set_affine_coordinates(group, point, x, y, bn_ctx) != 1) {
        return false;
    }

    // Verify point is on curve
    if (c.EC_POINT_is_on_curve(group, point, bn_ctx) != 1) {
        return false;
    }

    // Create EC key and set public key
    const eckey = c.EC_KEY_new();
    if (eckey == null) return false;
    defer c.EC_KEY_free(eckey);

    if (c.EC_KEY_set_group(eckey, group) != 1) {
        return false;
    }

    if (c.EC_KEY_set_public_key(eckey, point) != 1) {
        return false;
    }

    // Create ECDSA signature
    const ecdsa_sig = c.ECDSA_SIG_new();
    if (ecdsa_sig == null) return false;
    defer c.ECDSA_SIG_free(ecdsa_sig);

    // Set r and s
    const r = c.BN_bin2bn(&sig[0], 32, null);
    if (r == null) return false;
    defer c.BN_free(r);

    const s = c.BN_bin2bn(&sig[32], 32, null);
    if (s == null) return false;
    defer c.BN_free(s);

    // ECDSA_SIG_set0 transfers ownership, so we need to duplicate
    const r_dup = c.BN_dup(r);
    const s_dup = c.BN_dup(s);
    if (r_dup == null or s_dup == null) {
        if (r_dup) |r_ptr| c.BN_free(r_ptr);
        if (s_dup) |s_ptr| c.BN_free(s_ptr);
        return false;
    }

    const r_ptr = r_dup.?;
    const s_ptr = s_dup.?;

    if (c.ECDSA_SIG_set0(ecdsa_sig, r_ptr, s_ptr) != 1) {
        c.BN_free(r_ptr);
        c.BN_free(s_ptr);
        return false;
    }

    // Verify signature
    const result = c.ECDSA_do_verify(&msg, msg.len, ecdsa_sig, eckey);
    return result == 1;
}
