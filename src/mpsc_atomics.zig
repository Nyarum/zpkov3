const std = @import("std");
const Value = std.atomic.Value;
const Allocator = std.mem.Allocator;

pub fn Channel(comptime T: type, bound: usize) type {
    return struct {
        arr: [bound]T = undefined,
        head: Value(usize) = Value(usize){ .raw = 0 },
        tail: Value(usize) = Value(usize){ .raw = 0 },

        const Self = @This();

        pub fn push(self: *Self, v: T) error{ChannelFull}!void {
            // Get current head and check if channel is full
            const head = self.head.load(.acquire);
            const tail = self.tail.load(.acquire);
            if (head - tail >= bound) {
                return error.ChannelFull;
            }

            // Atomically increment head and write value
            const index = self.head.fetchAdd(1, .acq_rel) % bound;
            self.arr[index] = v;
        }

        pub fn pop(self: *Self) ?T {
            const tail = self.tail.load(.acquire);
            defer std.debug.print("Tail {any}\n", .{tail});
            const head = self.head.load(.acquire);

            if (tail >= head) {
                return null;
            }

            const index = tail % bound;
            const v = self.arr[index];

            // Increment tail after reading
            _ = self.tail.fetchAdd(1, .release);

            return v;
        }
    };
}

test "mpsc_atomics reach max" {
    var channel = Channel(i32, 2){};

    try channel.push(2);
    try channel.push(2);

    _ = channel.pop();
    _ = channel.pop();
    try channel.push(2);
}

test "mpsc_atomics" {
    var channel = Channel(i32, 1024){};

    try channel.push(2);
    try channel.push(2);
    try channel.push(2);
    try channel.push(2);

    _ = channel.pop();
    _ = channel.pop();
    _ = channel.pop();
    _ = channel.pop();

    if (channel.pop() == null) {
        std.debug.print("Channel is empty\n", .{});
    } else {
        std.debug.print("Channel is not empty\n", .{});
    }
}

test "mpsc_atomics_thread" {
    var channel = Channel(i32, 10240){};

    var thread = try std.Thread.spawn(.{}, struct {
        fn run(channel_link: *Channel(i32, 10240)) !void {
            std.debug.print("Hello from thread\n", .{});
            for (0..6144) |i| {
                try channel_link.push(@intCast(i));
            }
        }
    }.run, .{&channel});

    var thread2 = try std.Thread.spawn(.{}, struct {
        fn run(channel_link: *Channel(i32, 10240)) !void {
            std.debug.print("Hello from thread\n", .{});
            try channel_link.push(4);
        }
    }.run, .{&channel});

    var thread3 = try std.Thread.spawn(.{}, struct {
        fn run(channel_link: *Channel(i32, 10240)) !void {
            std.debug.print("Hello from thread\n", .{});
            try channel_link.push(7);

            std.time.sleep(50000000);
            try channel_link.push(7);
            try channel_link.push(7);
            try channel_link.push(7);
            try channel_link.push(7);
            try channel_link.push(7);
        }
    }.run, .{&channel});

    var finalRes: i32 = 0;
    var thread4 = try std.Thread.spawn(.{}, struct {
        fn run(channel_link: *Channel(i32, 10240), finalRes2: *i32) void {
            var arr: [10240]i32 = undefined;
            var i: usize = 0;
            while (true) {
                if (channel_link.pop()) |v| {
                    arr[i] = v;
                    i = i + 1;
                } else {
                    std.time.sleep(1000000000);
                    break;
                }
            }

            finalRes2.* = @intCast(i);
        }
    }.run, .{ &channel, &finalRes });

    thread.join();
    thread2.join();
    thread3.join();
    thread4.join();

    if (finalRes == 6146) {
        std.debug.print("Final res is correct\n", .{});
    } else {
        std.debug.print("Final res is incorrect\n", .{});
    }
}
