const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

pub const MyData = struct {
    myint: u8,
};

pub const Error = error{
    MalformedBuffer,
    WrongType,

    FoundNonInt,
    UnexpectedSign,
    NotSupported,
    LeadingZero,

    NoLen,
    NoNegative,
    WrongLen,
};

pub fn decode(
    /// The type to decode `data` into.
    comptime T: type,
    writer: *Writer,
    reader: *Reader,
) !void {
    const info = @typeInfo(T);

    return switch (info) {
        inline .int => |int| {
            _ = int;
            var r = try decode_int(T, reader);
            _ = try writer.write(std.mem.asBytes(&r));
        },
        // a literal string is a pointer.
        // string = []u8
        inline .pointer => |pointer| {
            if (std.meta.Elem(T) != u8) {
                return Error.WrongType;
            }
            if (pointer.alignment != 1 and pointer.sentinel_ptr == null) {
                return Error.MalformedBuffer;
            }
            var r = try decode_str(reader);
            if (r.len == 0) {
                _ = try writer.writeByte(0);
            } else {
                _ = try writer.write(r);
            }
        },
        inline .@"struct" => {
            // initialize the struct with zeroes, loop over the fields,
            // and call `decode` recursively with the field type.
            var val: T = undefined;
            inline for (std.meta.fields(T)) |f| {
                @field(val, f.name) = return decode(f.type, writer, reader);
            }
        },
        inline .array => |arr| {
            var r = try decode_arr(arr, reader, writer);
            _ = try writer.write(std.mem.asBytes(&r));
        },
        else => return Error.NotSupported,
    };
}

/// Lists are encoded as `l<elements>e`.
/// For example: `l3:foo:bare`.
pub fn decode_arr(
    comptime Arr: std.builtin.Type.Array,
    reader: *Reader,
    writer: *Writer,
) !void {
    const data = reader.buffer[reader.seek..];

    if (data.len < 3) {
        return Error.MalformedBuffer;
    }

    if (data[0] != 'l' or data[data.len - 1] != 'e') {
        return Error.MalformedBuffer;
    }

    // empty list
    if (std.mem.eql(u8, data, "le")) {
        return;
    }

    for (0..Arr.len) |_| {
        // skip the last byte of the prev structure and enter the current one
        reader.toss(1);
        // print(std.fmt.comptimePrint("child: {}\n", .{Arr.child}), .{});
        _ = try decode(Arr.child, writer, reader);
    }
}

/// Decode a byte str, encoded as `<length>:<contents>`.
/// `<length>` is specified in bytes, not characters.
/// For example: `6:italia`.
pub fn decode_str(reader: *Reader) ![]const u8 {
    if (reader.buffer[reader.seek..].len < 2) {
        return Error.MalformedBuffer;
    }

    // empty string
    if (std.mem.eql(u8, reader.buffer[reader.seek..], "0:")) {
        reader.toss(1);
        return "";
    }

    const colon = std.mem.find(
        u8,
        reader.buffer[reader.seek..],
        ":",
    ) orelse return Error.MalformedBuffer;

    const len_slice = reader.buffer[reader.seek .. reader.seek + colon];
    const len = try std.fmt.parseInt(usize, len_slice, 10);
    const str = reader.buffer[reader.seek + colon + 1 .. reader.seek + colon + len + 1];
    reader.toss(colon + len);

    return str;
}

/// Decode an integer, encoded as `i<base10 integer>e`.
/// For example: `i123e`
pub fn decode_int(
    comptime T: type,
    reader: *Reader,
) !T {
    const Int = @typeInfo(T).int;
    // print("reader.buffer[seek..]: {s}\n", .{reader.buffer[reader.seek..]});

    if (reader.buffer[reader.seek..].len < 3) {
        return Error.MalformedBuffer;
    }

    if (reader.buffer[reader.seek..][0] != 'i') {
        return Error.MalformedBuffer;
    }

    const end = std.mem.find(
        u8,
        reader.buffer[reader.seek..],
        "e",
    ) orelse return Error.MalformedBuffer;
    // print("end: {d} seek: {d}\n", .{ end, reader.seek });

    const data = reader.buffer[reader.seek .. reader.seek + end + 1];
    // print("data: {s}\n", .{data});

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

    const result = std.fmt.parseInt(T, data[1 .. data.len - 1], 10) catch |err| {
        return err;
    };
    reader.toss(data.len - 1);
    return result;
}

const expect = std.testing.expect;
var buffer: [14]u8 = undefined;

test "arr_int" {
    const encoded = "li22ee";
    var r = Reader.fixed(encoded);
    const T = [1]u8;
    var w = Writer.fixed(&buffer);
    try decode(T, &w, &r);
    try expect(buffer[0] == 22);
}

test "arr_int_2" {
    const encoded = "li22ei34ee";
    var r = Reader.fixed(encoded);
    const T = [2]u8;
    var w = Writer.fixed(&buffer);
    try decode(T, &w, &r);
    try expect(buffer[0] == 22);
    try expect(buffer[1] == 34);
}

test "arr_str" {
    const encoded = "l3:vvve";
    var r = Reader.fixed(encoded);
    const T = [1]*const [3]u8;
    var w = Writer.fixed(&buffer);
    try decode(T, &w, &r);
    try expect(std.mem.eql(u8, buffer[0..3], "vvv"));
}

