const std = @import("std");

pub const LiteralType = enum {
    const Self = @This();

    @"null",
    @"undefined",
    @"true",
    @"false",

    pub fn fromName(symbol: []const u8) ?Self {
        const info = @typeInfo(Self);
        inline for (info.Enum.fields) |field| {
            if (std.mem.eql(u8, field.name, symbol)) {
                return @intToEnum(Self, field.value);
            }
        }
        return null;
    }
};
