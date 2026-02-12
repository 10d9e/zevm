const std = @import("std");
const U256 = @import("u256.zig").U256;

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

test "U256: constants" {
    try expect(U256.ZERO.isZero());
    try expect(U256.ONE.val == 1);
    try expect(!U256.MAX.isZero());
    try expect(U256.MAX.val == std.math.maxInt(u256));
}

test "U256: from / toU64" {
    const v = U256.from(42);
    try expectEqual(@as(?u64, 42), v.toU64());
    try expectEqual(@as(?u64, null), U256.MAX.toU64());
}

test "U256: fromBytes / toBytes round-trip" {
    const bytes = [_]u8{0} ** 31 ++ [_]u8{42};
    const v = U256.fromBytes(bytes);
    try expectEqual(@as(?u64, 42), v.toU64());
    const back = v.toBytes();
    try expectEqual(bytes, back);
}

test "U256: fromBytes / toBytes MAX" {
    const bytes = [_]u8{0xFF} ** 32;
    const v = U256.fromBytes(bytes);
    try expect(v.eql(U256.MAX));
    try expectEqual(bytes, v.toBytes());
}

test "U256: add wrapping" {
    try expect(U256.from(5).add(U256.from(3)).eql(U256.from(8)));
    try expect(U256.MAX.add(U256.ONE).eql(U256.ZERO));
}

test "U256: sub wrapping" {
    try expect(U256.from(8).sub(U256.from(3)).eql(U256.from(5)));
    try expect(U256.ZERO.sub(U256.ONE).eql(U256.MAX));
}

test "U256: mul wrapping" {
    try expect(U256.from(3).mul(U256.from(4)).eql(U256.from(12)));
    try expect(U256.MAX.mul(U256.from(2)).eql(U256.MAX.sub(U256.ONE)));
}

test "U256: div" {
    try expect(U256.from(10).div(U256.from(3)).eql(U256.from(3)));
    try expect(U256.from(42).div(U256.ZERO).eql(U256.ZERO));
}

test "U256: mod" {
    try expect(U256.from(10).mod(U256.from(3)).eql(U256.from(1)));
    try expect(U256.from(42).mod(U256.ZERO).eql(U256.ZERO));
}

test "U256: sdiv" {
    try expect(U256.sdiv(U256.from(10), U256.from(3)).eql(U256.from(3)));
    try expect(U256.sdiv(U256.from(10), U256.ZERO).eql(U256.ZERO));
}

test "U256: smod" {
    try expect(U256.smod(U256.from(10), U256.from(3)).eql(U256.from(1)));
    try expect(U256.smod(U256.from(10), U256.ZERO).eql(U256.ZERO));
}

test "U256: addmod" {
    try expect(U256.addmod(U256.from(10), U256.from(7), U256.from(3)).eql(U256.from(2)));
    try expect(U256.addmod(U256.from(10), U256.from(7), U256.ZERO).eql(U256.ZERO));
    try expect(U256.addmod(U256.MAX, U256.ONE, U256.from(2)).eql(U256.ZERO));
}

test "U256: mulmod" {
    try expect(U256.mulmod(U256.from(10), U256.from(7), U256.from(3)).eql(U256.from(1)));
    try expect(U256.mulmod(U256.from(10), U256.from(7), U256.ZERO).eql(U256.ZERO));
    try expect(U256.mulmod(U256.MAX, U256.MAX, U256.MAX).eql(U256.ZERO));
}

test "U256: exp" {
    try expect(U256.exp(U256.from(2), U256.from(10)).eql(U256.from(1024)));
    try expect(U256.exp(U256.from(42), U256.ZERO).eql(U256.ONE));
    try expect(U256.exp(U256.ZERO, U256.ZERO).eql(U256.ONE));
}

test "U256: signextend" {
    try expect(U256.signextend(U256.from(31), U256.from(42)).eql(U256.from(42)));
}

test "U256: bitwise" {
    try expect(U256.from(0xFF).bitAnd(U256.from(0x0F)).eql(U256.from(0x0F)));
    try expect(U256.from(0xF0).bitOr(U256.from(0x0F)).eql(U256.from(0xFF)));
    try expect(U256.from(0xFF).bitXor(U256.from(0xF0)).eql(U256.from(0x0F)));
    try expect(U256.ZERO.bitNot().eql(U256.MAX));
}

test "U256: getByte" {
    try expect(U256.getByte(U256.from(31), U256.from(0xABCDEF)).eql(U256.from(0xEF)));
    try expect(U256.getByte(U256.from(32), U256.from(0xABCDEF)).eql(U256.ZERO));
}

