const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const EMPTY_STR = "";

pub const Error = error{
    MalformedBuffer,
    Empty,
    UnexpectedSign,
    NotSupported,
    LeadingZero,
    MissingColon,
};

fn encode(value: anytype, alloc: *std.mem.Allocator) ![]u8 {
    return switch (@typeInfo(@TypeOf(value))) {
        inline .int => try encode_int(value, alloc),
        inline .@"enum" => try encode_int(@intFromEnum(value), alloc),
        inline .array => |arr| {
            if (arr.child != u8) return Error.NotSupported;
            return try encode_str(&value, alloc);
        },
        inline .pointer => |p| {
            if (@typeInfo(p.child).array.child != u8) return Error.NotSupported;
            return try encode_str(&value.*, alloc);
        },
        inline else => Error.NotSupported,
    };
}

fn encode_str(value: []const u8, alloc: *std.mem.Allocator) ![]u8 {
    var enc_size: usize = 0;
    var v = value.len;
    while (v > 0) {
        enc_size += 1;
        v = @divTrunc(v, 10);
    }
    const buf_len = enc_size + 1 + value.len;
    const buf = try alloc.alloc(u8, buf_len);
    var w = Writer.fixed(buf);
    try w.printIntAny(value.len, 10, .lower, .{});
    buf[enc_size] = ':';
    @memcpy(buf[enc_size + 1..], value);
    return buf;
}

fn encode_int(value: anytype, alloc: *std.mem.Allocator) ![]u8 {
    var size: usize = 0;
    var v = @abs(value);
    while (v > 0) {
        size += 1;
        v = @divTrunc(v, 10);
    }
    var buf_len = 2 + size;
    if (value < 0) {
        buf_len += 1;
    }
    const buf = try alloc.alloc(u8, buf_len);
    buf[0] = 'i';
    var w = Writer.fixed(buf[1 .. buf.len - 1]);
    try w.printIntAny(value, 10, .lower, .{});
    buf[buf.len - 1] = 'e';
    return buf;
}

pub fn decode(
    /// The type to decode `data` into.
    comptime T: type,
    reader: *Reader,
) !T {
    return switch (@typeInfo(T)) {
        inline .int => try decode_int(T, reader),
        inline .@"enum" => |en| @enumFromInt(try decode_int(en.tag_type, reader)),
        inline .pointer => |p| {
            // []u8 will fall in this branch which is considered a string.
            if (p.child != u8) return Error.NotSupported;
            return try decode_str(reader);
        },
        inline .@"struct" => |str| try decode_dict(T, str, reader),
        inline .array => |arr| try decode_arr(arr, reader),
        inline else => Error.NotSupported,
    };
}

/// Dicts are encoded as `d<str><val>e`.
/// For example: `d3:fooi2ee`.
fn decode_dict(
    comptime T: type,
    comptime Str: std.builtin.Type.Struct,
    reader: *Reader,
) !T {
    const data = reader.buffer[reader.seek..];

    // empty dict
    if (std.mem.eql(u8, data, "de")) {
        reader.toss(1);
        return Error.Empty;
    }

    if (data.len < 3 or
        (data[0] != 'd' or data[data.len - 1] != 'e'))
    {
        return Error.MalformedBuffer;
    }

    var dict: T = undefined;

    inline for (Str.fields) |f| {
        // enter the field str `3:foo...`
        reader.toss(1);
        _ = try decode_str(reader);
        // enter the next data structure `i2e...`
        reader.toss(1);

        @field(dict, f.name) = try decode(f.type, reader);
    }

    reader.toss(1);
    return dict;
}

/// Lists are encoded as `l<elements>e`.
/// For example: `l3:foo:bare`.
fn decode_arr(
    comptime Arr: std.builtin.Type.Array,
    reader: *Reader,
) ![Arr.len]Arr.child {
    const data = reader.buffer[reader.seek..];

    // empty list
    if (std.mem.eql(u8, data, "le")) {
        reader.toss(1);
        // todo: not return an error here
        return Error.Empty;
    }

    if (data.len < 3) {
        return Error.MalformedBuffer;
    }

    if (data[0] != 'l' or data[data.len - 1] != 'e') {
        return Error.MalformedBuffer;
    }

    var arr: [Arr.len]Arr.child = undefined;

    inline for (0..Arr.len) |i| {
        // skip the last byte of the prev structure and
        // enter the current one
        reader.toss(1);
        const v: Arr.child = try decode(Arr.child, reader);
        arr[i] = v;
    }

    reader.toss(1);
    return arr;
}

