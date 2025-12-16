const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

// you basically need to pass your IO interface around the libraries.
// the consumer choses it's async model: threaded, greenthreaded, etc.

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer debug_allocator.deinit();
    const gpa = debug_allocator.allocator();

    var threaded: std.Io.Threaded = .init(gpa);
    defer threaded.deinit();
    const io = threaded.io();

    green_threads(io);
}

fn green_threads(io: Io) !void {
    var queue: Io.Queue([]const u8) = .init(&.{});

    // since io is Threaded, concurrent will make the task run in the thread.
    // an increase the pool size.
    var producer_task = io.concurrent(producer, .{
        io, &queue, "the vampire feed on the wars of mankind.",
    });
    defer producer_task.cancel(io) catch {};

    var consumer_task = io.concurrent(consumer, .{ io, &queue });
    defer _ = consumer_task.cancel(io) catch {};

    const result = try consumer_task.await(io);
    std.debug.print("message received: {s}\n", .{result});
}

fn producer(
    io: Io,
    queue: *Io.Queue([]const u8),
    flavor_text: []const u8,
) !void {
    try queue.putOne(io, flavor_text);
}

fn consumer(
    io: Io,
    queue: *Io.Queue([]const u8),
) ![]const u8 {
    return queue.getOne(io);
}
