//! A LanguageServer frontend, registered to a JsonRPC dispatcher.
const root = @import("root");
const std = @import("std");
const lsp = @import("language_server_protocol");
const astutil = @import("astutil");
const FixedPath = astutil.FixedPath;
const Line = astutil.Line;
const ImportSolver = astutil.ImportSolver;
const DocumentStore = astutil.DocumentStore;
const Project = astutil.Project;
const Document = astutil.Document;
const AstToken = astutil.AstToken;
const AstNode = astutil.AstNode;
const TypeResolver = astutil.TypeResolver;
const LiteralType = astutil.literals.LiteralType;
const Workspace = @import("./Workspace.zig");
const ZigEnv = @import("./ZigEnv.zig");
const Diagnostic = @import("./Diagnostic.zig");
const semantic_tokens = @import("./semantic_tokens.zig");
const SemanticTokensBuilder = @import("./SemanticTokensBuilder.zig");
const document_symbol = @import("./document_symbol.zig");
const Goto = @import("./Goto.zig");
const Completion = @import("./Completion.zig");
const Signature = @import("./Signature.zig");
const hover = @import("./hover.zig");

const rename = @import("./rename.zig");
const json_util = @import("./json_util.zig");
const logger = std.log.scoped(.LanguageServer);

const EnqueueNotificationProto = fn (ptr: *anyopaque, []const u8) void;
pub const EnqueueNotificationFunctor = struct {
    ptr: *anyopaque,
    proto: EnqueueNotificationProto,
    pub fn call(self: @This(), notification: []const u8) void {
        self.proto(self.ptr, notification);
    }
};

const Self = @This();

allocator: std.mem.Allocator,
zigenv: ZigEnv,

workspaces: std.ArrayList(Workspace),

// client_capabilities: ClientCapabilities = .{},
encoding: Line.Encoding = .utf16,
server_capabilities: lsp.initialize.ServerCapabilities = .{},
enqueue_notification: EnqueueNotificationFunctor,

pub fn init(allocator: std.mem.Allocator, zigenv: ZigEnv, enqueue_notification: EnqueueNotificationFunctor) Self {
    var self = Self{
        .allocator = allocator,
        .zigenv = zigenv,
        .workspaces = std.ArrayList(Workspace).init(allocator),
        .enqueue_notification = enqueue_notification,
    };
    return self;
}

pub fn deinit(self: *Self) void {
    for (self.workspaces.items) |*workspace| {
        workspace.deinit();
    }
    self.workspaces.deinit();
}

pub fn workspaceFromUri(self: *Self, uri: []const u8) !*Workspace {
    const path = try FixedPath.fromUri(uri);
    for (self.workspaces.items) |*workspace| {
        if (workspace.path.contains(path)) {
            return workspace;
        }
    }

    // fallback(std etc...)
    return &self.workspaces.items[0];
}

/// # base protocol
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#cancelRequest
pub fn @"$/cancelRequest"(self: *Self, arena: *std.heap.ArenaAllocator, jsonParams: ?std.json.Value) !void {
    _ = self;
    _ = arena;
    _ = jsonParams;
}

