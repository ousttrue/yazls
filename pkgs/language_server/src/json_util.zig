const std = @import("std");
const logger = std.log.scoped(.json_util);

fn allocToJson(allocator: std.mem.ArenaAllocator, value: anytype) []const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    std.json.stringify(value, .{ .emit_null_optional_fields = false }, buf.writer()) catch @panic("stringify");
    return buf.toOwnedSlice();
}

fn isNull(x: anytype) bool {
    const T = @TypeOf(x);
    switch (@typeInfo(T)) {
        .Optional => {
            return x == null;
        },
        else => {},
    }
    return false;
}

pub fn allocToResponse(allocator: std.mem.Allocator, id: i64, result: anytype) []const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    var w = std.json.writeStream(buf.writer(), 10);

    {
        w.beginObject() catch unreachable;
        defer w.endObject() catch unreachable;

        w.objectField("id") catch unreachable;
        w.emitNumber(id) catch unreachable;

        if (!isNull(result)) {
            w.objectField("result") catch unreachable;
            std.json.stringify(result, .{ .emit_null_optional_fields = false }, w.stream) catch unreachable;
            w.state_index -= 1;
        }
    }

    return buf.toOwnedSlice();
}

pub fn allocToNotification(allocator: std.mem.Allocator, method: []const u8, notification: anytype) []const u8
{
    var buf = std.ArrayList(u8).init(allocator);
    var w = std.json.writeStream(buf.writer(), 10);

    {
        w.beginObject() catch unreachable;
        defer w.endObject() catch unreachable;

        w.objectField("method") catch unreachable;
        w.emitString(method) catch unreachable;

        w.objectField("params") catch unreachable;
        std.json.stringify(notification, .{ .emit_null_optional_fields = false }, w.stream) catch unreachable;
        w.state_index -= 1;
    }

    return buf.toOwnedSlice();
}

pub fn logJson(allocator: std.mem.ArenaAllocator, json: ?std.json.Value) void {
    var json_buffer = std.ArrayList(u8).init(allocator);
    defer json_buffer.deinit();
    if (json) |value| {
        value.jsonStringify(
            .{ .emit_null_optional_fields = false, .whitespace = .{ .indent_level = 1 } },
            json_buffer.writer(),
        ) catch @panic("stringify");
        logger.debug("{s}", .{json_buffer.items});
    } else {
        logger.debug("null", .{});
    }
}

pub fn logT(allocator: std.mem.Allocator, value: anytype) void {
    const json = allocToJson(allocator, value);
    defer allocator.free(json);
    logger.debug("{s}", .{json});
}
