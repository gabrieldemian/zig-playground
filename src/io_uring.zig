const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const page_size_min = std.heap.page_size_min;

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

    // completion queue
    var cq = try std.Deque(u8).initCapacity(gpa, page_size_min);
    defer cq.deinit(gpa);
    const cqmmap = try posix.mmap(
        null,
        page_size_min,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .ANONYMOUS = true },
        -1,
        0,
    );
    defer posix.munmap(cqmmap);

    // initialize a zeroed array and cast to a struct
    var pp: [@sizeOf(linux.io_uring_params)]u8 align(@alignOf(linux.io_uring_params)) = undefined;
    @memset(&pp, 0);
    const p: *linux.io_uring_params = @ptrCast(&pp);

    // The io_uring_setup(2) system call sets up a submission queue (SQ)
    // and completion queue (CQ) with at least entries entries, and
    // returns a file descriptor which can be used to perform subsequent
    // operations on the io_uring instance.
    const ring_fd = linux.io_uring_setup(1, p);
    std.debug.print("ring_fd {any}\n", .{ring_fd});
    std.debug.print("p {any}\n", .{p.*});
}
