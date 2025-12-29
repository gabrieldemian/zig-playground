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
    var tmp_i: u32 = 0;
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

                    for (data[del + 1 .. i]) |value| {
                        n -= 1;
                        tmp_i += @intCast((value - '0') * POW10_TABLE[n]);
                    }

                    inside_of = null;
                    print("mask: {d}\n", .{tmp_i});
                    const a: []u8 = std.mem.asBytes(&tmp_i);
                    _ = try w.write(a);
                }
                is_positive = true;
            },
            // '0'...'9' => {
            //     if (inside_of == null) {
            //         return Error.MalformedBuffer;
            //     }
            //     print("writing {d}\n", .{v - '0'});
            // },
            else => {},
        }
    }
}

test "decode_int" {
    const encoded = "i253e";
    // const encoded = "i12345e";
    var buffer: [8]u8 = undefined;
    var w = std.Io.Writer.fixed(&buffer);
    try decode(&w, encoded);
    print("{any}\n", .{buffer});
    print("{d}\n", .{buffer[0]});
    const num: *u32 = @ptrCast(@alignCast(buffer[0..2].ptr));
    print("{d}\n", .{num.*});
}
