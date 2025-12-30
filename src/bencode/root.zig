const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const assert = std.debug.assert;

const MyData = struct {
    myint: u8,
};

pub const Error = error{
    MalformedBuffer,
};

const State = enum {
    None,
    Integer,
    List,
    Dict,
    StringLen,
};

const MAX_INT = i32;

pub fn decode(w: *Io.Writer, data: []const u8) !void {
    // which data structure the loop is inside of.
    var state: State = .None;
    var integer_value: MAX_INT = 0;
    var is_positive = true;

    for (data) |v| {
        switch (state) {
            .None => switch (v) {
                'i' => {
                    state = .Integer;
                    is_positive = true;
                    integer_value = 0;
                },
                else => {},
            },
            .Integer => switch (v) {
                '-' => {
                    is_positive = false;
                },
                '0'...'9' => {
                    const digit = v - '0';
                    if (integer_value > @divFloor((std.math.maxInt(MAX_INT) - @as(MAX_INT, digit)), 10)) {
                        return error.Overflow;
                    }
                    integer_value = integer_value * 10 + digit;
                },
                'e' => {
                    const value = if (is_positive) integer_value else -integer_value;
                    const a: []const u8 = std.mem.asBytes(&value);
                    _ = try w.write(a);
                },
                else => {},
            },
            else => {},
        }
    }
}

const expect = std.testing.expect;
var buffer: [8]u8 = undefined;

test "decode_u8" {
    const encoded = "i50e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(&w, encoded);
    const num: *u8 = @ptrCast(@alignCast(buffer[0..1].ptr));
    try expect(num.* == 50);
}

test "decode_u16" {
    const encoded = "i65535e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(&w, encoded);
    const num: *u16 = @ptrCast(@alignCast(buffer[0..2].ptr));
    try expect(num.* == 65535);
}

test "decode_i16" {
    const encoded = "i-32767e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(&w, encoded);
    const num: *i16 = @ptrCast(@alignCast(buffer[0..2].ptr));
    try expect(num.* == -32767);
}

test "decode_i8" {
    const encoded = "i-50e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(&w, encoded);
    const num: *i8 = @ptrCast(@alignCast(buffer[0..1].ptr));
    try expect(num.* == -50);
}
