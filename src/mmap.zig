const std = @import("std");
const posix = std.posix;
const page_size_min = std.heap.page_size_min;

/// An example on how to use mmap on a buffer
pub fn main() !void {
    var buffer: [page_size_min * 2]u8 = undefined;
    var fixed_buf = std.heap.FixedBufferAllocator.init(&buffer);
    const gpa = fixed_buf.allocator();

    // submission queue
    var sq = try std.Deque(u8).initCapacity(gpa, page_size_min);
    defer sq.deinit(gpa);
    const sqmmap = try posix.mmap(
        null,
        page_size_min,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .ANONYMOUS = true },
        -1,
        0,
    );
    defer posix.munmap(sqmmap);
}