/// # lifecycle
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize
pub fn initialize(self: *Self, arena: *std.heap.ArenaAllocator, id: i64, jsonParams: ?std.json.Value) ![]const u8 {
    // json_util.logJson(arena.allocator(), jsonParams);

    const params = try lsp.fromDynamicTree(arena, lsp.initialize.InitializeParams, jsonParams.?);
    for (params.capabilities.offsetEncoding.value) |encoding| {
        if (std.mem.eql(u8, encoding, "utf-8")) {
            self.encoding = .utf8;
        }
    }

    // semantic token
    if (self.server_capabilities.semanticTokensProvider) |*semantic_tokens_provider| {
        semantic_tokens_provider.legend.tokenTypes = block: {
            const tokTypeFields = std.meta.fields(semantic_tokens.SemanticTokenType);
            var names: [tokTypeFields.len][]const u8 = undefined;
            inline for (tokTypeFields) |field, i| {
                names[i] = field.name;
            }
            break :block &names;
        };
        semantic_tokens_provider.legend.tokenModifiers = block: {
            const tokModFields = std.meta.fields(semantic_tokens.SemanticTokenModifiers);
            var names: [tokModFields.len][]const u8 = undefined;
            inline for (tokModFields) |field, i| {
                names[i] = field.name;
            }
            break :block &names;
        };
    }

    // if (params.capabilities.textDocument) |textDocument| {
    //     self.client_capabilities.supports_semantic_tokens = textDocument.semanticTokens.exists;
    //     if (textDocument.hover) |hover| {
    //         for (hover.contentFormat.value) |format| {
    //             if (std.mem.eql(u8, "markdown", format)) {
    //                 self.client_capabilities.hover_supports_md = true;
    //             }
    //         }
    //     }
    //     if (textDocument.completion) |completion| {
    //         if (completion.completionItem) |completionItem| {
    //             self.client_capabilities.supports_snippets = completionItem.snippetSupport.value;
    //             for (completionItem.documentationFormat.value) |documentationFormat| {
    //                 if (std.mem.eql(u8, "markdown", documentationFormat)) {
    //                     self.client_capabilities.completion_doc_supports_md = true;
    //                 }
    //             }
    //         }
    //     }
    // }

    if (params.workspaceFolders) |folders| {
        for (folders) |folder, i| {
            logger.debug("[{}] {s}", .{ i, folder.uri });
            if (Workspace.fromUri(self.allocator, folder.uri, self.zigenv)) |workspace| {
                try self.workspaces.append(workspace);
            } else |err| {
                logger.info("{}: {s}", .{ err, folder.uri });
            }
        }
    }
    if (self.workspaces.items.len == 0) {
        const path = if (params.rootUri) |uri|
            try FixedPath.fromUri(uri)
        else if (params.rootPath) |path|
            FixedPath.fromFullpath(path)
        else
            return error.NoWorkspaceRoot;
        const workspace = try Workspace.init(self.allocator, path, self.zigenv);
        try self.workspaces.append(workspace);
    }

    return json_util.allocToResponse(arena.allocator(), id, lsp.initialize.InitializeResult{
        .offsetEncoding = self.encoding.toString(),
        .serverInfo = .{
            .name = "zls",
            .version = "0.1.0",
        },
        .capabilities = self.server_capabilities,
    });
}

/// # lifecycle
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized
pub fn initialized(self: *Self, arena: *std.heap.ArenaAllocator, jsonParams: ?std.json.Value) !void {
    _ = self;
    _ = arena;
    _ = jsonParams;
}

/// # lifecycle
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#shutdown
pub fn shutdown(self: *Self, arena: *std.heap.ArenaAllocator, id: i64, jsonParams: ?std.json.Value) ![]const u8 {
    _ = self;
    _ = jsonParams;
    root.keep_running = false;
    return json_util.allocToResponse(arena.allocator(), id, null);
}

/// # document sync
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didOpen
pub fn @"textDocument/didOpen"(self: *Self, arena: *std.heap.ArenaAllocator, jsonParams: ?std.json.Value) !void {
    const params = try lsp.fromDynamicTree(arena, lsp.document_sync.OpenDocument, jsonParams.?);
    const path = try FixedPath.fromUri(params.textDocument.uri);
    const workspace = try self.workspaceFromUri(params.textDocument.uri);
    const text = params.textDocument.text;
    const doc = try workspace.store.update(path, text);

    const diagnostics = try Diagnostic.getDiagnostics(arena, doc, self.encoding);
    const notification = try Diagnostic.publishDiagnostics(arena.allocator(), params.textDocument.uri, diagnostics);
    self.enqueue_notification.call(notification);
}

/// # document sync
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didChange
pub fn @"textDocument/didChange"(self: *Self, arena: *std.heap.ArenaAllocator, jsonParams: ?std.json.Value) !void {
    const params = try lsp.fromDynamicTree(arena, lsp.document_sync.ChangeDocument, jsonParams.?);
    const workspace = try self.workspaceFromUri(params.textDocument.uri);
    const doc = workspace.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;
    try doc.applyChanges(params.contentChanges.Array, self.encoding);

    const diagnostics = try Diagnostic.getDiagnostics(arena, doc, self.encoding);
    const notification = try Diagnostic.publishDiagnostics(arena.allocator(), params.textDocument.uri, diagnostics);
    self.enqueue_notification.call(notification);
}

/// # document sync
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didSave
pub fn @"textDocument/didSave"(self: *Self, arena: *std.heap.ArenaAllocator, jsonParams: ?std.json.Value) !void {
    const params = try lsp.fromDynamicTree(arena, lsp.document_sync.SaveDocument, jsonParams.?);
    const workspace = try self.workspaceFromUri(params.textDocument.uri);
    const doc = workspace.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;
    _ = doc;
    // try doc.applySave(self.zigenv);
}

