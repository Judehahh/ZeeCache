const std = @import("std");
const Cache = @import("Cache.zig");
const RwLock = std.Thread.RwLock;
const StringArrayHashMap = std.StringArrayHashMap;
const Allocator = std.mem.Allocator;
const StaticStringMap = std.StaticStringMap;
const testing = std.testing;

allocator: Allocator = undefined,
groups: StringArrayHashMap(*Group),
rwl: RwLock = .{},

const ZeeCache = @This();

pub fn init(allocator: Allocator) ZeeCache {
    return .{
        .allocator = allocator,
        .groups = StringArrayHashMap(*Group).init(allocator),
    };
}

pub fn deinit(z: *ZeeCache) void {
    z.rwl.lock();
    defer z.rwl.unlock();

    for (z.groups.values()) |g| {
        g.cache.deinit();
        z.allocator.destroy(g);
    }
    z.groups.deinit();
}

pub fn newGroup(z: *ZeeCache, name: []const u8, cache_bytes: usize, db: Getter) !*Group {
    z.rwl.lock();
    defer z.rwl.unlock();

    const g = try z.allocator.create(Group);
    g.name = name;
    g.cache = try Cache.init(z.allocator, cache_bytes);
    g.db = db;

    try z.groups.put(name, g);
    return g;
}

pub fn getGroup(z: *ZeeCache, name: []const u8) ?*Group {
    z.rwl.lockShared();
    defer z.rwl.unlockShared();

    const g = z.groups.get(name) orelse return null;
    return g;
}

pub const Group = struct {
    name: []const u8,
    cache: Cache,
    db: Getter,

    pub fn get(g: *Group, key: []const u8) ?[]const u8 {
        if (key.len == 0) {
            return null;
        }

        if (g.cache.get(key)) |v| {
            std.log.scoped(.GeeCache).info("hit", .{});
            return v;
        }

        return g.load(key);
    }

    fn load(g: *Group, key: []const u8) ?[]const u8 {
        return g.getLocally(key);
    }

    fn getLocally(g: *Group, key: []const u8) ?[]const u8 {
        const value = g.db.get(key) orelse return null;
        g.populateCache(key, value) catch return null;
        return value;
    }

    fn populateCache(g: *Group, key: []const u8, value: []const u8) !void {
        try g.cache.add(key, value);
    }
};

pub const Getter = struct {
    map: StaticStringMap([]const u8),

    const Self = @This();

    pub fn get(self: *Self, key: []const u8) ?[]const u8 {
        std.log.scoped(.SlowDB).info("search key {s}", .{key});
        return self.map.get(key) orelse {
            std.log.scoped(.SlowDB).info("key {s} not found", .{key});
            return null;
        };
    }
};

test "ZeeCache: test get" {
    testing.log_level = .info;

    const db = Getter{
        .map = StaticStringMap([]const u8).initComptime(.{
            .{ "Tom", "630" },
            .{ "Jack", "589" },
            .{ "Sam", "567" },
        }),
    };

    var zee = ZeeCache.init(testing.allocator);
    defer zee.deinit();

    var group = try zee.newGroup("scores", 2 << 10, db);

    for (db.map.keys()) |k| {
        const v = db.map.get(k).?;
        try testing.expectEqual(group.get(k), v);
        try testing.expectEqual(group.get(k), v);
    }
    try testing.expectEqual(group.get("unknown"), null);
}