/// Decode a byte str, encoded as `<length>:<contents>`.
/// `<length>` is specified in bytes, not characters.
/// For example: `6:italia`.
fn decode_str(reader: *Reader) ![]const u8 {
    if (reader.buffer[reader.seek..].len < 2) {
        return Error.MalformedBuffer;
    }

    // empty string
    if (std.mem.eql(u8, reader.buffer[reader.seek..], "0:")) {
        reader.toss(1);
        return EMPTY_STR;
    }

    const colon = std.mem.find(
        u8,
        reader.buffer[reader.seek..],
        ":",
    ) orelse return Error.MissingColon;
    const len_slice = reader.buffer[reader.seek .. reader.seek + colon];
    const len = try std.fmt.parseInt(usize, len_slice, 10);
    const str =
        reader.buffer[reader.seek + colon + 1 .. reader.seek + colon + len + 1];
    reader.toss(colon + len);

    return str;
}

/// Decode an integer, encoded as `i<base10 integer>e`.
/// For example: `i123e`
fn decode_int(
    comptime T: type,
    reader: *Reader,
) !T {
    const Int = @typeInfo(T).int;

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

    const data = reader.buffer[reader.seek .. reader.seek + end + 1];

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

    const result = std.fmt.parseInt(
        T,
        data[1 .. data.len - 1],
        10,
    ) catch |err| {
        return err;
    };
    reader.toss(data.len - 1);
    return result;
}

const expect = std.testing.expect;

test "encode_str" {
    const v = "avocado";
    var buffer: [9]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buffer);
    var gpa = alloc.allocator();
    const r = try encode(v, &gpa);
    try expect(std.mem.eql(u8, r, "7:avocado"));
}

test "encode_str_2" {
    const v = "iwillhave11";
    var buffer: [14]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buffer);
    var gpa = alloc.allocator();
    const r = try encode(v, &gpa);
    try expect(std.mem.eql(u8, r, "11:iwillhave11"));
}

test "encode_str_3" {
    const v = "iwillhave11";
    const vv = v.*;
    var buffer: [14]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buffer);
    var gpa = alloc.allocator();
    const r = try encode(vv, &gpa);
    try expect(std.mem.eql(u8, r, "11:iwillhave11"));
}

test "encode_enum" {
    const MyEnum = enum(u8) {
        Core,
        ExtHandshake,
        Metainfo,
    };
    var buffer: [3]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buffer);
    var gpa = alloc.allocator();
    const r = try encode(MyEnum.ExtHandshake, &gpa);
    try expect(std.mem.eql(u8, r, "i1e"));
}

test "encode_int" {
    const v: u8 = 255;
    var buffer: [5]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buffer);
    var gpa = alloc.allocator();
    const r = try encode(v, &gpa);
    try expect(std.mem.eql(u8, r, "i255e"));
}

test "encode_int_2" {
    const v: i8 = 30;
    var buffer: [4]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buffer);
    var gpa = alloc.allocator();
    const r = try encode(v, &gpa);
    try expect(std.mem.eql(u8, r, "i30e"));
}

test "encode_int_3" {
    const v: i8 = -30;
    var buffer: [5]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buffer);
    var gpa = alloc.allocator();
    const r = try encode(v, &gpa);
    try expect(std.mem.eql(u8, r, "i-30e"));
}

test "enum" {
    const MyEnum = enum(u8) {
        Core,
        ExtHandshake,
        Metainfo,
    };
    const encoded = "i1e";
    var r = Reader.fixed(encoded);
    const num = try decode(MyEnum, &r);
    try expect(num == .ExtHandshake);
    try expect(r.seek == encoded.len - 1);
}

test "dict" {
    const MyDict = struct {
        foo: u8,
    };
    const encoded = "d3:fooi3ee";
    var r = Reader.fixed(encoded);
    const s = try decode(MyDict, &r);
    try expect(s.foo == 3);
    try expect(r.seek == encoded.len - 1);
}

test "dict_2" {
    const MyDict = struct {
        foo: u8,
        bar: u32,
        zip: []const u8,
    };
    const encoded = "d3:fooi3e3:bari321e3:zip7:avocadoe";
    var r = Reader.fixed(encoded);
    const s = try decode(MyDict, &r);
    try expect(s.foo == 3);
    try expect(s.bar == 321);
    try expect(std.mem.eql(u8, s.zip, "avocado"));
    try expect(r.seek == encoded.len - 1);
}

