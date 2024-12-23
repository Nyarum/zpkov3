const std = @import("std");
const tcp = @import("tcp_iouring.zig");
const packet = @import("packet.zig");

pub fn on_connect(client: *tcp.Buffer) !void {
    std.debug.print("Client connected\n", .{});

    // Send first time packet (echo)
    const firstTimePkt = try (packet.FirstTime{}).encode();
    const pkt = try packet.pack(@intFromEnum(packet.Opcode.first_date), firstTimePkt);

    try client.push(pkt);
}

pub fn on_data(buf: []const u8, client: *tcp.Buffer) !void {
    if (buf.len == 2) {
        try client.push(buf);
        return;
    }

    const header = try packet.unpack(buf);
    std.debug.print("Header {any}\n", .{header});

    const opcode: packet.Opcode = @enumFromInt(header.opcode);

    switch (opcode) {
        .auth => {
            const auth = try packet.Auth.decode(header.data);
            _ = auth;

            // Send characters screen
            var charactersScreen = try (packet.CharacterScreen{
                .error_code = 0,
                .character_len = 0,
                .characters = &[_]packet.Character{},
                .pincode = 1,
                .encryption = 0,
            }).encode();
            const pkt = try packet.pack(@intFromEnum(packet.Opcode.response_chars), charactersScreen.getWritten());

            std.debug.print("Sending characters screen {any}\n", .{pkt});

            try client.push(pkt);
        },
        .exit => {
            std.debug.print("Client exited account\n", .{});
            return error.Exit;
        },
        else => {},
    }

    std.debug.print("Hello from server {any}\n", .{buf});

    try client.push(&[_]u8{ 0x00, 0x00 });
}

pub fn main() !void {
    try tcp.init("127.0.0.1", 1973, on_connect, on_data);
}
