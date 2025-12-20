const std = @import("std");
const posix = std.posix;
const print = std.debug.print;
const linux = std.os.linux;

const page_size_min = std.heap.page_size_min;
const entries: u32 = 128;

// There are two types of circular buffers: the Submission Queue (SQ)
// and the Completion Queue (CQ). Operations to be executed are submitted
// to the Submission Queue, and upon completion, the kernel places the
// results into the Completion Queue.

pub fn main() !void {
    var p: linux.io_uring_params = std.mem.zeroes(linux.io_uring_params);

    // The io_uring_setup(2) system call sets up a submission queue (SQ)
    // and completion queue (CQ) with at least entries entries, and
    // returns a file descriptor which can be used to perform subsequent
    // operations on the io_uring instance.
    //
    // busy-waiting: IORING_SETUP_IOPOLL
    const ring_fd: i32 = @intCast(linux.io_uring_setup(entries, &p));
    defer posix.close(ring_fd);

    print("{any}\n", .{p});

    if ((p.features & linux.IORING_FEAT_SINGLE_MMAP) != 1) {
        print(
            "kernel doesn't support IORING_FEAT_SINGLE_MMAP\n",
            .{},
        );
        return;
    }

    const sz = p.sq_off.array + p.sq_entries * @sizeOf(u32);

    // map in the submission and completion queue ring buffers.
    // they share the same mmap.
    const sq = try posix.mmap(
        null,
        sz,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .POPULATE = true },
        @intCast(ring_fd),
        linux.IORING_OFF_SQ_RING,
    );
    defer posix.munmap(sq);
    std.debug.print("sq len {d}\n", .{sq.len});
    std.debug.print("sq ptr {any}\n", .{sq.ptr});

    const sring_metadata = SRingMetadata{
        .tail = @ptrCast(@alignCast(sq.ptr + p.sq_off.tail)),
        .mask = @ptrCast(@alignCast(sq.ptr + p.sq_off.ring_mask)),
        .array = @ptrCast(@alignCast(sq.ptr + p.sq_off.array)),
    };
    _ = sring_metadata;

    // map in the submission queue entries array
    const sqes = try posix.mmap(
        null,
        p.sq_entries * @sizeOf(linux.io_uring_sqe),
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .POPULATE = true },
        @intCast(ring_fd),
        linux.IORING_OFF_SQES,
    );
    defer posix.munmap(sqes);

    const cring_metadata = &CRingMetadata{
        // sq.ptr because sq and cq share the same mmap.
        .head = @ptrCast(@alignCast(sq.ptr + p.cq_off.head)),
        .tail = @ptrCast(@alignCast(sq.ptr + p.cq_off.tail)),
        .mask = @ptrCast(@alignCast(sq.ptr + p.cq_off.ring_mask)),
    };

    // we're not creating a new memory mapping because the completion queue
    // ring directly indexes the shared array of Completion Queue Entries
    const cqes: [*]linux.io_uring_cqe = @ptrCast(@alignCast(sq.ptr + p.cq_off.cqes));
    const res = try read_from_cqe(cring_metadata, cqes);
    std.debug.print("cqe res: {d}", .{res});
}

/// Read from the completion queue and return the result.
fn read_from_cqe(
    cring: *const CRingMetadata,
    cqes: [*]linux.io_uring_cqe,
) Error!u32 {
    var head = smp_load_acquire(cring.head);

    if (head == cring.tail.*) {
        return Error.RingEmpty;
    }

    const cqe = cqes[head & (cring.mask.*)];
    if (cqe.res < 0) {
        return Error.Entry;
    }

    head += 1;
    smp_store_release(cring.head, head);

    return @intCast(cqe.res);
}

inline fn smp_store_release(ptr: *u32, value: u32) void {
    @atomicStore(@TypeOf(value), ptr, value, .release);
}

inline fn smp_load_acquire(ptr: *const u32) u32 {
    return @atomicLoad(u32, ptr, .acquire);
}

const SRingMetadata = struct {
    tail: *u32,
    mask: *u32,
    array: *u32,
};

const CRingMetadata = struct {
    head: *u32,
    tail: *u32,
    mask: *u32,
};

const Error = error{
    RingEmpty,
    Entry,
};
