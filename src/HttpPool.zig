const std = @import("std");
const mem = std.mem;
const Thread = std.Thread;
const http = std.http;
const net = std.net;
const testing = std.testing;

const ZeeCache = @import("ZeeCache.zig");
const Group = ZeeCache.Group;
const Getter = ZeeCache.Getter;
const log = std.log.scoped(.Server);

const default_base_path = "/_zeecache/";
const HttpPool = @This();

addr: net.Address,
base_path: []const u8,
zee: *ZeeCache,

fn init(zee: ZeeCache, buf: []const u8, port: u16) HttpPool {
    return .{
        .addr = try net.Address.parseIp4(buf, port),
        .base_path = default_base_path,
        .zee = zee,
    };
}

fn accept(connection: net.Server.Connection, zee: *ZeeCache) void {
    defer connection.stream.close();

    var read_buffer: [1024]u8 = undefined;
    var server = http.Server.init(connection, &read_buffer);

    while (server.state == .ready) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                log.err("closing http connection: {s}", .{@errorName(err)});
                return;
            },
        };
        serverHttp(&request, zee) catch |err| {
            std.log.err("unable to serve {s}: {s}", .{ request.head.target, @errorName(err) });
            return;
        };
    }
}

fn serverHttp(request: *std.http.Server.Request, zee: *ZeeCache) !void {
    if (!mem.startsWith(u8, request.head.target, default_base_path)) {
        log.err("HttpPool serving unexpected path: {s}", .{request.head.target});
        return;
    }

    log.info("{s} {s}", .{ @tagName(request.head.method), request.head.target });

    var it = mem.splitScalar(u8, request.head.target[default_base_path.len..], '/');
    const group_name = it.next() orelse {
        try request.respond("bad_request", .{ .status = .bad_request });
        return;
    };
    const key = it.next() orelse {
        try request.respond("bad_request", .{ .status = .bad_request });
        return;
    };

    var group = zee.getGroup(group_name) orelse {
        const content = try std.fmt.allocPrint(zee.allocator, "no such group: {s}", .{group_name});
        try request.respond(content, .{ .status = .not_found });
        return;
    };

    const view = group.get(key) orelse {
        const content = try std.fmt.allocPrint(zee.allocator, "fail to get value for key {s}", .{key});
        try request.respond(content, .{ .status = .internal_server_error });
        return;
    };

    try request.respond(view, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/octet-stream" },
        },
    });
}

test "test HttpPool" {
    testing.log_level = .info;

    const db = Getter{
        .map = std.StaticStringMap([]const u8).initComptime(.{
            .{ "Tom", "630" },
            .{ "Jack", "589" },
            .{ "Sam", "567" },
        }),
    };

    var zee = ZeeCache.init(testing.allocator);
    defer zee.deinit();
    _ = try zee.newGroup("scores", 2 << 10, db);

    const address = try net.Address.parseIp4("127.0.0.1", 9999);

    var http_server = try address.listen(.{
        .reuse_address = true,
        .reuse_port = true,
    });
    defer http_server.deinit();

    std.log.scoped(.Server).info("Start server at http://localhost:{}", .{address.getPort()});

    while (true) {
        const connection = try http_server.accept();
        const thread = try Thread.spawn(.{}, accept, .{ connection, &zee });
        thread.detach();
    }
}