test "U256: shl/shr" {
    try expect(U256.shl(U256.from(1), U256.from(5)).eql(U256.from(10)));
    try expect(U256.shr(U256.from(1), U256.from(10)).eql(U256.from(5)));
    try expect(U256.shl(U256.from(256), U256.from(1)).eql(U256.ZERO));
    try expect(U256.shr(U256.from(256), U256.from(1)).eql(U256.ZERO));
}

test "U256: sar" {
    try expect(U256.sar(U256.from(1), U256.from(10)).eql(U256.from(5)));
    try expect(U256.sar(U256.from(4), U256.MAX).eql(U256.MAX));
    try expect(U256.sar(U256.from(256), U256.MAX).eql(U256.MAX));
    try expect(U256.sar(U256.from(300), U256.from(42)).eql(U256.ZERO));
}

test "U256: comparison" {
    try expect(U256.from(5).lt(U256.from(10)));
    try expect(!U256.from(10).lt(U256.from(5)));
    try expect(U256.from(10).gt(U256.from(5)));
    try expect(U256.from(42).eql(U256.from(42)));
    try expect(!U256.from(42).eql(U256.from(43)));
    try expect(U256.ZERO.isZero());
    try expect(!U256.ONE.isZero());
}

test "U256: signed comparison" {
    const neg = U256.fromNative(@as(u256, 1) << 255);
    try expect(neg.slt(U256.from(1)));
    try expect(!U256.from(1).slt(neg));
    try expect(U256.from(1).sgt(neg));
    try expect(!neg.sgt(U256.from(1)));
}

test "U256: U256 comparison results" {
    try expect(U256.from(5).ltU256(U256.from(10)).eql(U256.ONE));
    try expect(U256.from(10).ltU256(U256.from(5)).eql(U256.ZERO));
    try expect(U256.from(42).eqlU256(U256.from(42)).eql(U256.ONE));
    try expect(U256.ZERO.isZeroU256().eql(U256.ONE));
    try expect(U256.ONE.isZeroU256().eql(U256.ZERO));
}

test "U256: byteSize" {
    try expectEqual(@as(u64, 0), U256.ZERO.byteSize());
    try expectEqual(@as(u64, 1), U256.ONE.byteSize());
    try expectEqual(@as(u64, 1), U256.from(255).byteSize());
    try expectEqual(@as(u64, 2), U256.from(256).byteSize());
    try expectEqual(@as(u64, 32), U256.MAX.byteSize());
}

test "U256: isNegative" {
    try expect(!U256.ZERO.isNegative());
    try expect(!U256.from(42).isNegative());
    try expect(U256.MAX.isNegative());
    try expect(U256.fromNative(@as(u256, 1) << 255).isNegative());
}

test "U256: negate" {
    try expect(U256.ZERO.negate().eql(U256.ZERO));
    try expect(U256.ONE.negate().eql(U256.MAX));
    try expect(U256.MAX.negate().eql(U256.ONE));
}

test "U256: format" {
    var buf: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const v = U256.from(12345);
    try v.format("", .{}, fbs.writer());
    try std.testing.expectEqualStrings("12345", fbs.getWritten());
}

test "U256: fromNative/toNative round-trip" {
    const val: u256 = 123456789012345678901234567890;
    const u = U256.fromNative(val);
    try expectEqual(val, u.toNative());
}

test "U256: limbLessThan" {
    try expect(!U256.limbLessThan(.{ 1, 2, 3, 4 }, .{ 1, 2, 3, 4 }));
    try expect(U256.limbLessThan(.{ 1, 2, 3, 4 }, .{ 1, 2, 3, 5 }));
    try expect(!U256.limbLessThan(.{ 1, 2, 3, 5 }, .{ 1, 2, 3, 4 }));
}

test "U256: mulFull small" {
    const result = U256.mulFull(U256.from(3), U256.from(4));
    try expectEqual(@as(u64, 12), result[0]);
    for (1..8) |i| {
        try expectEqual(@as(u64, 0), result[i]);
    }
}

test "U256: mulFull MAX*MAX" {
    const result = U256.mulFull(U256.MAX, U256.MAX);
    try expectEqual(@as(u64, 1), result[0]);
    try expectEqual(@as(u64, 0), result[1]);
    try expectEqual(@as(u64, 0), result[2]);
    try expectEqual(@as(u64, 0), result[3]);
    const max64 = std.math.maxInt(u64);
    try expectEqual(max64 - 1, result[4]);
    try expectEqual(max64, result[5]);
    try expectEqual(max64, result[6]);
    try expectEqual(max64, result[7]);
}
