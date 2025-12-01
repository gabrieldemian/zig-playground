const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

// Zig gives no guarantees about the order of fields and the size of
// the struct but the fields are guaranteed to be ABI-aligned.
const Point = struct {
    x: u32,
    y: u32,

    // functions and methods are defined inside the struct
    pub fn new(x: u32, y: u32) Point {
        return Point{ .x = x, .y = y };
    }

    pub fn area(self: *const Point) u32 {
        return self.x * self.y;
    }
};

// types are first class citizens, types are  values.
// structs can be returned from functions.
// a generic type can be described as a function that
// takes a type as arg and return another type. (note the comptime keyword)
fn LinkedList(comptime T: type) type {
    return struct {
        pub const Node = struct {
            // optional values take an ?
            prev: ?*Node,
            next: ?*Node,
            data: T,
        };
        first: ?*Node,
        last: ?*Node,
        len: usize,
    };
}

pub fn main() void {
    // const mypoint = Point{ .x = 1, .y = 2 };
    const mypoint = &Point.new(1, 2);

    // Pointers for primitive types:
    //
    // single pointer *T (C pointers)
    // deference like this var.*
    // or directly access a field like var.x
    //
    // multi pointer [*]T many unknown number of items,
    // supports pointer-int arithmetic.
    print("{}\n", .{mypoint.*});

    const area = mypoint.area();
    print("area: {}\n", .{area});

    // Pointers for arrays and slices
    // []T   slice, a fat pointer of the original array [*]T and length
    // *[N]T array, points to N items. exact same pointer for a single pointer of a primitive type

    // array literal
    const buf = [5]u8{ 'h', 'e', 'l', 'l', 'o' };
    // const buf: [_]u8 = { 'h', 'e', 'l', 'l', 'o' };
    // slice
    const slice = buf[0..3];
    // const slice = &buf;

    print("{s} -> {any}\n", .{ buf, buf });
    print("{s}\n", .{slice});
    const linked = LinkedList(u8);
    _ = linked;
}
