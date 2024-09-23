const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoArrayHashMap = std.AutoArrayHashMap;
const ArrayList = std.ArrayList;
const Crc32 = std.hash.Crc32;
const testing = std.testing;

const Map = struct {
    allocator: Allocator,
    replicas: usize,
    keys: ArrayList(usize),
    hashMap: AutoArrayHashMap(usize, []const u8),

    pub fn init(allocator: Allocator, replicas: usize) Map {
        return .{
            .allocator = allocator,
            .replicas = replicas,
            .keys = ArrayList(usize).init(allocator),
            .hashMap = AutoArrayHashMap(usize, []const u8).init(allocator),
        };
    }

    pub fn deinit(m: *Map) void {
        m.keys.deinit();
        m.hashMap.deinit();
    }

    pub fn add(m: *Map, keys: []const []const u8) !void {
        for (keys) |key| {
            for (0..m.replicas) |i| {
                const hash = blk: {
                    if (i == 0) {
                        break :blk Crc32.hash(key);
                    } else {
                        const hash_key = try std.fmt.allocPrint(m.allocator, "{d}{s}", .{ i, key });
                        defer m.allocator.free(hash_key);
                        break :blk Crc32.hash(hash_key);
                    }
                };

                try m.keys.append(hash);
                try m.hashMap.put(hash, key);
            }
        }
        std.mem.sort(usize, m.keys.items, {}, comptime std.sort.asc(usize));
    }

    pub fn get(m: *Map, key: []const u8) []const u8 {
        if (m.keys.items.len == 0) {
            return "";
        }
        const hash = Crc32.hash(key);
        const idx = std.sort.lowerBound(usize, m.keys.items, @as(usize, hash), struct {
            fn orderUsize(context: usize, item: usize) std.math.Order {
                return std.math.order(context, item);
            }
        }.orderUsize);

        return m.hashMap.get(m.keys.items[idx % m.keys.items.len]) orelse "";
    }
};

test "test ConsistentHash" {
    var map = Map.init(testing.allocator, 3);
    defer map.deinit();

    try map.add(&[_][]const u8{ "6", "4", "2" });

    const test_cases = std.StaticStringMap([]const u8).initComptime(.{
        .{ "2", "2" },
        .{ "4", "4" },
        .{ "6", "6" },
        .{ "12", "2" },
        .{ "14", "4" },
        .{ "16", "6" },
        .{ "22", "2" },
        .{ "24", "4" },
        .{ "26", "6" },
    });

    for (test_cases.keys(), test_cases.values()) |key, value| {
        const result = map.get(key);
        std.debug.print("result: {s}\n", .{result});
        try testing.expect(std.mem.eql(u8, value, result));
    }
}
