const std = @import("std");
const lsp = @import("language_server_protocol");
const astutil = @import("astutil");
const Document = astutil.Document;
const Line = astutil.Line;
const AstNode = astutil.AstNode;
const AstContainer = astutil.AstContainer;
const lsp_util = @import("./lsp_util.zig");
const logger = std.log.scoped(.DocumentSymbol);

const SymbolTree = struct {
    const Self = @This();

    root: std.ArrayList(lsp.document_symbol.DocumentSymbol),
    imports: std.ArrayList(lsp.document_symbol.DocumentSymbol),

    fn init(allocator: std.mem.Allocator) Self {
        var self = Self{
            .root = std.ArrayList(lsp.document_symbol.DocumentSymbol).init(allocator),
            .imports = std.ArrayList(lsp.document_symbol.DocumentSymbol).init(allocator),
        };
        var range = lsp.types.Range{
            .start = .{
                .line = 0,
                .character = 0,
            },
            .end = .{
                .line = 0,
                .character = 0,
            },
        };
        self.root.append(.{
            .name = "imports",
            .kind = .Module,
            .range = range,
            .selectionRange = range,
            .detail = "",
        }) catch unreachable;
        return self;
    }

    fn toOwnedSlice(self: *Self) []lsp.document_symbol.DocumentSymbol {
        self.root.items[0].children = self.imports.items;
        return self.root.toOwnedSlice();
    }

    fn process(
        self: *Self,
        arena: *std.heap.ArenaAllocator,
        doc: *Document,
        encoding: Line.Encoding,
    ) !void {
        try self.traverse(&self.root, arena, doc, AstNode.init(doc.ast_context, 0), encoding);
    }

    fn traverse(
        self: *Self,
        current: *std.ArrayList(lsp.document_symbol.DocumentSymbol),
        arena: *std.heap.ArenaAllocator,
        doc: *Document,
        container_node: AstNode,
        encoding: Line.Encoding,
    ) anyerror!void {
        var buf2: [2]u32 = undefined;
        var it = AstContainer.init(container_node).iterator(&buf2);
        while (it.next()) |member| {
            // member_node: var_decl / container_field / fn_decl / test_decl
            if (member.name_token) |name_token| {
                // member_node: var_decl / container_field / fn_decl
                const range = try lsp_util.getRange(doc, name_token.getLoc(), encoding);
                var item = lsp.document_symbol.DocumentSymbol{
                    .name = name_token.getText(),
                    .kind = getItemTag(member.node),
                    .range = range,
                    .selectionRange = range,
                };
                var is_import = false;
                if (member.node.getTypeNode()) |type_node| {
                    var buf: [2]u32 = undefined;
                    switch (type_node.getChildren(&buf)) {
                        .builtin_call => {
                            if (std.mem.eql(u8, type_node.getMainToken().getText(), "@import")) {
                                is_import = true;
                                item.kind = .File;
                            }
                        },
                        .container_decl => {
                            if (std.mem.eql(u8, type_node.getMainToken().getText(), "enum")) {
                                item.kind = .Enum;
                            }
                            var children = std.ArrayList(lsp.document_symbol.DocumentSymbol).init(arena.allocator());
                            try self.traverse(&children, arena, doc, type_node, encoding);
                            item.children = children.toOwnedSlice();
                        },
                        else => {},
                    }
                } else {
                    if (item.kind != .Method) {
                        item.kind = .EnumMember;
                    }
                }

                if (is_import) {
                    try self.imports.append(item);
                } else {
                    try current.append(item);
                }
            }
        }
    }
};

fn getItemTag(node: AstNode) lsp.document_symbol.SymbolKind {
    var buf: [2]u32 = undefined;
    return switch (node.getChildren(&buf)) {
        .var_decl => .Variable,
        .container_field => .Property,
        else => .Method,
    };
}

pub fn to_symbols(
    arena: *std.heap.ArenaAllocator,
    doc: *Document,
    encoding: Line.Encoding,
) anyerror![]lsp.document_symbol.DocumentSymbol {
    var symbol_tree = SymbolTree.init(arena.allocator());
    try symbol_tree.process(arena, doc, encoding);
    return symbol_tree.toOwnedSlice();
}
