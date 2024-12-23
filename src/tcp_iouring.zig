const std = @import("std");
const posix = std.posix;
const net = std.net;
const print = std.debug.print;
const mem = std.mem;
const mpsc = @import("mpsc_atomics.zig");

// Constants for our setup
const QUEUE_DEPTH = 256;
const BACKLOG = 128;
const BUFFER_SIZE = 2048;

pub const Buffer = mpsc.Channel([]const u8, 1024);

// Operation types we'll use
const OpType = enum {
    accept,
    recv,
    send,
};

// Context for operations
const OpContext = struct {
    op_type: OpType,
    buffer: []u8,
    client_addr: ?*std.os.linux.sockaddr = null,
    client_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr),
    fd: i32 = -1,
};

pub fn init(host: []const u8, port: u16, on_connection: anytype, on_data: anytype) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize io_uring
    var ring = try std.os.linux.IoUring.init(QUEUE_DEPTH, 0);
    defer ring.deinit();

    // Create TCP server socket
    const address = try net.Address.parseIp(host, port);
    const server_fd = try posix.socket(address.any.family, posix.SOCK.STREAM | posix.SOCK.NONBLOCK, 0);
    errdefer posix.close(server_fd);

    // Set socket options and bind
    try posix.setsockopt(server_fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(server_fd, &address.any, address.getOsSockLen());
    try posix.listen(server_fd, BACKLOG);

    print("Server listening on {}\n", .{address});

    // Prepare accept context
    const accept_ctx = try allocator.create(OpContext);
    accept_ctx.* = .{
        .op_type = .accept,
        .buffer = try allocator.alloc(u8, BUFFER_SIZE),
    };

    // Queue initial accept
    try queue_accept(&ring, server_fd, accept_ctx);

    // Main event loop
    while (true) {
        // Submit and wait for events
        _ = try ring.submit_and_wait(1);

        const cqe = try ring.copy_cqe();

        const ctx = @as(*OpContext, @ptrFromInt(cqe.user_data));

        switch (ctx.op_type) {
            .accept => {
                if (cqe.res >= 0) {
                    // Accept successful
                    const client_fd: i32 = @intCast(cqe.res);

                    var channel = Buffer{};
                    try on_connection(&channel);
                    const resp = channel.pop();

                    if (resp) |resp_buf| {
                        // Create context for sending response
                        const send_ctx = try allocator.create(OpContext);
                        send_ctx.* = .{
                            .op_type = .send,
                            .buffer = try allocator.dupe(u8, resp_buf),
                            .fd = client_fd,
                        };

                        // Queue send operation (echo back)
                        try queue_send(&ring, send_ctx);
                    } else {
                        return error.NoResponse;
                    }

                    // Create context for receiving data
                    const recv_ctx = try allocator.create(OpContext);
                    recv_ctx.* = .{
                        .op_type = .recv,
                        .buffer = try allocator.alloc(u8, BUFFER_SIZE),
                        .fd = client_fd,
                    };

                    // Queue receive operation
                    try queue_recv(&ring, recv_ctx);

                    // Queue next accept
                    try queue_accept(&ring, server_fd, ctx);
                } else {
                    print("Accept failed with error: {}\n", .{cqe.res});
                    try queue_accept(&ring, server_fd, ctx);
                }
            },
            .recv => {
                if (cqe.res > 0) {
                    // Data received
                    const bytes_read: usize = @intCast(cqe.res);

                    var channel = Buffer{};
                    on_data(ctx.buffer[0..bytes_read], &channel) catch |err| {
                        if (err == error.Exit) {
                            posix.close(ctx.fd);
                            allocator.free(ctx.buffer);
                            allocator.destroy(ctx);
                            continue;
                        }
                    };
                    const resp = channel.pop();

                    if (resp) |resp_buf| {
                        // Create context for sending response
                        const send_ctx = try allocator.create(OpContext);
                        send_ctx.* = .{
                            .op_type = .send,
                            .buffer = try allocator.dupe(u8, resp_buf),
                            .fd = ctx.fd,
                        };

                        // Queue send operation (echo back)
                        try queue_send(&ring, send_ctx);
                    } else {
                        return error.NoResponse;
                    }

                    // Queue another receive
                    try queue_recv(&ring, ctx);
                } else {
                    // Connection closed or error
                    print("Connection closed: fd={}\n", .{ctx.fd});
                    posix.close(ctx.fd);
                    allocator.free(ctx.buffer);
                    allocator.destroy(ctx);
                }
            },
            .send => {
                if (cqe.res >= 0) {
                    // Send completed
                    //print("Sent {} bytes\n", .{cqe.res});
                }
                // Clean up send context
                allocator.free(ctx.buffer);
                allocator.destroy(ctx);
            },
        }
    }
}

// Helper functions to queue operations
fn queue_accept(ring: *std.os.linux.IoUring, server_fd: posix.fd_t, ctx: *OpContext) !void {
    const sqe = try ring.get_sqe();
    sqe.prep_accept(
        server_fd,
        ctx.client_addr,
        &ctx.client_addr_len,
        posix.SOCK.NONBLOCK,
    );
    sqe.user_data = @intFromPtr(ctx);
}

fn queue_recv(ring: *std.os.linux.IoUring, ctx: *OpContext) !void {
    const sqe = try ring.get_sqe();
    sqe.prep_recv(
        ctx.fd,
        ctx.buffer,
        posix.MSG.NOSIGNAL,
    );
    sqe.user_data = @intFromPtr(ctx);
}

fn queue_send(ring: *std.os.linux.IoUring, ctx: *OpContext) !void {
    const sqe = try ring.get_sqe();
    sqe.prep_send(
        ctx.fd,
        ctx.buffer,
        posix.MSG.NOSIGNAL,
    );
    sqe.user_data = @intFromPtr(ctx);
}
