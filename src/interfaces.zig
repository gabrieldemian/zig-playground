const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

// interfaces are just normal structs in memory, there is no magic.
// interfaces define their fn pointer signatures, and implementors
// will use their respective function pointers when creating the implementation.
//
// technique 1: implementor creates the interface,
// runtime-based and implementor need to cast the pointer.

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

// technique 3: comptime trait-like

pub fn Human(comptime T: type) type {
    return struct {
        ptr: *const T,
        pub fn get_age(self: @This()) u8 {
            return T.get_age(self.ptr);
        }
        pub fn call_age(h: *const Human) void {
            _ = h;
        }
    };
}

const Maria = struct {
    age: u8,
    pub fn get_age(self: *const Maria) u8 {
        return self.age;
    }
    pub fn as_human(self: *const Maria) Human(Maria) {
        return Human(Maria){ .ptr = self };
    }
};

// technique 3: another comptime variation
// here, it's the interface that returns the interface object,
// which is not very intuitive.

fn ColorT(comptime Colorable: type) type {
    return struct {
        // @This() will be, for example, ColorT(Cyan) at compile time.
        const Color = @This();
        // Cyan
        c: Colorable,
        fn init(s: Colorable) Color {
            return Color{
                .c = s,
            };
        }
        fn rgb(self: Color) [3]u8 {
            return self.c.rgb();
        }
    };
}

const Cyan = struct {
    r: u8,
    g: u8,
    b: u8,
    fn rgb(self: Cyan) [3]u8 {
        return [_]u8{
            self.r,
            self.g,
            self.b,
        };
    }
    // pub fn as_color(self: *const Cyan) [3]u8 {
    //     return ColorT(Cyan).init(self);
    // }
};

// technique 4: another runtime based.
// in contrast to technique 1, the interface cast the pointer,
// which is nice because it's easier for implementors.
const Writer = struct {
    ptr: *anyopaque,
    writeAllFn: *const fn (ptr: *anyopaque, data: []const u8) anyerror!void,

    // the point of init is to cast *anyopaque to the implementor's ptr.
    // `anytype` will make this function comptime and capture the implementor's
    // type in `T`.
    fn init(ptr: anytype) Writer {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);

        if (ptr_info != .pointer) @compileError("ptr must be a pointer");
        if (ptr_info.pointer.size != .One) @compileError("ptr must be a single item pointer");

        // this struct is needed because in Zig, you can't have
        // functions inside functions.
        const gen = struct {
            pub fn writeAll(pointer: *anyopaque, data: []const u8) anyerror!void {
                const self: T = @ptrCast(@alignCast(pointer));
                // return ptr_info.pointer.child.writeAll(self, data);
                // this can be used to inline the function.
                return @call(.always_inline, ptr_info.pointer.child.writeAll, .{ self, data });
            }
        };

        return Writer{
            .ptr = ptr,
            .writeAllFn = gen.writeAll,
        };
    }

    pub fn writeAll(self: Writer, data: []const u8) !void {
        return self.writeAllFn(self.ptr, data);
    }
};

const File = struct {
    fn writeAll(self: *const File, data: []const u8) !void {
        _ = self;
        _ = data;
    }
    fn writer(self: *File) Writer {
        return Writer.init(self);
    }
};

// technique 5: comptime tagged unions
// only when you know the implementor's, can't be used as a 3rd party lib.

const Writer2 = union(enum) {
    file: File2,
    pub fn writeAll(self: Writer2, data: []const u8) void {
        switch (self) {
            inline else => |file| return file.writeAll(data),
        }
    }
};

const File2 = struct {
    pub fn writeAll(self: File2, data: []const u8) void {
        _ = self;
        _ = data;
        print("writeAll\n", .{});
    }
};

pub fn main() void {
    const cyan = Cyan{ .r = 1, .g = 2, .b = 3 };
    const cyan_color = ColorT(@TypeOf(cyan)).init(cyan);
    // const cyan_color = cyan.as_color();

    print("cyan_rgb {any}\n", .{cyan_color.rgb()});

    const tr = Triangle{};
    tr.as_shape().draw();

    const dog = Dog{};
    // there is some overhead with vtables:
    // here, call a function `as_animal` that calls `make_noise`
    // which follows a pointer to call implementors `make_noise`.
    dog.as_animal().make_noise();

    const maria = Maria{ .age = 23 };
    print("{d}\n", .{maria.as_human().get_age()});

    const file2 = File2{};
    const writer2 = Writer2{ .file = file2 };
    writer2.file.writeAll(&[_]u8{
        1,
        2,
        3,
    });
}

// fn ColorTT(comptime T: type) type {
//     return struct {
//         c: T,
//         fn rgb(self: T) [3]u8 {
//             return self.c.rgb();
//         }
//     };
// }
