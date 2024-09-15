const std = @import("std");
const Cache = @import("Cache.zig");
const RwLock = std.Thread.RwLock;
const StringArrayHashMap = std.StringArrayHashMap;
const Allocator = std.mem.Allocator;
const StaticStringMap = std.StaticStringMap;
const testing = std.testing;

pub fn ZeeCache(comptime DB: type) type {
    if (!@hasDecl(DB, "getter"))
        @compileError("DB must have a getter method");

    return struct {
        allocator: Allocator = undefined,
        groups: StringArrayHashMap(*DbGroup),
        rwl: RwLock = RwLock{},

        const dbtype = DB;
        const DbGroup = Group(dbtype);

        const Self = @This();

        pub fn init(
            allocator: Allocator,
        ) Self {
            return .{
                .allocator = allocator,
                .groups = StringArrayHashMap(*DbGroup).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.rwl.lock();
            defer self.rwl.unlock();

            for (self.groups.values()) |g| {
                g.cache.deinit();
                self.allocator.destroy(g);
            }
            self.groups.deinit();
        }

        pub fn newGroup(self: *Self, name: []const u8, cache_bytes: usize, db: dbtype) !*DbGroup {
            self.rwl.lock();
            defer self.rwl.unlock();

            const g = try self.allocator.create(Group(dbtype));
            g.name = name;
            g.cache = try Cache.init(self.allocator, cache_bytes);
            g.db = db;

            try self.groups.put(name, g);
            return g;
        }

        pub fn getGroup(self: *Self, name: []const u8) *Group {
            self.rwl.lockShared();
            defer self.rwl.unlockShared();

            const g = self.groups.get(name) orelse return null;
            return g;
        }
    };
}

pub fn Group(comptime dbtype: type) type {
    return struct {
        name: []const u8,
        cache: Cache,
        db: dbtype,

        const Self = @This();

        pub fn get(self: *Self, key: []const u8) ?[]const u8 {
            if (key.len == 0) {
                return null;
            }

            if (self.cache.get(key)) |v| {
                std.debug.print("[GeeCache] hit\n", .{});
                return v;
            }

            return self.load(key);
        }

        fn load(self: *Self, key: []const u8) ?[]const u8 {
            return self.getLocally(key);
        }

        fn getLocally(self: *Self, key: []const u8) ?[]const u8 {
            const value = self.db.getter(key) orelse return null;
            self.populateCache(key, value) catch return null;
            return value;
        }

        fn populateCache(self: *Self, key: []const u8, value: []const u8) !void {
            try self.cache.add(key, value);
        }
    };
}

test "ZeeCache: test get" {
    const db = struct {
        map: StaticStringMap([]const u8),

        const Self = @This();

        pub fn getter(self: Self, key: []const u8) ?[]const u8 {
            std.debug.print("[SlowDB] search key {s}\n", .{key});
            return self.map.get(key) orelse {
                std.debug.print("[SlowDB] key {s} not found\n", .{key});
                return null;
            };
        }
    }{
        .map = StaticStringMap([]const u8).initComptime(.{
            .{ "Tom", "630" },
            .{ "Jack", "589" },
            .{ "Sam", "567" },
        }),
    };

    var zee = ZeeCache(@TypeOf(db)).init(testing.allocator);
    defer zee.deinit();

    var group = try zee.newGroup("scores", 2 << 10, db);

    for (db.map.keys()) |k| {
        const v = db.map.get(k).?;
        try testing.expectEqual(group.get(k), v);
        try testing.expectEqual(group.get(k), v);
    }
    try testing.expectEqual(group.get("unknown"), null);
}
