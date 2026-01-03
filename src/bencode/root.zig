const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const assert = std.debug.assert;

pub const MyData = struct {
    myint: u8,
};

pub const Error = error{
    MalformedBuffer,

    FoundNonInt,
    UnexpectedSign,
    NotSupported,
    LeadingZero,

    NoLen,
    NoNegative,
    WrongLen,
};

pub fn decode(
    comptime T: type,
    w: *Io.Writer,
    comptime data: anytype,
) !void {
    const info = @typeInfo(T);

    return switch (info) {
        inline .int => {
            const r = try decode_int(T, data);
            _ = try w.write(std.mem.asBytes(&r));
        },
        inline .pointer => {
            // todo: how to check if pointer is []u8 ?
            if (info.pointer.alignment != 1 and info.pointer.sentinel_ptr == null) {
                return Error.MalformedBuffer;
            }
            const r = try decode_str(data);
            if (r.len == 0) {
                _ = try w.writeByte(0);
            } else {
                _ = try w.write(r);
            }
        },
        inline .@"struct" => {
            // initialize the struct with zeroes, loop over the fields,
            // and call `decode` recursively with the field type.
            var val: T = std.mem.zeroes(T);
            inline for (std.meta.fields(T)) |f| {
                @field(val, f.name) = return decode(f.type, w, data);
            }
        },
        else => return Error.NotSupported,
    };
}

/// Decode a byte str, encoded as `<length>:<contents>`.
/// `<length>` is specified in bytes, not characters.
/// For example: `6:italia`.
pub fn decode_str(data: []const u8) ![]const u8 {
    if (data.len < 2) {
        return Error.MalformedBuffer;
    }

    if (data[0] == '-') {
        return Error.NoNegative;
    }

    // empty string
    if (std.mem.eql(u8, data, "0:")) {
        return "";
    }

    const colon = std.mem.find(u8, data, ":") orelse return Error.MalformedBuffer;
    const len = try std.fmt.parseInt(usize, data[0..colon], 10);
    const str = data[colon + 1 ..];

    if (len != str.len) {
        return Error.WrongLen;
    }

    return str;
}

/// Decode an integer, encoded as `i<base10 integer>e`.
/// For example: `i123e`
pub fn decode_int(
    comptime T: type,
    data: []const u8,
) !T {
    const Int = @typeInfo(T).int;

    if (data.len < 3) {
        return Error.MalformedBuffer;
    }

    if (data[0] != 'i' or data[data.len - 1] != 'e') {
        return Error.MalformedBuffer;
    }

    if (data[1] == '0' and data.len > 3) {
        return Error.LeadingZero;
    }

    const is_negative = data[1] == '-';

    if (Int.signedness == .unsigned and is_negative) {
        return Error.UnexpectedSign;
    }

    // -0 is not valid
    if (is_negative and data[2] == '0') {
        return Error.LeadingZero;
    }

    return try std.fmt.parseInt(T, data[1..data.len - 1], 10);
}

const expect = std.testing.expect;
var buffer: [8]u8 = undefined;

test "struct" {
    const encoded = "i4e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(MyData, &w, encoded);
    std.debug.print("my_data {any}\n", .{buffer});
    try expect(buffer[0] == 4);
}

test "empty_str" {
    const encoded = "0:";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(@TypeOf(encoded), &w, encoded);
    try expect(buffer[0] == 0);
}

test "decode_str" {
    const encoded = "3:hih";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(@TypeOf(encoded), &w, encoded);
    try expect(std.mem.eql(u8, buffer[0..3], "hih"));
}

// Test str errors

test "str_wrong_len" {
    const encoded = "2:hih";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(@TypeOf(encoded), &w, encoded);
    try expect(err == Error.WrongLen);
}

test "str_no_len" {
    const encoded = ":hih";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(@TypeOf(encoded), &w, encoded);
    try expect(err == error.InvalidCharacter);
}

// Test numbers not close to the max
test "decode_u8" {
    const encoded = "i50e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(u8, &w, encoded);
    const num: *u8 = @ptrCast(@alignCast(buffer[0..1].ptr));
    try expect(num.* == 50);
}

test "decode_i8" {
    const encoded = "i-50e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(i8, &w, encoded);
    const num: *i8 = @ptrCast(@alignCast(buffer[0..1].ptr));
    try expect(num.* == -50);
}

test "decode_u16" {
    const encoded = "i65535e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(u16, &w, encoded);
    const num: *u16 = @ptrCast(@alignCast(buffer[0..2].ptr));
    try expect(num.* == 65_535);
}

test "decode_i16" {
    const encoded = "i-32768e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(i16, &w, encoded);
    const num: *i16 = @ptrCast(@alignCast(buffer[0..2].ptr));
    try expect(num.* == -32_768);
}

// Test the max value of a signed int and that the minus sign is optional.
test "decode_i16_2" {
    const encoded = "i32767e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(i16, &w, encoded);
    const num: *i16 = @ptrCast(@alignCast(buffer[0..2].ptr));
    try expect(num.* == 32_767);
}

test "decode_u32" {
    const encoded = "i4294967295e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(u32, &w, encoded);
    const num: *u32 = @ptrCast(@alignCast(buffer[0..4].ptr));
    try expect(num.* == 4_294_967_295);
}

test "decode_i32" {
    const encoded = "i-2147483648e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(i32, &w, encoded);
    const num: *i32 = @ptrCast(@alignCast(buffer[0..4].ptr));
    try expect(num.* == -2_147_483_648);
}

test "zero" {
    const encoded = "i0e";
    var w = std.Io.Writer.fixed(&buffer);
    try decode(u8, &w, encoded);
    try expect(buffer[0] == 0);
}

// Test errors

test "leading_zero" {
    const encoded = "i02e";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(u8, &w, encoded);
    try expect(err == Error.LeadingZero);
}

test "leading_zero_2" {
    const encoded = "i-0e";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(i8, &w, encoded);
    try expect(err == Error.LeadingZero);
}

test "overflow" {
    const encoded = "i256e";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(u8, &w, encoded);
    try expect(err == error.Overflow);
}

test "overflow_2" {
    const encoded = "i-296e";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(i8, &w, encoded);
    try expect(err == error.Overflow);
}

test "non_int" {
    const encoded = "i12#e";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(i8, &w, encoded);
    try expect(err == error.InvalidCharacter);
}

test "malformed" {
    const encoded = "i12";
    var w = std.Io.Writer.fixed(&buffer);
    const err = decode(i8, &w, encoded);
    try expect(err == Error.MalformedBuffer);
}