/// # document sync
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didClose
pub fn @"textDocument/didClose"(self: *Self, arena: *std.heap.ArenaAllocator, jsonParams: ?std.json.Value) !void {
    const params = try lsp.fromDynamicTree(arena, lsp.document_sync.CloseDocument, jsonParams.?);
    const workspace = try self.workspaceFromUri(params.textDocument.uri);
    const doc = workspace.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;
    _ = doc;
}

/// # language feature
/// ## document request
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_formatting
pub fn @"textDocument/formatting"(self: *Self, arena: *std.heap.ArenaAllocator, id: i64, jsonParams: ?std.json.Value) ![]const u8 {
    const params = try lsp.fromDynamicTree(arena, lsp.types.TextDocumentIdentifierRequest, jsonParams.?);
    const workspace = try self.workspaceFromUri(params.textDocument.uri);
    const doc = workspace.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;

    const stdout_bytes = try self.zigenv.spawnZigFmt(arena.allocator(), doc.utf8_buffer.text);
    const end = doc.utf8_buffer.text.len;
    const position = try doc.utf8_buffer.getPositionFromBytePosition(end, self.encoding);
    const range = lsp.types.Range{
        .start = .{
            .line = 0,
            .character = 0,
        },
        .end = .{
            .line = position.line,
            .character = position.x,
        },
    };

    var edits = try arena.allocator().alloc(lsp.types.TextEdit, 1);
    edits[0] = .{
        .range = range,
        .newText = stdout_bytes,
    };

    return json_util.allocToResponse(arena.allocator(), id, edits);
}

/// # language feature
/// ## document request
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_documentSymbol
pub fn @"textDocument/documentSymbol"(
    self: *Self,
    arena: *std.heap.ArenaAllocator,
    id: i64,
    jsonParams: ?std.json.Value,
) ![]const u8 {
    const params = try lsp.fromDynamicTree(arena, lsp.types.TextDocumentIdentifierRequest, jsonParams.?);
    const path = try FixedPath.fromUri(params.textDocument.uri);
    const workspace = try self.workspaceFromUri(params.textDocument.uri);
    const doc = workspace.store.get(path) orelse {
        logger.err("not found: {s}", .{path.slice()});
        return error.DocumentNotFound;
    };
    const symbols = try document_symbol.to_symbols(arena, doc, self.encoding);
    return json_util.allocToResponse(arena.allocator(), id, symbols);
}

/// # language feature
/// ## document request
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens
pub fn @"textDocument/semanticTokens/full"(self: *Self, arena: *std.heap.ArenaAllocator, id: i64, jsonParams: ?std.json.Value) ![]const u8 {
    const params = try lsp.fromDynamicTree(arena, lsp.types.TextDocumentIdentifierRequest, jsonParams.?);
    const workspace = try self.workspaceFromUri(params.textDocument.uri);
    const doc = workspace.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;

    var token_array = try SemanticTokensBuilder.writeAllSemanticTokens(arena, doc);
    var array = try std.ArrayList(u32).initCapacity(arena.allocator(), token_array.len * 5);
    for (token_array) |token| {
        const start = try doc.utf8_buffer.getPositionFromBytePosition(token.start, self.encoding);

        var p = token.start;
        var i: u32 = 0;
        while (p < token.end) {
            const len = try std.unicode.utf8ByteSequenceLength(doc.utf8_buffer.text[p]);
            p += len;
            i += 1;
        }

        try array.appendSlice(&.{
            start.line,
            start.x,
            @intCast(u32, if (self.encoding == .utf8) token.end - token.start else i),
            @enumToInt(token.token_type),
            token.token_modifiers.toInt(),
        });
    }
    // convert to delta
    var data = array.items;
    {
        var prev_line: u32 = 0;
        var prev_character: u32 = 0;
        var i: u32 = 0;
        while (i < data.len) : (i += 5) {
            const current_line = data[i];
            const current_character = data[i + 1];

            data[i] = current_line - prev_line;
            data[i + 1] = current_character - if (current_line == prev_line) prev_character else 0;

            prev_line = current_line;
            prev_character = current_character;
        }
    }
    // logger.debug("semantic tokens: {}", .{data.len});
    // SemanticTokensFull: struct { data: []const u32 }
    return json_util.allocToResponse(arena.allocator(), id, .{ .data = data });
}

