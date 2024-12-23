const std = @import("std");
const mpsc = @import("mpsc_atomics.zig");
const tcp = @import("tcp_iouring.zig");

pub fn on_connect(client: *tcp.Buffer) !void {
    std.debug.print("Client connected\n", .{});

    try client.push("Hello from server\n");
}

pub fn on_data(buf: []const u8, client: *tcp.Buffer) !void {
    std.debug.print("Hello from server {any}\n", .{buf});

    try client.push(buf);
}

pub fn main() !void {
    //var channel = mpsc.Channel(i32, 1024){};
    try tcp.init("127.0.0.1", 1973, on_connect, on_data);
}
