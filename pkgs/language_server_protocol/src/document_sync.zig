const std = @import("std");
const types = @import("./types.zig");

pub const OpenDocument = struct {
    textDocument: struct {
        uri: []const u8,
        text: []const u8,
    },
};

pub const ChangeDocument = struct {
    textDocument: types.TextDocumentIdentifier,
    contentChanges: std.json.Value,
};

pub const SaveDocument = types.TextDocumentIdentifierRequest;
pub const CloseDocument = types.TextDocumentIdentifierRequest;
