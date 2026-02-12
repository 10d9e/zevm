const U256 = @import("primitives").U256;

inline fn fromBuf(buf: [*]const u64) U256 {
    return U256{ .val = @bitCast(buf[0..4].*) };
}

inline fn writeBuf(buf: [*]u64, result: U256) void {
    buf[0..4].* = @bitCast(result.val);
}

// --- Arithmetic ---

export fn uint256_add(buf: [*]u64) void {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    writeBuf(buf, a.add(b));
}

export fn uint256_sub(buf: [*]u64) void {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    writeBuf(buf, a.sub(b));
}

export fn uint256_mul(buf: [*]u64) void {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    writeBuf(buf, a.mul(b));
}

export fn uint256_div(buf: [*]u64) void {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    writeBuf(buf, a.div(b));
}

export fn uint256_mod(buf: [*]u64) void {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    writeBuf(buf, a.mod(b));
}

export fn uint256_sdiv(buf: [*]u64) void {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    writeBuf(buf, U256.sdiv(a, b));
}

export fn uint256_smod(buf: [*]u64) void {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    writeBuf(buf, U256.smod(a, b));
}

export fn uint256_addmod(buf: [*]u64) void {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    const n = fromBuf(buf + 8);
    writeBuf(buf, U256.addmod(a, b, n));
}

export fn uint256_mulmod(buf: [*]u64) void {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    const n = fromBuf(buf + 8);
    writeBuf(buf, U256.mulmod(a, b, n));
}

export fn uint256_exp(buf: [*]u64) void {
    const base = fromBuf(buf);
    const exponent = fromBuf(buf + 4);
    writeBuf(buf, U256.exp(base, exponent));
}

export fn uint256_signextend(buf: [*]u64) void {
    const byte_pos = fromBuf(buf);
    const value = fromBuf(buf + 4);
    writeBuf(buf, U256.signextend(byte_pos, value));
}

// --- Bitwise ---

export fn uint256_and(buf: [*]u64) void {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    writeBuf(buf, a.bitAnd(b));
}

export fn uint256_or(buf: [*]u64) void {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    writeBuf(buf, a.bitOr(b));
}

export fn uint256_xor(buf: [*]u64) void {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    writeBuf(buf, a.bitXor(b));
}

export fn uint256_not(buf: [*]u64) void {
    const a = fromBuf(buf);
    writeBuf(buf, a.bitNot());
}

export fn uint256_byte(buf: [*]u64) void {
    const i = fromBuf(buf);
    const x = fromBuf(buf + 4);
    writeBuf(buf, U256.getByte(i, x));
}

export fn uint256_shl(buf: [*]u64) void {
    const shift = fromBuf(buf);
    const value = fromBuf(buf + 4);
    writeBuf(buf, U256.shl(shift, value));
}

export fn uint256_shr(buf: [*]u64) void {
    const shift = fromBuf(buf);
    const value = fromBuf(buf + 4);
    writeBuf(buf, U256.shr(shift, value));
}

export fn uint256_sar(buf: [*]u64) void {
    const shift = fromBuf(buf);
    const value = fromBuf(buf + 4);
    writeBuf(buf, U256.sar(shift, value));
}

// --- Comparison ---

export fn uint256_lt(buf: [*]const u64) u64 {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    return if (a.lt(b)) 1 else 0;
}

export fn uint256_gt(buf: [*]const u64) u64 {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    return if (a.gt(b)) 1 else 0;
}

export fn uint256_slt(buf: [*]const u64) u64 {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    return if (a.slt(b)) 1 else 0;
}

export fn uint256_sgt(buf: [*]const u64) u64 {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    return if (a.sgt(b)) 1 else 0;
}

export fn uint256_eq(buf: [*]const u64) u64 {
    const a = fromBuf(buf);
    const b = fromBuf(buf + 4);
    return if (a.eql(b)) 1 else 0;
}

export fn uint256_iszero(buf: [*]const u64) u64 {
    const a = fromBuf(buf);
    return if (a.isZero()) 1 else 0;
}
