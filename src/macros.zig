const std = @import("std");
const print = std.debug.print;

// during compilation time, you can use Zig to create your own types

/// Returns an enum given an array of strings
fn BuildEnum(comptime inputs: []const [:0]const u8) type {
    var fields: [inputs.len]std.builtin.Type.EnumField = undefined;

    for (inputs, 0..) |f, i| {
        fields[i] = .{
            .name = f,
            .value = i,
        };
    }

    const enumInfo = std.builtin.Type.Enum{
        .tag_type = u8,
        .fields = &fields,
        .decls = &.{},
        .is_exhaustive = true,
    };

    return @Type(std.builtin.Type{ .@"enum" = enumInfo });
}

// same as:
// enum(u8) {
//   f1,
//   f2,
// }
const MyEnum = BuildEnum(&[_][:0]const u8{ "f1", "f2" });

pub fn main() void {
    const val = MyEnum.f2;

    print("{any}\n", .{MyEnum});
    print("{d}\n", .{val});
}
