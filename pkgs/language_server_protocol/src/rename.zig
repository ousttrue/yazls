const types = @import("./types.zig");

// request
pub const RenameParams = struct {
    textDocument: types.TextDocumentIdentifier,
    position: types.Position,
    newName: []const u8,
};
