const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const assert = std.debug.assert;

const MyData = struct {
    myint: u8,
};

pub const Error = error{
    MalformedBuffer,
    IntHasntOnlyNumber,
    IntSigned,
    NotSupported,
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

pub fn decode_int(
    comptime T: type,
    data: []const u8,
) !T {
    const Int = @typeInfo(T).int;
    var integer_value: T = 0;

    if (data[0] != 'i' or data[data.len - 1] != 'e') {
        return Error.MalformedBuffer;
    }

    if (Int.signedness == .signed and data[1] != '-') {
        return Error.IntSigned;
    }

    if (Int.signedness == .unsigned and data[1] == '-') {
        return Error.IntSigned;
    }

    for (data) |v| {
        switch (v) {
            '-', 'i' => {},
            '0'...'9' => {
                const vv: T = @intCast(v - '0');
                integer_value = integer_value * 10 + vv;
            },
            'e' => {
                return switch (Int.signedness) {
                    inline else => |s| if (s == .signed) -integer_value else integer_value
                };
            },
            else => return Error.IntHasntOnlyNumber,
        }
    }
    unreachable;
}

const expect = std.testing.expect;
var buffer: [8]u8 = undefined;

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
    try expect(num.* == 65535);
}

test "decode_i16" {
    const encoded = "i-32767e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(i16, &w, encoded);
    const num: *i16 = @ptrCast(@alignCast(buffer[0..2].ptr));
    try expect(num.* == -32767);
}

test "decode_u32" {
    const encoded = "i4294967295e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(u32, &w, encoded);
    const num: *u32 = @ptrCast(@alignCast(buffer[0..4].ptr));
    try expect(num.* == 4294967295);
}

test "decode_i32" {
    // todo: this value errors, fix
    // const encoded = "i-2147483648e";
    const encoded = "i-2147483647e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(i32, &w, encoded);
    const num: *i32 = @ptrCast(@alignCast(buffer[0..4].ptr));
    try expect(num.* == -2147483647);
}
