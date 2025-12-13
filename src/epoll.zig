const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const net = std.net;
const posix = std.posix;
const linux = std.os.linux;

var timespec: posix.timespec = .{ .sec = 2, .nsec = 0 };

pub fn main() !void {
    var buffer: [1 << 4]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buffer);
    const gpa = alloc.allocator();

    var threaded = Io.Threaded.init(gpa);
    defer threaded.deinit();
    const io = threaded.io();
    _ = io;

    // no flags for this system call
    // `efd` is the file descriptor of this epoll.
    const efd = try posix.epoll_create1(0);
    defer posix.close(efd);

    // read fd = pipe[0] write fd = pipe[1]
    const pipe = try posix.pipe();
    defer posix.close(pipe[0]);

    {
        // monitor one end of the pipe
        var event = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .fd = pipe[0] } };
        // register the pipe fd
        try posix.epoll_ctl(efd, linux.EPOLL.CTL_ADD, pipe[0], &event);
    }

    const thread = try std.Thread.spawn(.{}, shutdown, .{pipe[1]});
    thread.detach();

    var ready_list: [16]linux.epoll_event = undefined;

    while (true) {
        // -1 means to block indefinitely and wait for events.
        const ready_count = posix.epoll_wait(efd, &ready_list, -1);

        for (ready_list[0..ready_count]) |ready| {
            if (ready.data.fd == pipe[0]) {
                std.debug.print("shutting down\n", .{});
                return;
            }
        }
    }
}

fn shutdown(signal: posix.socket_t) void {
    _ = std.posix.system.nanosleep(&timespec, &timespec);
    posix.close(signal);
}