// // /// # language feature
// // /// ## document request
// // /// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_signatureHelp
// // pub fn @"textDocument/codeLens"(self: *Self, arena: *std.heap.ArenaAllocator, id: i64, jsonParams: ?std.json.Value) !lsp.Response {
// //     var workspace = self.workspace orelse return error.WorkspaceNotInitialized;
// //     const params = try lsp.fromDynamicTree(arena, lsp.requests.TextDocumentIdentifierRequest, jsonParams.?);
// //     const doc = self.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;

// //     // const tree = doc.ast_context.tree;
// //     var data = std.ArrayList(lsp.types.CodeLens).init(arena.allocator());
// //     const tag = doc.ast_context.tree.nodes.items(.tag);
// //     // var i: u32 = 0;
// //     var buffer: [2]u32 = undefined;
// //     const allocator = arena.allocator();
// //     // while (i < tree.nodes.len) : (i += 1) {
// //     for (tag) |_, i| {
// //         const children = AstNodeIterator.NodeChildren.init(doc.ast_context.tree, @intCast(u32, i), &buffer);
// //         switch (children) {
// //             .fn_proto => |fn_proto| {
// //                 const token_idx = fn_proto.ast.fn_token;
// //                 const token = AstToken.init(&doc.ast_context.tree, token_idx);
// //                 const n = if (try textdocument_position.getRenferences(arena, workspace, doc, token, true)) |refs| refs.len else 0;
// //                 const loc = token.getLoc();
// //                 const start = try doc.utf8_buffer.getPositionFromBytePosition(loc.start, self.encoding);
// //                 const end = try doc.utf8_buffer.getPositionFromBytePosition(loc.end, self.encoding);
// //                 const text = try std.fmt.allocPrint(allocator, "references {}", .{n});
// //                 _ = text;
// //                 // const arg = try std.fmt.allocPrint(allocator, "{}", .{token_idx});
// //                 // logger.debug("{s}", .{text});
// //                 try data.append(.{
// //                     .range = .{
// //                         .start = .{
// //                             .line = start.line,
// //                             .character = 0,
// //                         },
// //                         .end = .{
// //                             .line = end.line,
// //                             .character = 1,
// //                         },
// //                     },
// //                     .command = .{
// //                         .title = text,
// //                         .command = "zls.refrences",
// //                     },
// //                 });
// //             },
// //             else => {},
// //         }
// //     }

// //     return lsp.Response{
// //         .id = id,
// //         .result = .{ .CodeLens = data.items },
// //     };
// // }

// // pub fn @"codeLens/resolve"(self: *Self, arena: *std.heap.ArenaAllocator, id: i64, jsonParams: ?std.json.Value) !lsp.Response {
// //     var workspace = self.workspace orelse return error.WorkspaceNotInitialized;
// //     _ = workspace;
// //     logJson(arena, jsonParams);
// //     // const params = try lsp.fromDynamicTree(arena, lsp.requests.TextDocumentIdentifierRequest, jsonParams.?);
// //     // const doc = self.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;
// //     return lsp.Response.createNull(id);
// // }

/// # language feature
/// ## document position request
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_hover
pub fn @"textDocument/hover"(
    self: *Self,
    arena: *std.heap.ArenaAllocator,
    id: i64,
    jsonParams: ?std.json.Value,
) ![]const u8 {
    const params = try lsp.fromDynamicTree(arena, lsp.types.TextDocumentIdentifierPositionRequest, jsonParams.?);
    const workspace = try self.workspaceFromUri(params.textDocument.uri);
    const doc = workspace.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;
    const position = params.position;
    const line = try doc.utf8_buffer.getLine(@intCast(u32, position.line));
    const byte_position = try line.getBytePosition(@intCast(u32, position.character), self.encoding);
    const token = AstToken.fromBytePosition(&doc.ast_context.tree, byte_position) orelse {
        // no token under cursor
        return json_util.allocToResponse(arena.allocator(), id, null);
    };
    if (token.getTag() != .identifier) {
        // skip token that is not identifier
        return json_util.allocToResponse(arena.allocator(), id, null);
    }
    if (LiteralType.fromName(token.getText())) |_| {
        // skip literal. null, true, false, undefined...
        return json_util.allocToResponse(arena.allocator(), id, null);
    }

    const node = AstNode.fromTokenIndex(doc.ast_context, token.index);
    var resolver = TypeResolver.init(arena.allocator());
    defer resolver.deinit();
    const resolved = try resolver.resolve(workspace.project(), node, token);
    const text = try hover.getHover(arena.allocator(), token, node, resolved);

    var range: ?lsp.types.Range = null;
    // if (hover.loc) |loc| {
    //     const start = try doc.utf8_buffer.getPositionFromBytePosition(loc.start, self.encoding);
    //     const end = try doc.utf8_buffer.getPositionFromBytePosition(loc.end, self.encoding);
    //     range = lsp.types.Range{
    //         .start = .{
    //             .line = start.line,
    //             .character = start.x,
    //         },
    //         .end = .{
    //             .line = end.line,
    //             .character = end.x,
    //         },
    //     };
    // }

    return json_util.allocToResponse(arena.allocator(), id, lsp.types.Hover{
        .contents = .{ .value = text },
        .range = range,
    });
}

