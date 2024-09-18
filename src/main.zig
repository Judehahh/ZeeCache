const std = @import("std");
const Thread = std.Thread;
const http = std.http;
const net = std.net;
const log = std.log.scoped(.server);

pub fn main() !void {
    const address = try net.Address.parseIp4("127.0.0.1", 9999);

    var http_server = try address.listen(.{
        .reuse_address = true,
        .reuse_port = true,
    });
    defer http_server.deinit();

    log.info("Start server at http://localhost:{}", .{address.getPort()});

    while (true) {
        var connection = try http_server.accept();
        const thread = try Thread.spawn(.{}, handler, .{&connection});
        thread.detach();
    }
}

fn handler(connection: *net.Server.Connection) !void {
    defer connection.stream.close();

    var read_buffer: [1024]u8 = undefined;
    var server = http.Server.init(connection.*, &read_buffer);

    var request = try server.receiveHead();
    try request.respond("Greeting from ZeeCache!\n", .{ .keep_alive = false });
}