test "dict_3" {
    const MyDict = struct {
        foo: u8,
        bar: u32,
        zip: []const u8,
        arr: [2]u8,
    };
    const encoded = "d3:fooi3e3:bari321e3:zip7:avocado3:arrli1ei2eee";
    var r = Reader.fixed(encoded);
    const s = try decode(MyDict, &r);
    try expect(s.foo == 3);
    try expect(s.bar == 321);
    try expect(std.mem.eql(u8, s.zip, "avocado"));
    try expect(s.arr[0] == 1);
    try expect(s.arr[1] == 2);
    try expect(r.seek == encoded.len - 1);
}

test "dict_4" {
    const MyDict2 = struct {
        foo: u8,
    };
    const MyDict = struct {
        foo: u8,
        bar: u32,
        dic: MyDict2,
        zip: []const u8,
        arr: [2]u8,
    };
    const encoded = "d3:fooi3e3:bari321e3:dicd3:fooi6ee3:zip7:avocado3:arrli1ei2eee";
    var r = Reader.fixed(encoded);
    const s = try decode(MyDict, &r);
    try expect(s.foo == 3);
    try expect(s.bar == 321);
    try expect(s.dic.foo == 6);
    try expect(std.mem.eql(u8, s.zip, "avocado"));
    try expect(s.arr[0] == 1);
    try expect(s.arr[1] == 2);
    try expect(r.seek == encoded.len - 1);
}

test "dict_tuple" {
    const encoded = "d3:fooi3e3:bari321e3:zip7:avocadoe";
    var r = Reader.fixed(encoded);
    const T = @Tuple(&.{ u8, u32, []const u8 });
    const s: T = try decode(T, &r);
    try expect(s[0] == 3);
    try expect(s[1] == 321);
    try expect(std.mem.eql(u8, s[2], "avocado"));
    try expect(r.seek == encoded.len - 1);
}

test "arr_int" {
    const encoded = "li22ee";
    var r = Reader.fixed(encoded);
    const s = try decode([1]u8, &r);
    try expect(s[0] == 22);
    try expect(s.len == 1);
    try expect(r.seek == encoded.len - 1);
}

test "arr_int_2" {
    const encoded = "li22ei34ee";
    var r = Reader.fixed(encoded);
    const s = try decode([2]u8, &r);
    try expect(s[0] == 22);
    try expect(s[1] == 34);
    try expect(s.len == 2);
    try expect(r.seek == encoded.len - 1);
}

test "arr_int_3" {
    const encoded = "li22ei34ee";
    var r = Reader.fixed(encoded);
    const s = try decode([2]u16, &r);
    try expect(s[0] == 22);
    try expect(s[1] == 34);
    try expect(s.len == 2);
    try expect(r.seek == encoded.len - 1);
}

test "arr_int_4" {
    const encoded = "lli1ei2ei3eeli4ei5ei6eeli7ei8ei9eee";
    var r = Reader.fixed(encoded);
    const s = try decode([3][3]u8, &r);
    // print("arr: {d} {s}\n", .{ r.seek, r.buffer[r.seek..] });
    try expect(s[0][0] == 1);
    try expect(s[0][1] == 2);
    try expect(s[0][2] == 3);
    try expect(s[1][0] == 4);
    try expect(s[1][1] == 5);
    try expect(s[1][2] == 6);
    try expect(s[2][0] == 7);
    try expect(s[2][1] == 8);
    try expect(s[2][2] == 9);
    try expect(s[0].len == 3);
    try expect(s[1].len == 3);
    try expect(s[2].len == 3);
    try expect(r.seek == encoded.len - 1);
}

test "arr_str" {
    const encoded = "l3:vvve";
    var r = Reader.fixed(encoded);
    const s = try decode([1][]const u8, &r);
    try expect(std.mem.eql(u8, s[0], "vvv"));
    try expect(s.len == 1);
    try expect(r.seek == encoded.len - 1);
}

test "arr_str_2" {
    const encoded = "l3:vvv3:fooe";
    var r = Reader.fixed(encoded);
    const s = try decode([2][]const u8, &r);
    try expect(std.mem.eql(u8, s[0], "vvv"));
    try expect(std.mem.eql(u8, s[1], "foo"));
    try expect(s.len == 2);
    try expect(r.seek == encoded.len - 1);
}

test "decode_str" {
    const encoded = "3:hih";
    var r = Reader.fixed(encoded);
    const s = try decode([]const u8, &r);
    try expect(std.mem.eql(u8, s, "hih"));
    try expect(r.seek == encoded.len - 1);
}

test "empty_str" {
    const encoded = "0:";
    var r = Reader.fixed(encoded);
    const s = try decode([]const u8, &r);
    try expect(std.mem.eql(u8, s, ""));
    try expect(r.seek == encoded.len - 1);
}

