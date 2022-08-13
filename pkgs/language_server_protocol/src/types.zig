const std = @import("std");
pub const string = []const u8;

// LSP types
// https://microsoft.github.io/language-server-protocol/specifications/specification-3-16/

pub const Position = struct {
    line: i64,
    character: i64,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const Location = struct {
    uri: string,
    range: Range,
};

/// Hover response
pub const Hover = struct {
    contents: MarkupContent,
    range: ?Range,
};

pub const WorkspaceEdit = struct {
    changes: ?std.StringHashMap([]TextEdit),

    pub fn jsonStringify(self: WorkspaceEdit, options: std.json.StringifyOptions, writer: anytype) @TypeOf(writer).Error!void {
        try writer.writeByte('{');
        if (self.changes) |changes| {
            try writer.writeAll("\"changes\": {");
            var it = changes.iterator();
            var idx: usize = 0;
            while (it.next()) |entry| : (idx += 1) {
                if (idx != 0) try writer.writeAll(", ");

                try writer.writeByte('"');
                try writer.writeAll(entry.key_ptr.*);
                try writer.writeAll("\":");
                try std.json.stringify(entry.value_ptr.*, options, writer);
            }
            try writer.writeByte('}');
        }
        try writer.writeByte('}');
    }
};

pub const TextEdit = struct {
    range: Range,
    newText: string,
};

pub const MarkupContent = struct {
    pub const Kind = enum(u1) {
        PlainText = 0,
        Markdown = 1,

        pub fn jsonStringify(value: Kind, options: std.json.StringifyOptions, out_stream: anytype) !void {
            const str = switch (value) {
                .PlainText => "plaintext",
                .Markdown => "markdown",
            };
            try std.json.stringify(str, options, out_stream);
        }
    };

    kind: Kind = .Markdown,
    value: string,
};

pub const InsertTextFormat = enum(i64) {
    PlainText = 1,
    Snippet = 2,

    pub fn jsonStringify(value: InsertTextFormat, options: std.json.StringifyOptions, out_stream: anytype) !void {
        try std.json.stringify(@enumToInt(value), options, out_stream);
    }
};

/// Only check for the field's existence.
pub const Exists = struct {
    exists: bool,
};

pub fn Default(comptime T: type, comptime default_value: T) type {
    return struct {
        pub const value_type = T;
        pub const default = default_value;
        value: T,
    };
}

pub const MaybeStringArray = Default([]const []const u8, &.{});

pub const CodeLens = struct {
    range: Range,
    command: struct {
        title: string,
        command: string,
        arguments: ?[]string = null,
    },
};

pub const TextDocumentIdentifier = struct {
    uri: []const u8,
};
