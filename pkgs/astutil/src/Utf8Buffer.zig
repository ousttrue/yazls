const std = @import("std");
const Line = @import("./Line.zig");

pub fn allocLineHeads(allocator: std.mem.Allocator, text: []const u8) ![]const u32 {
    var line_heads = std.ArrayList(u32).init(allocator);
    line_heads.resize(0) catch unreachable;
    line_heads.append(0) catch unreachable;
    var i: u32 = 0;
    while (i < text.len) {
        const c = text[i];
        if (c == '\n') {
            line_heads.append(@intCast(u32, i + 1)) catch unreachable;
        }
        i += @intCast(u32, try std.unicode.utf8ByteSequenceLength(c));
    }
    return line_heads.toOwnedSlice();
}

const Self = @This();

allocator: std.mem.Allocator,
// This is a substring of mem starting at 0
text: [:0]u8,
// This holds the memory that we have actually allocated.
mem: []u8,
line_heads: []const u32,

pub fn init(allocator: std.mem.Allocator, text: []const u8) !Self {
    const duped_text = try allocator.dupeZ(u8, text);
    errdefer allocator.free(duped_text);
    var self = Self{
        .allocator = allocator,
        .text = duped_text,
        // Extra +1 to include the null terminator
        .mem = duped_text.ptr[0 .. duped_text.len + 1],
        .line_heads = undefined,
    };
    self.line_heads = try allocLineHeads(allocator, self.text);
    return self;
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.line_heads);
    self.allocator.free(self.mem);
}

pub fn applyChanges(self: *Self, content_changes: std.json.Array, encoding: Line.Encoding) !void {
    for (content_changes.items) |change| {
        if (change.Object.get("range")) |range| {
            std.debug.assert(@ptrCast([*]const u8, self.text.ptr) == self.mem.ptr);

            // TODO: add tests and validate the JSON
            const start_obj = range.Object.get("start").?;
            const end_obj = range.Object.get("end").?;

            const change_text = change.Object.get("text").?.String;
            const start_line = try self.getLine(@intCast(u32, start_obj.Object.get("line").?.Integer));
            const start_index = try start_line.getBytePosition(@intCast(u32, start_obj.Object.get("character").?.Integer), encoding);
            const end_line = try self.getLine(@intCast(u32, end_obj.Object.get("line").?.Integer));
            const end_index = try end_line.getBytePosition(@intCast(u32, end_obj.Object.get("character").?.Integer), encoding);

            const old_len = self.text.len;
            const new_len = old_len - (end_index - start_index) + change_text.len;
            if (new_len >= self.mem.len) {
                // We need to reallocate memory.
                // We reallocate twice the current filesize or the new length, if it's more than that
                // so that we can reduce the amount of realloc calls.
                // We can tune this to find a better size if needed.
                const realloc_len = std.math.max(2 * old_len, new_len + 1);
                self.mem = try self.allocator.realloc(self.mem, realloc_len);
            }

            // The first part of the string, [0 .. start_index] need not be changed.
            // We then copy the last part of the string, [end_index ..] to its
            //    new position, [start_index + change_len .. ]
            if (new_len < old_len) {
                std.mem.copy(u8, self.mem[start_index + change_text.len ..][0 .. old_len - end_index], self.mem[end_index..old_len]);
            } else {
                std.mem.copyBackwards(u8, self.mem[start_index + change_text.len ..][0 .. old_len - end_index], self.mem[end_index..old_len]);
            }
            // Finally, we copy the changes over.
            std.mem.copy(u8, self.mem[start_index..][0..change_text.len], change_text);

            // Reset the text substring.
            self.mem[new_len] = 0;
            self.text = self.mem[0..new_len :0];
        } else {
            const change_text = change.Object.get("text").?.String;
            const old_len = self.text.len;

            if (change_text.len >= self.mem.len) {
                // Like above.
                const realloc_len = std.math.max(2 * old_len, change_text.len + 1);
                self.mem = try self.allocator.realloc(self.mem, realloc_len);
            }

            std.mem.copy(u8, self.mem[0..change_text.len], change_text);
            self.mem[change_text.len] = 0;
            self.text = self.mem[0..change_text.len :0];
        }
    }
    self.allocator.free(self.line_heads);
    self.line_heads = try allocLineHeads(self.allocator, self.text);
}

