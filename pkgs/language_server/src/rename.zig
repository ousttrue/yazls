const std = @import("std");
const lsp = @import("language_server_protocol");
const astutil = @import("astutil");
const Project = astutil.Project;
const Document = astutil.Document;
const AstToken = astutil.AstToken;

pub fn getEdit(
    arena: *std.heap.ArenaAllocator,
    project: Project,
    doc: *Document,
    token: AstToken,
) !lsp.types.WorkspaceEdit {
    // {
    //    "uri": [changes]
    // }
    var changes = std.StringHashMap([]lsp.types.TextEdit).init(arena.allocator());
    _ = project;
    _ = doc;
    _ = token;
    // for (locations) |location| {
    //     const uri = try URI.fromPath(allocator, location.path.slice());
    //     // var text_edits = if (changes.get(uri)) |slice|
    //     //     std.ArrayList(lsp.TextEdit).fromOwnedSlice(allocator, slice)
    //     // else
    //     //     std.ArrayList(lsp.TextEdit).init(allocator);

    //     // var start = try doc.utf8_buffer.getPositionFromBytePosition(location.loc.start, self.encoding);
    //     // var end = try doc.utf8_buffer.getPositionFromBytePosition(location.loc.end, self.encoding);

    //     // (try text_edits.addOne()).* = .{
    //     //     .range = .{
    //     //         .start = .{ .line = start.line, .character = start.x },
    //     //         .end = .{ .line = end.line, .character = end.x },
    //     //     },
    //     //     .newText = params.newName,
    //     // };
    //     try changes.put(uri, text_edits.toOwnedSlice());
    return lsp.types.WorkspaceEdit{
        .changes = changes,
    };
}
