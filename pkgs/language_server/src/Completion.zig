const std = @import("std");
const astutil = @import("astutil");
const lsp = @import("language_server_protocol");
const Project = astutil.Project;
const ImportSolver = astutil.ImportSolver;
const Document = astutil.Document;
const Line = astutil.Line;
const AstToken = astutil.AstToken;
const AstNode = astutil.AstNode;
const AstContainer = astutil.AstContainer;
// const builtin_completions = @import("./builtin_completions.zig");
const logger = std.log.scoped(.Completion);

pub fn completeContainerMember(
    arena: *std.heap.ArenaAllocator,
    project: Project,
    doc: *Document,
    period: AstToken,
) ![]const lsp.completion.CompletionItem {
    var token = period;
    if (period.getTag() == .period) {
        if (period.getPrev()) |prev| {
            token = prev;
        }
    }

    // token.debugPrint();
    const node = AstNode.fromTokenIndex(doc.ast_context, token.index);
    // node.debugPrint();
    const type_node = try project.resolveType(node);
    // type_node.debugPrint();

    var items = std.ArrayList(lsp.completion.CompletionItem).init(arena.allocator());
    var buf: [2]u32 = undefined;

    if (AstContainer.init(type_node)) |container| {
        var it = container.iterator(&buf);
        while (it.next()) |member| {
            if (member.name_token) |name_token| {
                const name = name_token.getText();
                if (name[0] == '_') {
                    continue;
                }

                try items.append(.{
                    .label = name,
                    .kind = switch (member.kind) {
                        .field => .Property,
                        .var_decl => .Value,
                        .fn_proto, .fn_decl => .Method,
                        .test_decl => .Unit,
                    },
                });
            } else {}
        }
    }

    return items.toOwnedSlice();
}

fn tokenToLspRange(doc: *Document, loc: std.zig.Token.Loc, encoding: Line.Encoding) !lsp.types.Range {
    const start = try doc.utf8_buffer.getPositionFromBytePosition(loc.start, encoding);
    const end = try doc.utf8_buffer.getPositionFromBytePosition(loc.end, encoding);
    return lsp.types.Range{
        .start = .{
            .line = start.line,
            .character = start.x,
        },
        .end = .{
            .line = end.line,
            .character = end.x,
        },
    };
}

fn completeImport(
    arena: *std.heap.ArenaAllocator,
    import_solver: ImportSolver,
    doc: *Document,
    token: AstToken,
    encoding: Line.Encoding,
) ![]lsp.completion.CompletionItem {
    var items = std.ArrayList(lsp.completion.CompletionItem).init(arena.allocator());
    const loc = token.getLoc();
    const text = token.getText();
    var range = try tokenToLspRange(doc, .{ .start = loc.start + 1, .end = loc.end - 1 }, encoding);
    _ = range;

    try items.append(.{
        .label = "std",
        .kind = .Text,
    });
    try items.append(.{
        .label = "builtin",
        .kind = .Text,
    });

    {
        // pckages
        var it = import_solver.pkg_path_map.keyIterator();
        while (it.next()) |key| {
            const copy = try std.fmt.allocPrint(arena.allocator(), "{s}", .{key.*});
            // logger.debug("pkg: {s} => {s}", .{ token.getText(), copy });
            try items.append(.{
                .label = copy,
                .kind = .Module,
                // .textEdit = .{
                //     .range = range,
                //     .newText = copy,
                // },
                // .filterText=,
                // .insertText = try std.fmt.allocPrint(arena.allocator(), "\"{s}\"", .{key.*}),
                // .insertTextFormat=,
                // .detail=,
                // .documentation=,
            });
        }
    }

    if (std.mem.startsWith(u8, text, "\"./")) {
        // current path
        const dir = doc.path.parent().?;
        var it = try dir.iterateChildren();
        defer it.deinit();
        while (try it.next()) |entry| {
            switch (entry.kind) {
                .File => {
                    if (std.mem.endsWith(u8, entry.name, ".zig")) {
                        const copy = try std.fmt.allocPrint(arena.allocator(), "{s}", .{entry.name});
                        // logger.debug("path: {s} => {s}", .{ token.getText(), copy });
                        try items.append(.{
                            .label = copy,
                            .kind = .File,
                            // .textEdit = .{
                            //     .range = range,
                            //     .newText = copy,
                            // },
                            // .filterText=,
                            // .insertText = copy[partial.len..], //
                            // .insertTextFormat=,
                            // .detail=,
                            // .documentation=,
                        });
                    }
                },
                else => {},
            }
        }
    }

    return items.toOwnedSlice();
}

pub fn getCompletion(
    arena: *std.heap.ArenaAllocator,
    project: Project,
    doc: *Document,
    trigger_character: ?[]const u8,
    byte_position: u32,
    encoding: Line.Encoding,
) ![]const lsp.completion.CompletionItem {
    // TODO:
    // * trigger
    // * not trigger input head(no token under cursor)
    // * not trigger input not head(token under cursor)

    // get token for completion context
    //
    // std.
    //     ^ cursor is here. no token. get previous token
    const token_with_index = doc.ast_context.prevTokenFromBytePos(byte_position) orelse {
        // token not found. return no hover.
        return error.NoTokenUnderCursor;
    };
    const token = AstToken.init(&doc.ast_context.tree, token_with_index.index);

    if (trigger_character) |trigger| {
        if (std.mem.eql(u8, trigger, ".")) {
            logger.debug("trigger '.' => field_access", .{});
            return try completeContainerMember(arena, project, doc, token);
        }
        // else if (std.mem.eql(u8, trigger, "@")) {
        //     // logger.debug("trigger '@' => builtin", .{});
        //     return builtin_completions.completeBuiltin();
        // }
        else {
            logger.debug("trigger '{s}'", .{trigger});
            return &[_]lsp.completion.CompletionItem{};
        }
    } else {
        switch (token.getTag()) {
            .period => {
                if (token.getPrev()) |prev| {
                    return try completeContainerMember(arena, project, doc, prev);
                }
            },
            .string_literal => {
                const prev = token.getPrev().?; // lparen
                const prev_prev = prev.getPrev().?; //
                if (std.mem.eql(u8, prev_prev.getText(), "@import")) {
                    return try completeImport(arena, project.import_solver, doc, token, encoding);
                }
                // return try completeGlobal(arena, workspace, token.getStart(), doc, config, doc_kind);
            },
            else => {
                // const node = AstNode.fromTokenIndex(doc.ast_context, token.index);
                // return try completeGlobal(arena, workspace, token.getStart(), doc, config, doc_kind);
            },
        }
    }
    return &[_]lsp.completion.CompletionItem{};
}
