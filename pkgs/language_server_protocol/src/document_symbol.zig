const std = @import("std");
const types = @import("./types.zig");
const Range = types.Range;
const string = []const u8;

pub const DocumentSymbol = struct {
    name: string,
    detail: ?string = null,
    kind: SymbolKind,
    deprecated: bool = false,
    range: Range,
    selectionRange: Range,
    children: []DocumentSymbol = &[_]DocumentSymbol{},
};

pub const SymbolKind = enum(u32) {
    File = 1,
    Module = 2,
    Namespace = 3,
    Package = 4,
    Class = 5,
    Method = 6,
    Property = 7,
    Field = 8,
    Constructor = 9,
    Enum = 10,
    Interface = 11,
    Function = 12,
    Variable = 13,
    Constant = 14,
    String = 15,
    Number = 16,
    Boolean = 17,
    Array = 18,
    Object = 19,
    Key = 20,
    Null = 21,
    EnumMember = 22,
    Struct = 23,
    Event = 24,
    Operator = 25,
    TypeParameter = 26,

    pub fn jsonStringify(value: SymbolKind, options: std.json.StringifyOptions, out_stream: anytype) !void {
        try std.json.stringify(@enumToInt(value), options, out_stream);
    }
};
