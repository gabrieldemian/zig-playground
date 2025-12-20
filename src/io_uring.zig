//! Read from STDIN and write to STDOUT using io_uring.
//!
//! There are two types of circular buffers: the Submission Queue (SQ)
//! and the Completion Queue (CQ). Operations to be executed are submitted
//! to the Submission Queue, and upon completion, the kernel places the
//! results into the Completion Queue.
//!
//! The io_uring_setup(2) system call sets up a submission queue (SQ)
//! and completion queue (CQ) with at least `ENTRIES` entries, and
//! returns a file descriptor which can be used to perform subsequent
//! operations on the io_uring instance.

const std = @import("std");
const posix = std.posix;
const print = std.debug.print;
const linux = std.os.linux;

/// Depth of the submission queue.
const ENTRIES: u32 = 1;

/// Buffer for reading/writing stdin/stdout.
var buff: [1024]u8 = undefined;

pub fn main() !void {
    var p: linux.io_uring_params = std.mem.zeroes(linux.io_uring_params);

    // busy-waiting: IORING_SETUP_IOPOLL
    const ring_fd: i32 = @intCast(linux.io_uring_setup(ENTRIES, &p));
    defer posix.close(ring_fd);

    // print("{any}\n", .{p});

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

    const sring_metadata = &SRingMetadata{
        .tail = @ptrCast(@alignCast(sq.ptr + p.sq_off.tail)),
        .mask = @ptrCast(@alignCast(sq.ptr + p.sq_off.ring_mask)),
        .array = @ptrCast(@alignCast(sq.ptr + p.sq_off.array)),
    };

    // map in the submission queue entries array
    const sqes_mmap = try posix.mmap(
        null,
        p.sq_entries * @sizeOf(linux.io_uring_sqe),
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .POPULATE = true },
        @intCast(ring_fd),
        linux.IORING_OFF_SQES,
    );
    defer posix.munmap(sqes_mmap);
    const sqes: []linux.io_uring_sqe = @ptrCast(@alignCast(sqes_mmap));

    const cring_metadata = &CRingMetadata{
        // sq.ptr because sq and cq share the same mmap.
        .head = @ptrCast(@alignCast(sq.ptr + p.cq_off.head)),
        .tail = @ptrCast(@alignCast(sq.ptr + p.cq_off.tail)),
        .mask = @ptrCast(@alignCast(sq.ptr + p.cq_off.ring_mask)),
    };

    // we're not creating a new memory mapping because the completion queue
    // ring directly indexes the shared array of Completion Queue Entries
    const cqes: [*]linux.io_uring_cqe = @ptrCast(@alignCast(sq.ptr + p.cq_off.cqes));

    var res: u32 = 0;

    while (true) {
        // request a read from stdin
        _ = try submit_to_sq(
            sring_metadata,
            sqes,
            posix.STDIN_FILENO,
            ring_fd,
            linux.IORING_OP.READ,
        );

        // ready to read, now read it
        res = try read_from_cq(cring_metadata, cqes);
        // std.debug.print("res: {d}\n", .{res});

        // if ok, write the stdin to stdout
        if (res > 0) {
            _ = try submit_to_sq(
                sring_metadata,
                sqes,
                posix.STDOUT_FILENO,
                ring_fd,
                linux.IORING_OP.WRITE,
            );
            _ = try read_from_cq(cring_metadata, cqes);
        } else if (res == 0) {
            break;
        } else if (res < 0) {
            std.debug.print("error: {d}\n", .{res});
            break;
        }
    }
}

/// Submit a read or write request to the submission queue.
fn submit_to_sq(
    sring: *const SRingMetadata,
    sqes: []linux.io_uring_sqe,
    fd: i32,
    ring_fd: i32,
    op: linux.IORING_OP,
) Error!usize {
    var tail = sring.tail.*;
    const index = tail & sring.mask.*;
    var sqe = &sqes[index];

    // mutate the values required for the operation.
    sqe.opcode = op;
    sqe.fd = fd;
    sqe.addr = @intCast(@intFromPtr(&buff));

    if (op == .READ) {
        @memset(&buff, 0);
        sqe.len = buff.len;
    } else {
        sqe.len = buff.len;
    }

    sring.array[index] = index;
    tail += 1;
    smp_store_release(sring.tail, tail);

    // tell the kernel that the event was submitted,
    // return how many events were submitted.
    const submitted = linux.io_uring_enter(
        ring_fd,
        1,
        1,
        // this flag will make the fn block until min_complete completes.
        linux.IORING_ENTER_GETEVENTS,
        null,
    );

    if (submitted < 0) {
        return Error.Enter;
    }

    return submitted;
}

/// Read from the completion queue and return the result.
fn read_from_cq(
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

inline fn smp_store_release(ptr: anytype, value: @TypeOf(ptr.*)) void {
    @atomicStore(@TypeOf(ptr.*), ptr, value, .release);
}

inline fn smp_load_acquire(ptr: *const u32) @TypeOf(ptr.*) {
    return @atomicLoad(@TypeOf(ptr.*), ptr, .acquire);
}

const SRingMetadata = struct {
    tail: *u32,
    mask: *u32,
    array: [*]u32,
};

const CRingMetadata = struct {
    head: *u32,
    tail: *u32,
    mask: *u32,
};

const Error = error{
    RingEmpty,
    SQFull,
    Entry,
    Enter,
};
