const std = @import("std");

pub fn init(host: []const u8, port: u16) !void {
    // Create a TCP server bound to localhost port 8080
    const address = try std.net.Address.parseIp(host, port);

    // Create and configure the server with options
    var server = try std.net.Address.listen(address, .{
        .kernel_backlog = 128, // How many connections the kernel will queue
        .reuse_address = true, // Allows reusing the address if it's already bound
    });
    defer server.deinit();

    std.debug.print("Server listening on {}\n", .{address});

    while (true) {
        // Accept new client connections
        const connection = try server.accept();
        defer connection.stream.close();

        std.debug.print("Client connected\n", .{});

        // Handle client communication
        var buffer: [1024]u8 = undefined;
        while (true) {
            // Read data from client
            const bytes_read = try connection.stream.read(&buffer);
            if (bytes_read == 0) break; // Client disconnected

            // Echo the data back to client
            try connection.stream.writeAll(buffer[0..bytes_read]);
        }
    }
}
