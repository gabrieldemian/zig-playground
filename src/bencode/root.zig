const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const assert = std.debug.assert;

const POW10_TABLE = [_]u32{
    1, // 10^0
    10, // 10^1 = (1<<3)+(1<<1)
    100, // 10^2
    1000, // 10^3
    10000, // 10^4
    100000, // 10^5
    1000000, // 10^6
    10000000, // 10^7
    100000000, // 10^8
    1000000000, // 10^9
};

const MyData = struct {
    myint: u8,
};

pub const Error = error{
    MalformedBuffer,
};

pub fn decode(w: *Io.Writer, data: []const u8) !void {
    // which data structure the loop is inside of:
    // i = integer, d = dictionary, etc.
    var inside_of: ?usize = null;
    var is_positive = true;

    for (data, 0..) |v, i| {
        switch (v) {
            'i', 'd', 'l' => {
                inside_of = i;
            },
            '-' => {
                if (inside_of) |del| {
                    if (data[del] == 'i') {
                        is_positive = false;
                    }
                }
            },
            'e' => {
                if (inside_of) |del| {
                    // how much to raise by power of 10
                    var n: usize = i - del - 1;
                    var start = del + 1;
                    var tmp_i: i32 = 0;

                    if (!is_positive) {
                        start += 1;
                        n -= 1;
                    }

                    // const nums: [*]u8 = @ptrCast(@alignCast(@constCast(
                    //     data[start..i].ptr)));
                    // _ = nums;

                    for (data[start..i]) |value| {
                        // print("c: {c}\n", .{value});
                        n -= 1;
                        tmp_i += @intCast((value - '0') * POW10_TABLE[n]);
                    }

                    if (!is_positive) {
                        tmp_i = -tmp_i;
                    }

                    inside_of = null;
                    const a: []u8 = std.mem.asBytes(&tmp_i);
                    _ = try w.write(a);
                    is_positive = true;
                }
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
    // print("{any}\n", .{buffer});
    // print("{d}\n", .{buffer[0]});
    const num: *u8 = @ptrCast(@alignCast(buffer[0..1].ptr));
    try expect(num.* == 50);
    // print("{d}\n", .{num.*});
}

test "decode_i8" {
    const encoded = "i-50e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(&w, encoded);
    const num: *i8 = @ptrCast(@alignCast(buffer[0..1].ptr));
    try expect(num.* == -50);
}