test "empty_arr" {
    const encoded = "le";
    var r = Reader.fixed(encoded);
    const s = decode([1][]const u8, &r);
    try expect(s == Error.Empty);
    try expect(r.seek == encoded.len - 1);
}

test "decode_str_2" {
    const encoded = "10:hihhihhihh";
    var r = Reader.fixed(encoded);
    const s = try decode([]const u8, &r);
    try expect(std.mem.eql(u8, s, "hihhihhihh"));
    try expect(r.seek == encoded.len - 1);
}

// Test numbers not close to the max
test "decode_u8" {
    const encoded = "i50e";
    var r = Reader.fixed(encoded);
    const num = try decode(u8, &r);
    try expect(num == 50);
    try expect(r.seek == encoded.len - 1);
}

test "decode_i8" {
    const encoded = "i-50e";
    var r = Reader.fixed(encoded);
    const num = try decode(i8, &r);
    try expect(num == -50);
    try expect(r.seek == encoded.len - 1);
}

test "decode_u16" {
    const encoded = "i65535e";
    var r = Reader.fixed(encoded);
    const num = try decode(u16, &r);
    try expect(num == 65_535);
    try expect(r.seek == encoded.len - 1);
}

test "decode_i16" {
    const encoded = "i-32768e";
    var r = Reader.fixed(encoded);
    const num = try decode(i16, &r);
    try expect(num == -32_768);
    try expect(r.seek == encoded.len - 1);
}

// // Test the max value of a signed int and that the minus sign is optional.
test "decode_i16_2" {
    const encoded = "i32767e";
    var r = Reader.fixed(encoded);
    const num = try decode(i16, &r);
    try expect(num == 32_767);
    try expect(r.seek == encoded.len - 1);
}

test "decode_u32" {
    const encoded = "i4294967295e";
    var r = Reader.fixed(encoded);
    const num = try decode(u32, &r);
    try expect(num == 4_294_967_295);
    try expect(r.seek == encoded.len - 1);
}

test "decode_i32" {
    const encoded = "i-2147483648e";
    var r = Reader.fixed(encoded);
    const num = try decode(i32, &r);
    try expect(num == -2_147_483_648);
    try expect(r.seek == encoded.len - 1);
}

test "zero" {
    const encoded = "i0e";
    var r = Reader.fixed(encoded);
    const num = try decode(u8, &r);
    try expect(num == 0);
    try expect(r.seek == encoded.len - 1);
}

// Test errors

test "leading_zero" {
    const encoded = "i02e";
    var r = Reader.fixed(encoded);
    const err = decode(u8, &r);
    try expect(err == Error.LeadingZero);
    try expect(r.seek == 0);
}

test "leading_zero_2" {
    const encoded = "i-0e";
    var r = Reader.fixed(encoded);
    const err = decode(i8, &r);
    try expect(err == Error.LeadingZero);
    try expect(r.seek == 0);
}

test "overflow" {
    const encoded = "i256e";
    var r = Reader.fixed(encoded);
    const err = decode(u8, &r);
    try expect(err == error.Overflow);
    try expect(r.seek == 0);
}

test "overflow_2" {
    const encoded = "i-296e";
    var r = Reader.fixed(encoded);
    const err = decode(i8, &r);
    try expect(err == error.Overflow);
    try expect(r.seek == 0);
}

test "non_int" {
    const encoded = "i12#e";
    var r = Reader.fixed(encoded);
    const err = decode(i8, &r);
    try expect(err == error.InvalidCharacter);
    try expect(r.seek == 0);
}

test "int_missing_e" {
    const encoded = "i12";
    var r = Reader.fixed(encoded);
    const err = decode(i8, &r);
    try expect(err == Error.MalformedBuffer);
    try expect(r.seek == 0);
}

test "str_wrong_len" {
    // should ignore all the rest of the string
    const encoded = "2:higarbage";
    var r = Reader.fixed(encoded);
    const s = try decode([]const u8, &r);
    try expect(std.mem.eql(u8, s, "hi"));
    try expect(r.seek == 3);
}

test "str_no_len" {
    const encoded = ":hih";
    var r = Reader.fixed(encoded);
    const err = decode([]const u8, &r);
    try expect(err == error.InvalidCharacter);
    try expect(r.seek == 0);
}

test "str_missing_colon" {
    const encoded = "10hihhihhihh";
    var r = Reader.fixed(encoded);
    const err = decode([]const u8, &r);
    try expect(err == Error.MissingColon);
    try expect(r.seek == 0);
}
