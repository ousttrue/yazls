const std = @import("std");

pub const SemanticTokenType = enum(u32) {
    namespace,
    type,
    class,
    @"enum",
    interface,
    @"struct",
    typeParameter,
    parameter,
    variable,
    property,
    enumMember,
    event,
    function,
    method,
    macro,
    keyword,
    modifier,
    comment,
    string,
    number,
    regexp,
    operator,
    decorator,
};

pub const SemanticTokenModifiers = packed struct {
    const Self = @This();

    declaration: bool = false,
    definition: bool = false,
    readonly: bool = false,
    static: bool = false,
    deprecated: bool = false,
    abstract: bool = false,
    @"async": bool = false,
    modification: bool = false,
    documentation: bool = false,
    defaultLibrary: bool = false,

    pub fn toInt(self: Self) u32 {
        var res: u32 = 0;
        inline for (std.meta.fields(Self)) |field, i| {
            if (@field(self, field.name)) {
                res |= 1 << i;
            }
        }
        return res;
    }

    pub inline fn set(self: *Self, comptime field: []const u8) void {
        @field(self, field) = true;
    }
};
