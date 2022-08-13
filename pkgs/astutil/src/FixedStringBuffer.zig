const std = @import("std");
const logger = std.log.scoped(.FixedPath);
const Self = @This();

_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined,
len: usize = 0,

pub fn slice(self: Self) []const u8 {
    return self._buffer[0..self.len];
}

pub fn assign(self: *Self, buf: []const u8) void {
    std.mem.copy(u8, &self._buffer, buf);
    self.len = buf.len;
    self._buffer[self.len] = 0;
}

pub fn pushChar(self: *Self, c: u8) void {
    self._buffer[self.len] = c;
    self.len += 1;
}
