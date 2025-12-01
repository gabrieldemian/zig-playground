const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

// interfaces are just normal structs in memory, there is no magic.
// interfaces define their fn pointer signatures, and implementors
// will use their respective function pointers when creating the implementation.
//
// technique 1:

const Shape = struct {
    // a "type-erased pointer" to the underlying type:
    // a pointer, non-zero sized with unknown type.
    // in C this would be a *void. In zig, this doesn't work because *void
    // has an unknown but zero size.
    ptr: *const anyopaque,
    draw_fn: *const fn (ptr: *const anyopaque) void,

    // this just calls the "draw" fn on the implementor "ptr".
    fn draw(self: *const Shape) void {
        self.draw_fn(self.ptr);
    }
};

const Triangle = struct {
    // the implementor will cal this, you don't call it directly.
    fn draw(ptr: *const anyopaque) void {
        // implementor won't know the type of self,
        // so you have to type cast it.
        const self: *const Triangle = @ptrCast(@alignCast(ptr));
        _ = self;
        print("draw from triangle\n", .{});
    }
    // return self as the implementor of Shape.
    pub fn shape(self: *const Triangle) Shape {
        return .{
            .ptr = @ptrCast(self),
            .draw_fn = draw,
        };
    }
};

const Animal = struct {
    // pointer to the implementor
    ptr: *const anyopaque,
    fn make_noise(self: *Animal) void {
        _ = self;
    }
};

const Dog = struct {};

pub fn main() void {
    const tr = Triangle{};
    const sh = tr.shape();
    // this `draw` is calling `Triangle.draw`
    sh.draw();
}

// fn init(
//     pointer: anytype,
//     comptime draw_fn: fn (ptr: @TypeOf(pointer)) void,
// ) Shape {
//     const T = @TypeOf(pointer);
//     assert(@typeInfo(T) == .pointer); // Must be a pointer
//     assert(@typeInfo(T).pointer.size == .one); // Must be a single-item pointer
//     assert(@typeInfo(@typeInfo(T).pointer.child) == .@"struct"); // Must point to a struct
//     const gen = struct {
//         fn draw(
//             ptr: *anyopaque,
//         ) void {
//             // cast the alignment of *anyopaque which is 1,
//             // to the alignment of the underlying type.
//             // and then cast the *anyopaque pointer to the type.
//             const self: T = @ptrCast(@alignCast(ptr));
//             // now it's possible to call the method.
//             draw_fn(self);
//         }
//     };
//     return Shape{
//         .ptr = pointer,
//         .draw_fn = gen.draw,
//     };
// }