/// # language feature
/// ## document position request
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_definition
pub fn @"textDocument/definition"(
    self: *Self,
    arena: *std.heap.ArenaAllocator,
    id: i64,
    jsonParams: ?std.json.Value,
) ![]const u8 {
    const params = try lsp.fromDynamicTree(arena, lsp.types.TextDocumentIdentifierPositionRequest, jsonParams.?);
    const workspace = try self.workspaceFromUri(params.textDocument.uri);
    const doc = workspace.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;
    const position = params.position;
    const line = try doc.utf8_buffer.getLine(@intCast(u32, position.line));
    const byte_position = try line.getBytePosition(@intCast(u32, position.character), self.encoding);
    const token = AstToken.fromBytePosition(&doc.ast_context.tree, byte_position) orelse {
        return json_util.allocToResponse(arena.allocator(), id, null);
    };

    // get location
    const location = (try Goto.getGoto(arena, workspace.project(), doc, token)) orelse {
        return json_util.allocToResponse(arena.allocator(), id, null);
    };

    // location to lsp
    const goto_doc = (try workspace.store.getOrLoad(location.path)) orelse {
        logger.warn("fail to load: {s}", .{location.path.slice()});
        return error.DocumentNotFound;
    };
    const goto = try goto_doc.utf8_buffer.getPositionFromBytePosition(location.loc.start, self.encoding);
    const goto_pos = lsp.types.Position{ .line = goto.line, .character = goto.x };

    const uri = try location.path.allocToUri(arena.allocator());
    return json_util.allocToResponse(arena.allocator(), id, lsp.types.Location{
        .uri = uri,
        .range = .{
            .start = goto_pos,
            .end = goto_pos,
        },
    });
}

/// # language feature
/// ## document position request
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_completion
pub fn @"textDocument/completion"(
    self: *Self,
    arena: *std.heap.ArenaAllocator,
    id: i64,
    jsonParams: ?std.json.Value,
) ![]const u8 {
    // var tmp = std.ArrayList(u8).init(arena.allocator());
    // try jsonParams.?.jsonStringify(.{}, tmp.writer());
    // logger.debug("{s}", .{tmp.items});

    const params = try lsp.fromDynamicTree(arena, lsp.completion.CompletionParams, jsonParams.?);
    const workspace = try self.workspaceFromUri(params.textDocument.uri);
    const doc = workspace.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;
    const position = params.position;
    const line = try doc.utf8_buffer.getLine(@intCast(u32, position.line));
    const byte_position = try line.getBytePosition(@intCast(u32, position.character), self.encoding);

    const completions = try Completion.getCompletion(
        arena,
        workspace.project(),
        doc,
        params.context.triggerCharacter,
        byte_position,
        self.encoding,
    );

    return json_util.allocToResponse(arena.allocator(), id, completions);
}

/// # language feature
/// ## document position request
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_rename
pub fn @"textDocument/rename"(self: *Self, arena: *std.heap.ArenaAllocator, id: i64, jsonParams: ?std.json.Value) ![]const u8 {
    const params = try lsp.fromDynamicTree(arena, lsp.rename.RenameParams, jsonParams.?);
    const workspace = try self.workspaceFromUri(params.textDocument.uri);
    const doc = workspace.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;
    const position = params.position;
    const line = try doc.utf8_buffer.getLine(@intCast(u32, position.line));
    const byte_position = try line.getBytePosition(@intCast(u32, position.character), self.encoding);
    const token = AstToken.fromBytePosition(&doc.ast_context.tree, byte_position) orelse {
        // no token under cursor
        return json_util.allocToResponse(arena.allocator(), id, null);
    };
    if (token.getTag() != .identifier) {
        // skip token that is not identifier
        return json_util.allocToResponse(arena.allocator(), id, null);
    }
    if (LiteralType.fromName(token.getText())) |_| {
        // skip literal. null, true, false, undefined...
        return json_util.allocToResponse(arena.allocator(), id, null);
    }

    const workspaceEdit = try rename.getEdit(
        arena,
        workspace.project(),
        doc,
        token,
    );

    return json_util.allocToResponse(arena.allocator(), id, workspaceEdit);
}

