const std = @import("std");
const print = std.debug.print;

// Zig uses their own types primitives to build the types of the language,
// you can use those to build your own types at compile time.

/// Returns an enum given an array of strings
fn BuildEnum(comptime inputs: []const [:0]const u8) type {
    var fields: [inputs.len][]const u8 = undefined;
    var values: [inputs.len]u8 = undefined;

    for (inputs, 0..) |f, i| {
        fields[i] = f;
        values[i] = i;
    }

    return @Enum(
        u8,
        .exhaustive,
        &fields,
        &values,
    );
}

// same as:
// enum(u8) {
//   f1,
//   f2,
// }
const MyEnum = BuildEnum(&[_][:0]const u8{ "f1", "f2" });

// Comptime is just code execution at compile time, so you can go crazy
// and have functions that return a comptime known integer,
// or use a function or an if statemente as the return of a function.

fn GetLen(comptime arr: []u8) comptime_int {
    const colon = std.mem.find(
        u8,
        arr,
        ":",
    ) orelse unreachable;
    const len_slice = arr[0..colon];
    const lenn = std.fmt.parseInt(usize, len_slice, 10) catch unreachable;
    return lenn;
}

fn fngetlen(comptime n: u8) GetLen([4]u8{'2', ':', 'a', 'b'}) {
    _ = n;
    // todo
    return 2;
}

fn ifelsefunction(comptime n: u8) if (n == 3) u8 else u32 {
    if (n == 3) 1 else 1;
}

pub fn main() void {
    const val = MyEnum.f2;

    print("{any}\n", .{MyEnum});
    print("{d}\n", .{val});
}