test "arr_str_2" {
    const encoded = "l3:foo3:bare";
    var r = Reader.fixed(encoded);
    const T = [2]*const [3]u8;
    var w = Writer.fixed(&buffer);
    try decode(T, &w, &r);
    try expect(std.mem.eql(u8, buffer[0..3], "foo"));
    try expect(std.mem.eql(u8, buffer[3..6], "bar"));
}

test "decode_str" {
    const encoded = "3:hih";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    try decode(@TypeOf(encoded), &w, &r);
    try expect(std.mem.eql(u8, buffer[0..3], "hih"));
    try expect(r.seek == encoded.len - 1);
}

test "struct" {
    const encoded = "i4e";
    var r = Reader.fixed(encoded);
    var w = Writer.fixed(&buffer);
    try decode(MyData, &w, &r);
    try expect(buffer[0] == 4);
    try expect(r.seek == encoded.len - 1);
}

test "empty_str" {
    const encoded = "0:";
    var r = Reader.fixed(encoded);
    var w = Writer.fixed(&buffer);
    try decode(@TypeOf(encoded), &w, &r);
    try expect(buffer[0] == 0);
    try expect(r.seek == encoded.len - 1);
}

test "decode_str_2" {
    const encoded = "10:hihhihhihh";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    try decode(@TypeOf(encoded), &w, &r);
    try expect(std.mem.eql(u8, buffer[0..10], "hihhihhihh"));
    try expect(r.seek == encoded.len - 1);
}

// // Test str errors

test "str_wrong_len" {
    // should ignore all the rest of the string
    const encoded = "2:higarbage";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    try decode(@TypeOf(encoded), &w, &r);
    try expect(std.mem.eql(u8, buffer[0..2], "hi"));
    try expect(r.seek == 3);
}

test "str_no_len" {
    const encoded = ":hih";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    const err = decode(@TypeOf(encoded), &w, &r);
    try expect(err == error.InvalidCharacter);
    try expect(r.seek == 0);
}

// Test numbers not close to the max
test "decode_u8" {
    const encoded = "i50e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    try decode(u8, &w, &r);
    const num: *u8 = @ptrCast(@alignCast(buffer[0..1].ptr));
    try expect(num.* == 50);
    try expect(r.seek == encoded.len - 1);
}

test "decode_i8" {
    const encoded = "i-50e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    try decode(i8, &w, &r);
    const num: *i8 = @ptrCast(@alignCast(buffer[0..1].ptr));
    try expect(num.* == -50);
    try expect(r.seek == encoded.len - 1);
}

test "decode_u16" {
    const encoded = "i65535e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    try decode(u16, &w, &r);
    const num: *u16 = @ptrCast(@alignCast(buffer[0..2].ptr));
    try expect(num.* == 65_535);
    try expect(r.seek == encoded.len - 1);
}

test "decode_i16" {
    const encoded = "i-32768e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    try decode(i16, &w, &r);
    const num: *i16 = @ptrCast(@alignCast(buffer[0..2].ptr));
    try expect(num.* == -32_768);
    try expect(r.seek == encoded.len - 1);
}

// Test the max value of a signed int and that the minus sign is optional.
test "decode_i16_2" {
    const encoded = "i32767e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    try decode(i16, &w, &r);
    const num: *i16 = @ptrCast(@alignCast(buffer[0..2].ptr));
    try expect(num.* == 32_767);
    try expect(r.seek == encoded.len - 1);
}

test "decode_u32" {
    const encoded = "i4294967295e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    try decode(u32, &w, &r);
    const num: *u32 = @ptrCast(@alignCast(buffer[0..4].ptr));
    try expect(num.* == 4_294_967_295);
    try expect(r.seek == encoded.len - 1);
}

test "decode_i32" {
    const encoded = "i-2147483648e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    try decode(i32, &w, &r);
    const num: *i32 = @ptrCast(@alignCast(buffer[0..4].ptr));
    try expect(num.* == -2_147_483_648);
    try expect(r.seek == encoded.len - 1);
}

test "zero" {
    const encoded = "i0e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    try decode(u8, &w, &r);
    try expect(buffer[0] == 0);
    try expect(r.seek == encoded.len - 1);
}

// Test errors

test "leading_zero" {
    const encoded = "i02e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    const err = decode(u8, &w, &r);
    try expect(err == Error.LeadingZero);
    try expect(r.seek == 0);
}

test "leading_zero_2" {
    const encoded = "i-0e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    const err = decode(i8, &w, &r);
    try expect(err == Error.LeadingZero);
    try expect(r.seek == 0);
}

test "overflow" {
    const encoded = "i256e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    const err = decode(u8, &w, &r);
    try expect(err == error.Overflow);
    try expect(r.seek == 0);
}

test "overflow_2" {
    const encoded = "i-296e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    const err = decode(i8, &w, &r);
    try expect(err == error.Overflow);
    try expect(r.seek == 0);
}

test "non_int" {
    const encoded = "i12#e";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    const err = decode(i8, &w, &r);
    try expect(err == error.InvalidCharacter);
    try expect(r.seek == 0);
}

test "malformed" {
    const encoded = "i12";
    var w = Writer.fixed(&buffer);
    var r = Reader.fixed(encoded);
    const err = decode(i8, &w, &r);
    try expect(err == Error.MalformedBuffer);
    try expect(r.seek == 0);
}