// // /// # language feature
// // /// ## document position request
// // /// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_references
// // pub fn @"textDocument/references"(self: *Self, arena: *std.heap.ArenaAllocator, id: i64, jsonParams: ?std.json.Value) !lsp.Response {
// //     var workspace = self.workspace orelse return error.WorkspaceNotInitialized;
// //     const params = try lsp.fromDynamicTree(arena, lsp.requests.References, jsonParams.?);
// //     const doc = self.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;
// //     const position = params.position;
// //     const line = try doc.utf8_buffer.getLine(@intCast(u32, position.line));
// //     const byte_position = try line.getBytePosition(@intCast(u32, position.character), self.encoding);
// //     const token = AstToken.fromBytePosition(&doc.ast_context.tree, byte_position) orelse {
// //         return lsp.Response.createNull(id);
// //     };

// //     if (try textdocument_position.getRenferences(
// //         arena,
// //         workspace,
// //         doc,
// //         token,
// //         params.context.includeDeclaration,
// //     )) |src| {
// //         var locations = std.ArrayList(lsp.Location).init(arena.allocator());
// //         for (src) |location| {
// //             const uri = try URI.fromPath(arena.allocator(), location.path.slice());
// //             var start = try doc.utf8_buffer.getPositionFromBytePosition(location.loc.start, self.encoding);
// //             var end = try doc.utf8_buffer.getPositionFromBytePosition(location.loc.end, self.encoding);
// //             if (self.encoding == .utf16) {
// //                 start = try doc.utf8_buffer.utf8PositionToUtf16(start);
// //                 end = try doc.utf8_buffer.utf8PositionToUtf16(end);
// //             }
// //             try locations.append(.{
// //                 .uri = uri,
// //                 .range = .{
// //                     .start = .{ .line = start.line, .character = start.x },
// //                     .end = .{ .line = end.line, .character = end.x },
// //                 },
// //             });
// //         }

// //         return lsp.Response{
// //             .id = id,
// //             .result = .{ .Locations = locations.items },
// //         };
// //     } else {
// //         return lsp.Response.createNull(id);
// //     }
// // }

/// # language feature
/// ## document position request
/// * https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_signatureHelp
pub fn @"textDocument/signatureHelp"(
    self: *Self,
    arena: *std.heap.ArenaAllocator,
    id: i64,
    jsonParams: ?std.json.Value,
) ![]const u8 {
    const params = try lsp.fromDynamicTree(arena, lsp.signature_help.SignatureHelpParams, jsonParams.?);
    const workspace = try self.workspaceFromUri(params.textDocument.uri);
    const doc = workspace.store.get(try FixedPath.fromUri(params.textDocument.uri)) orelse return error.DocumentNotFound;
    const position = params.position;
    const line = try doc.utf8_buffer.getLine(@intCast(u32, position.line));
    const byte_position = try line.getBytePosition(@intCast(u32, position.character), self.encoding);
    const token = AstToken.fromBytePosition(&doc.ast_context.tree, byte_position) orelse {
        return json_util.allocToResponse(arena.allocator(), id, null);
    };

    const signature = (try Signature.getSignature(
        arena,
        workspace.project(),
        doc,
        token,
    )) orelse {
        logger.warn("no signature", .{});
        return json_util.allocToResponse(arena.allocator(), id, null);
    };

    var args = std.ArrayList(lsp.signature_help.ParameterInformation).init(arena.allocator());
    for (signature.params) |param| {
        try args.append(.{
            .label = param.getName(),
            .documentation = .{
                .kind = .Markdown,
                .value = param.type_node.getText(),
            },
        });
    }
    var signatures: [1]lsp.signature_help.SignatureInformation = .{
        .{
            .label = signature.getName(),
            .documentation = .{
                .kind = .Markdown,
                .value = "",
            },
            .parameters = args.items,
            .activeParameter = signature.active_param,
        },
    };

    return json_util.allocToResponse(arena.allocator(), id, .{ .signatures = signatures });
}
