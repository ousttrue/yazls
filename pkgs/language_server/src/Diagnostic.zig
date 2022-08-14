const std = @import("std");
const lsp = @import("language_server_protocol");
const astutil = @import("astutil");
const Document = astutil.Document;
const Line = astutil.Line;
const AstToken = astutil.AstToken;
const json_util = @import("./json_util.zig");
const logger = std.log.scoped(.Diagnostic);

fn getRange(doc: *Document, loc: std.zig.Token.Loc, encoding: Line.Encoding) !lsp.types.Range {
    var start_loc = try doc.utf8_buffer.getPositionFromBytePosition(loc.start, encoding);
    var end_loc = try doc.utf8_buffer.getPositionFromBytePosition(loc.end, encoding);
    var range = lsp.types.Range{
        .start = .{
            .line = @intCast(i64, start_loc.line),
            .character = @intCast(i64, start_loc.x),
        },
        .end = .{
            .line = @intCast(i64, end_loc.line),
            .character = @intCast(i64, end_loc.x),
        },
    };
    return range;
}

pub fn getDiagnostics(arena: *std.heap.ArenaAllocator, doc: *Document, encoding: Line.Encoding) ![]lsp.diagnostic.Diagnostic {
    const tree = &doc.ast_context.tree;
    var diagnostics = std.ArrayList(lsp.diagnostic.Diagnostic).init(arena.allocator());
    for (tree.errors) |err| {
        var message = std.ArrayList(u8).init(arena.allocator());
        try tree.renderError(err, message.writer());
        try diagnostics.append(.{
            .range = try getRange(doc, AstToken.init(tree, err.token).getLoc(), encoding),
            .severity = .Error,
            .code = @tagName(err.tag),
            .source = "zls",
            .message = message.items,
            // .relatedInformation = undefined
        });
    }
    return diagnostics.toOwnedSlice();
}

fn publishDiagnostics(allocator: std.mem.Allocator, uri: []const u8, diagnostics: []lsp.diagnostic.Diagnostic) ![]const u8 {
    logger.info("publishDiagnostics: {}", .{diagnostics.len});
    json_util.allocToNotification(allocator, "textDocument/publishDiagnostics", lsp.diagnostic.PublishDiagnosticsParams{
        .uri = uri,
        .diagnostics = diagnostics,
    });
}
