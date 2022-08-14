const std = @import("std");
const lsp = @import("language_server_protocol");
const astutil = @import("astutil");
const Document = astutil.Document;
const Line = astutil.Line;
const AstToken = astutil.AstToken;
const json_util = @import("./json_util.zig");
const lsp_util = @import("./lsp_util.zig");
const logger = std.log.scoped(.Diagnostic);

pub fn getDiagnostics(arena: *std.heap.ArenaAllocator, doc: *Document, encoding: Line.Encoding) ![]lsp.diagnostic.Diagnostic {
    const tree = &doc.ast_context.tree;
    var diagnostics = std.ArrayList(lsp.diagnostic.Diagnostic).init(arena.allocator());
    for (tree.errors) |err| {
        var message = std.ArrayList(u8).init(arena.allocator());
        try tree.renderError(err, message.writer());
        try diagnostics.append(.{
            .range = try lsp_util.getRange(doc, AstToken.init(tree, err.token).getLoc(), encoding),
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
