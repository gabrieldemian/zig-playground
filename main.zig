const std = @import("std");
const print = std.debug.print;

const Point = struct {
    x: u32,
    y: u32,
};

pub fn main() void {
    const mypoint = &Point{ .x = 1, .y = 2 };
    print("{}\n", .{mypoint});
}
