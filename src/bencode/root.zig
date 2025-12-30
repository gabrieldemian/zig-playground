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
    NegInteger,
    List,
    Dict,
    StringLen,
};

const MAX_INT = i32;

pub fn decode(w: *Io.Writer, data: []const u8) !void {
    // which data structure the loop is inside of.
    var state: State = .None;
    var integer_value: MAX_INT = 0;

    for (data) |v| {
        switch (state) {
            .None => switch (v) {
                'i' => {
                    state = .Integer;
                    integer_value = 0;
                },
                else => {},
            },
            .Integer => switch (v) {
                '-' => {
                    state = .NegInteger;
                },
                // todo: handle int overflow
                '0'...'9' => integer_value = integer_value * 10 + v - '0',
                'e' => _ = try w.write(std.mem.asBytes(&integer_value)),
                else => {},
            },
            .NegInteger => switch (v) {
                '0'...'9' => integer_value = integer_value * 10 + v - '0',
                'e' => _ = try w.write(std.mem.asBytes(&-integer_value)),
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