pub fn getLineIndexFromBytePosition(self: Self, byte_position: usize) !usize {
    if (byte_position > self.text.len) {
        return error.OutOfRange;
    }
    const line_count = self.line_heads.len;
    var top: usize = 0;
    var bottom: usize = line_count - 1;
    while (true) {
        var line: usize = (bottom + top) / 2;
        const begin = self.line_heads[line];
        const end = if (line + 1 < line_count)
            self.line_heads[line + 1] - 1
        else
            self.text.len;
        // std.debug.print("line: [{}, {} => {}]: {} ~ {} <= {}\n", .{ top, bottom, line, begin, end, byte_position });
        if (byte_position >= begin and byte_position <= end) {
            return line;
        }
        if (top == bottom) {
            unreachable;
        }

        if (byte_position < begin) {
            if (bottom != line) {
                bottom = line;
            } else {
                bottom = line - 1;
            }
        } else if (byte_position > end) {
            if (top != line) {
                top = line;
            } else {
                top = line + 1;
            }
        } else {
            unreachable;
        }
    }
    unreachable;
}

pub fn getLine(self: Self, line_index: u32) !Line {
    const line_count = self.line_heads.len;
    if (line_count == 0) {
        return error.NoLine;
    } else if (line_index < line_count - 1) {
        return Line{
            .full = self.text,
            .begin = self.line_heads[line_index],
            .end = self.line_heads[line_index + 1] - 1,
        };
    } else if (line_index == line_count - 1) {
        // last line
        return Line{
            .full = self.text,
            .begin = self.line_heads[line_index],
            .end = @intCast(u32, self.text.len),
        };
    } else {
        return error.OverLine;
    }
}

pub const LineX = struct {
    line: u32,
    x: u32,
};

// TODO: mutibyte
pub fn getPositionFromBytePosition(self: Self, byte_position: usize, encoding: Line.Encoding) !LineX {
    const line = try self.getLineIndexFromBytePosition(byte_position);
    var i: u32 = self.line_heads[line];
    var x: u32 = 0;
    while (i < byte_position) {
        const len: u32 = try std.unicode.utf8ByteSequenceLength(self.text[i]);
        i += len;
        x += switch (encoding) {
            .utf8 => len,
            .utf16 => 1,
        };
    }
    return LineX{ .line = @intCast(u32, line), .x = x };
}

pub fn utf8PositionToUtf16(self: Self, src: LineX) !LineX {
    const begin = self.line_heads.items[src.line];
    var i: u32 = begin;
    var x: u32 = 0;
    var n: u32 = 0;
    while (x < src.x) {
        const len: u32 = try std.unicode.utf8ByteSequenceLength(self.text[i]);
        i += len;
        x += len;
        n += 1;
    }
    return LineX{ .line = src.line, .x = n };
}

test "LinePosition" {
    const text =
        \\0
        \\1
        \\2
        \\345
    ;
    const ls = try Self.init(std.testing.allocator, text);
    defer ls.deinit();
    try std.testing.expect((try ls.getLineIndexFromBytePosition(0)) == @as(usize, 0));
    try std.testing.expect((try ls.getLineIndexFromBytePosition(2)) == @as(usize, 1));
    try std.testing.expect((try ls.getLineIndexFromBytePosition(6)) == @as(usize, 3));
    try std.testing.expectEqual((try ls.getPositionFromBytePosition(0, .utf8)), .{ .line = 0, .x = 0 });
    try std.testing.expectEqual((try ls.getPositionFromBytePosition(7, .utf8)), .{ .line = 3, .x = 1 });
}

test "multibyte" {
    const text =
        \\あ
        \\い
        \\うえお
        \\漢字
        \\0123
    ;
    const ls = try Self.init(std.testing.allocator, text);
    defer ls.deinit();
    // std.debug.print("\n", .{});
    // あ
    try std.testing.expect((try ls.getLineIndexFromBytePosition(4)) == @as(usize, 1));
    try std.testing.expect((try ls.getLineIndexFromBytePosition(8)) == @as(usize, 2));
    try std.testing.expect((try ls.getLineIndexFromBytePosition(18)) == @as(usize, 3));
}
