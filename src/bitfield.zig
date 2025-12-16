const std = @import("std");

// a packed struct is another way to interpret an integer,
// this will be calculated bit by bit and it is possible
// to have arbitrary int sizes, booleans take 1 bit.
//
// packed structs have no padding and the layout is preserved.
//
// with these primitives it is trivial to build a bitfield,
// or a protocol struct.
//
// in memory this takes only 1 byte.
const Bitfield = packed struct {
    part1: u4,
    flag1: bool,
    flag2: bool,
    flag3: bool,
    flag4: bool,

    pub fn init() Bitfield {
        return Bitfield{
            .part1 = 1,
            .flag1 = true,
            .flag2 = false,
            .flag3 = true,
            .flag4 = false,
        };
    }

    pub fn to_bytes(self: *const Bitfield) [@sizeOf(Bitfield)]u8 {
        return @bitCast(self.*);
    }

    pub fn from_bytes(buf: [@sizeOf(Bitfield)]u8) Bitfield {
        return @bitCast(buf);
    }
};

pub fn main() void {
    const bits = Bitfield.init();
    const to_bytes = bits.to_bytes();

    std.debug.print("{} {}\n", .{ bits.part1, bits.flag1 });
    std.debug.print("from_bytes {}\n", .{Bitfield.from_bytes([_]u8{1})});
    std.debug.print("to_bytes {any}\n", .{to_bytes});
}
