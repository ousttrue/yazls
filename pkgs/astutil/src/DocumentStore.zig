const std = @import("std");
const FixedPath = @import("./FixedPath.zig");
const Document = @import("./Document.zig");
const Utf8Buffer = @import("./Utf8Buffer.zig");
const logger = std.log.scoped(.DocumentStore);
const Self = @This();

allocator: std.mem.Allocator,
path_document_map: std.StringHashMap(*Document),

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .path_document_map = std.StringHashMap(*Document).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var it = self.path_document_map.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.delete();
    }
    self.path_document_map.deinit();
}

pub fn put(self: *Self, doc: *Document) !void {
    // logger.debug("new {s}", .{doc.path.slice()});
    try self.path_document_map.put(doc.path.slice(), doc);
}

pub fn update(self: *Self, path: FixedPath, text: []const u8) !*Document {
    if (self.path_document_map.get(path.slice())) |doc| {
        // already opened. udpate content
        try doc.update(text);
        return doc;
    } else {
        // new document
        const doc = try Document.new(self.allocator, path, text);
        try self.put(doc);
        return doc;
    }
}

pub fn get(self: Self, path: FixedPath) ?*Document {
    if (self.path_document_map.get(path.slice())) |doc| {
        return doc;
    }

    logger.warn("not found: {s}", .{path.slice()});
    return null;
}

pub fn getOrLoad(self: *Self, path: FixedPath) !?*Document {
    if (self.path_document_map.get(path.slice())) |doc| {
        return doc;
    }

    // load
    if (path.allocReadContents(self.allocator)) |text| {
        defer self.allocator.free(text);

        const new_document = try Document.new(self.allocator, path, text);
        try self.put(new_document);
        return new_document;
    } else |err| {
        logger.err("{s}", .{path.slice()});
        return err;
    }
}
