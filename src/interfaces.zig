const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

// interfaces are just normal structs in memory, there is no magic.
// interfaces define their fn pointer signatures, and implementors
// will use their respective function pointers when creating the implementation.
//
// technique 1: implementor creates the interface

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
    pub fn as_shape(self: *const Triangle) Shape {
        return Shape{
            .ptr = @ptrCast(self),
            .draw_fn = draw,
        };
    }
};

// technique 2: VTable

// the interface defines it's methods as a VTable,
// a VTable is just a struct of function pointers.
const Animal = struct {
    ptr: *const anyopaque,
    vtable: *const AnimalVTable,

    fn make_noise(self: *const Animal) void {
        // call the implementor's function with his ptr as `self`.
        return self.vtable.make_noise(self.ptr);
    }
};

const AnimalVTable = struct {
    make_noise: *const fn (ptr: *const anyopaque) void,
};

const Dog = struct {
    fn make_noise(ptr: *const anyopaque) void {
        const self: *const Dog = @ptrCast(@alignCast(ptr));
        _ = self;
        print("woof\n", .{});
    }

    // in the Dog file, could also move this `as_animal` to the top-level
    // to make it evaluate at compile time and reduce 1 function call.
    pub fn as_animal(self: *const Dog) Animal {
        return Animal{
            .ptr = @ptrCast(self),
            .vtable = &AnimalVTable{ .make_noise = make_noise },
        };
    }
};

pub fn main() void {
    const tr = Triangle{};
    tr.as_shape().draw();

    const dog = Dog{};
    // there is some overhead with vtables:
    // here, call a function `as_animal` that calls `make_noise`
    // which follows a pointer to call implementors `make_noise`.
    dog.as_animal().make_noise();
}
