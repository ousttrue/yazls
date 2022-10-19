const std = @import("std");
const FixedPath = @import("./FixedPath.zig");
const logger = std.log.scoped(.ImportSolver);

pub fn unquote(text: []const u8) []const u8 {
    return if (text.len > 2 and text[0] == '"' and text[text.len - 1] == '"')
        text[1 .. text.len - 1]
    else
        text;
}

// pub const ImportType = union(enum) {
//     pkg: []const u8,
//     file: []const u8,

//     pub fn fromText(text: []const u8) @This() {
//         return if (std.mem.endsWith(u8, text, ".zig")) .{ .file = unquote(text) } else .{ .pkg = unquote(text) };
//     }
// };

const Self = @This();

allocator: std.mem.Allocator,
pkg_path_map: std.StringHashMap(FixedPath),
c_import: ?FixedPath = null,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .pkg_path_map = std.StringHashMap(FixedPath).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var it = self.pkg_path_map.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
    }
    self.pkg_path_map.deinit();
}

pub fn push(self: *Self, pkg: []const u8, path: FixedPath) !void {
    if (self.pkg_path_map.fetchRemove("c")) |kv| {
        self.allocator.free(kv.key);
    }

    const copy = try self.allocator.dupe(u8, pkg);
    try self.pkg_path_map.put(copy, path);
}

// pub fn remove(self: *Self, pkg: []const u8) !void
// {

// }

pub fn solve(self: Self, import_from: FixedPath, import: []const u8) ?FixedPath {
    const text = unquote(import);
    if (std.mem.endsWith(u8, text, ".zig")) {
        // relative path
        if (import_from.parent()) |parent| {
            return parent.child(text);
        } else {
            return null;
        }
    } else {
        // pkg
        if (self.pkg_path_map.get(text)) |found| {
            return found;
        } else {
            var tmp = std.ArrayList(u8).init(self.allocator);
            defer tmp.deinit();
            var writer = tmp.writer();
            writer.print("pkg '{s}' not found\n", .{text}) catch unreachable;
            var it = self.pkg_path_map.iterator();
            while (it.next()) |e| {
                writer.print(", {s}", .{e.key_ptr.*}) catch unreachable;
            }
            logger.debug("{s}", .{tmp.items});
            return null;
        }
    }
}
