const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const net = std.net;
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
        sq.buffer.ptr,
        page_size_min,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .ANONYMOUS = true },
        -1,
        0,
    );
    defer std.posix.munmap(sqmmap);

    // request queue
    var rq = try std.Deque(u8).initCapacity(gpa, page_size_min);
    defer rq.deinit(gpa);
    const rqmmap = try posix.mmap(
        null,
        page_size_min,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .ANONYMOUS = true },
        -1,
        0,
    );
    defer std.posix.munmap(rqmmap);

    // const params = linux.io_uring_params{
    //     .sq_entries = 1,
    //     .cq_entries = 1,
    //     .flags = 2,
    //     .sq_thread_cpu = 2,
    //     .sq_thread_idle = 2,
    //     .features = 2,
    //     .wq_fd = 2,
    //     .resv = [3]u32{1,2,3},
    // .sq_off= io_sqring_offsets,
    // .cq_off= io_cqring_offsets,
    // };
    // const entries: u32 = 2;
    // const ur = linux.io_uring_setup(entries, &params);
    // _ = ur;
}
