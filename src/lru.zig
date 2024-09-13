const std = @import("std");
const Allocator = std.mem.Allocator;
const DoublyLinkedList = std.DoublyLinkedList;
const testing = std.testing;

max_bytes: usize,
nbytes: usize,
allocator: Allocator,
map: std.StringArrayHashMap(*Node),
list: DoublyLinkedList(Entry),

const Self = @This();

pub fn init(allocator: Allocator, max_bytes: usize) !Self {
    var self = Self{
        .max_bytes = max_bytes,
        .nbytes = 0,
        .allocator = allocator,
        .map = std.StringArrayHashMap(*Node).init(allocator),
        .list = DoublyLinkedList(Entry){},
    };
    try self.map.ensureTotalCapacity(self.max_bytes);
    return self;
}

pub fn deinit(self: *Self) void {
    while (self.removeOldest()) {}
    std.debug.assert(self.nbytes == 0);
    self.map.deinit();
}

pub fn get(self: *Self, key: []const u8) ?[]const u8 {
    const node = self.map.get(key) orelse return null;
    self.list.remove(node);
    self.list.prepend(node);
    return node.data.value;
}

pub fn removeOldest(self: *Self) bool {
    if (self.list.pop()) |node| {
        _ = self.map.swapRemove(node.data.key);
        self.nbytes -= node.data.key.len + node.data.value.len;
        self.allocator.destroy(node);

        return true;
    }
    return false;
}

pub fn add(self: *Self, key: []const u8, value: []const u8) !void {
    if (self.map.get(key)) |node| {
        self.list.remove(node);
        self.list.prepend(node);
        self.nbytes += value.len - node.data.value.len;
        node.data.value = value;
    } else {
        const node = try self.allocator.create(Node);
        node.* = .{ .data = Entry{ .key = key, .value = value } };
        try self.map.put(key, node);
        self.list.prepend(node);
        self.nbytes += key.len + value.len;
    }

    while (self.nbytes > self.max_bytes) {
        _ = self.removeOldest();
    }
}

pub fn len(self: *Self) usize {
    return self.list.len;
}

const Entry = struct {
    key: []const u8,
    value: []const u8,
};

const Node = DoublyLinkedList(Entry).Node;

test "lru.zig: test lru.get()" {
    var cache = try Self.init(testing.allocator, 1000);
    defer cache.deinit();

    try cache.add("key1", "1234");

    const result = cache.get("key1");
    try std.testing.expectEqual(result, "1234");
}

test "lru.zig: test lru.removeOldest()" {
    const keys = &[_][]const u8{ "key1", "key2", "key3" };
    const values = &[_][]const u8{ "value1", "value2", "v3" };

    var cache = try Self.init(
        testing.allocator,
        keys[0].len + keys[1].len + values[0].len + values[1].len,
    );
    defer cache.deinit();

    try cache.add(keys[0], values[0]);
    try cache.add(keys[1], values[1]);
    try cache.add(keys[2], values[2]);

    try std.testing.expectEqual(cache.len(), 2);
}
