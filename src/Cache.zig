const std = @import("std");
const Mutex = std.Thread.Mutex;
const Allocator = std.mem.Allocator;
const LRU = @import("LRU.zig");
const testing = std.testing;

mutex: Mutex,
allocator: Allocator,
lru: LRU,
cache_bytes: usize,

const Self = @This();

pub fn init(allocator: Allocator, cache_bytes: usize) !Self {
    return .{
        .mutex = Mutex{},
        .allocator = allocator,
        .cache_bytes = cache_bytes,
        .lru = try LRU.init(allocator, cache_bytes),
    };
}

pub fn deinit(self: *Self) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.lru.deinit();
}

pub fn add(self: *Self, key: []const u8, value: []const u8) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    try self.lru.add(key, value);
}

pub fn get(self: *Self, key: []const u8) ?[]const u8 {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.lru.get(key);
}

test "cache.zig: test cache.get()" {
    var cache = try Self.init(testing.allocator, 64);
    defer cache.deinit();

    try cache.add("key1", "value1");
    try testing.expectEqual(cache.get("key1"), "value1");
}
