const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const assert = std.debug.assert;

const MyData = struct {
    myint: u8,
};

pub const Error = error{
    MalformedBuffer,
    FoundNonInt,
    UnexpectedSign,
    NotSupported,
    LeadingZero,
};

const State = enum {
    None,
    Integer,
    NegInteger,
    List,
    Dict,
    StringLen,
};

pub fn decode(
    comptime T: type,
    w: *Io.Writer,
    data: []const u8,
) !void {
    const info = @typeInfo(T);

    return switch (info) {
        inline .int => {
            const r = try decode_int(T, data);
            _ = try w.write(std.mem.asBytes(&r));
        },
        else => return Error.NotSupported,
    };
}

/// Decode an integer, for example:
/// `i123e`
pub fn decode_int(
    comptime T: type,
    data: []const u8,
) !T {
    @setRuntimeSafety(false);
    const Int = @typeInfo(T).int;

    if (data.len < 3) {
        return Error.MalformedBuffer;
    }

    if (data[0] != 'i' or data[data.len - 1] != 'e') {
        return Error.MalformedBuffer;
    }

    if (data[1] == '0' and data.len > 3) {
        return Error.LeadingZero;
    }

    const is_negative = data[1] == '-';

    if (Int.signedness == .unsigned and is_negative) {
        return Error.UnexpectedSign;
    }

    // -0 is not valid
    if (is_negative and data[2] == '0') {
        return Error.UnexpectedSign;
    }

    var integer_value: T = 0;

    for (data) |v| {
        switch (v) {
            'i', '-' => {},
            '0'...'9' => {
                const vv: T = @intCast(v - '0');
                const m = @mulWithOverflow(integer_value, 10);
                if (m[1] != 0) return error.Overflow;

                if (!is_negative) {
                    const add = @addWithOverflow(m[0], vv);
                    if (add[1] != 0) return error.Overflow;
                    integer_value = add[0];
                } else {
                    const sub = @subWithOverflow(m[0], vv);
                    if (sub[1] != 0) return error.Overflow;
                    integer_value = sub[0];
                }
            },
            'e' => return integer_value,
            else => return Error.FoundNonInt,
        }
    }
    unreachable;
}

const expect = std.testing.expect;
var buffer: [8]u8 = undefined;

// Test numbers not close to the max
test "decode_u8" {
    const encoded = "i50e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(u8, &w, encoded);
    const num: *u8 = @ptrCast(@alignCast(buffer[0..1].ptr));
    try expect(num.* == 50);
}

test "decode_i8" {
    const encoded = "i-50e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(i8, &w, encoded);
    const num: *i8 = @ptrCast(@alignCast(buffer[0..1].ptr));
    try expect(num.* == -50);
}

test "decode_u16" {
    const encoded = "i65535e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(u16, &w, encoded);
    const num: *u16 = @ptrCast(@alignCast(buffer[0..2].ptr));
    try expect(num.* == 65_535);
}

test "decode_i16" {
    const encoded = "i-32768e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(i16, &w, encoded);
    const num: *i16 = @ptrCast(@alignCast(buffer[0..2].ptr));
    try expect(num.* == -32_768);
}

// Test the max value of a signed int and that the minus sign is optional.
test "decode_i16_2" {
    const encoded = "i32767e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(i16, &w, encoded);
    const num: *i16 = @ptrCast(@alignCast(buffer[0..2].ptr));
    try expect(num.* == 32_767);
}

test "decode_u32" {
    const encoded = "i4294967295e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(u32, &w, encoded);
    const num: *u32 = @ptrCast(@alignCast(buffer[0..4].ptr));
    try expect(num.* == 4_294_967_295);
}

test "decode_i32" {
    const encoded = "i-2147483648e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(i32, &w, encoded);
    const num: *i32 = @ptrCast(@alignCast(buffer[0..4].ptr));
    try expect(num.* == -2_147_483_648);
}

test "zero" {
    const encoded = "i0e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(u8, &w, encoded);
    try expect(buffer[0] == 0);
}

// Test errors

test "leading_zero" {
    const encoded = "i02e";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(u8, &w, encoded);
    try expect(err == Error.LeadingZero);
}

test "leading_zero_2" {
    const encoded = "i-0e";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(i8, &w, encoded);
    try expect(err == Error.UnexpectedSign);
}

test "overflow" {
    const encoded = "i256e";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(u8, &w, encoded);
    try expect(err == error.Overflow);
}

test "overflow_2" {
    const encoded = "i-296e";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(i8, &w, encoded);
    try expect(err == error.Overflow);
}

test "non_int" {
    const encoded = "i12#e";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(i8, &w, encoded);
    try expect(err == Error.FoundNonInt);
}

test "malformed" {
    const encoded = "i12";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(i8, &w, encoded);
    try expect(err == Error.MalformedBuffer);
}
