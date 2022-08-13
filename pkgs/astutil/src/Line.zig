const std = @import("std");
pub const Encoding = enum {
    utf8,
    utf16,

    pub fn toString(self: Encoding) []const u8 {
        return if (self == .utf8)
            @as([]const u8, "utf-8")
        else
            "utf-16";
    }
};

const Self = @This();

full: []const u8,
begin: u32,
end: u32,

pub fn getBytePosition(self: Self, character: u32, encoding: Encoding) !u32 {
    if (encoding == .utf8) {
        return self.begin + character;
    }

    var i = self.begin;
    var x: u32 = 0;
    while (x < character) : (x += 1) {
        if (i >= self.end) {
            return error.EOL;
        }
        const len = try std.unicode.utf8ByteSequenceLength(self.full[i]);
        i += len;
    }
    return i;
}
