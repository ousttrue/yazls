const std = @import("std");
const astutil = @import("astutil");
const Project = astutil.Project;
const Document = astutil.Document;
const AstToken = astutil.AstToken;
const AstNode = astutil.AstNode;
const Declaration = astutil.Declaration;
const FunctionSignature = astutil.FunctionSignature;
const AstIdentifier = astutil.AstIdentifier;
// const builtin_completions = @import("./builtin_completions.zig");
const logger = std.log.scoped(.Hover);
const Self = @This();

text: []const u8,
loc: ?std.zig.Token.Loc = null,

pub fn getHover(
    arena: *std.heap.ArenaAllocator,
    project: Project,
    doc: *Document,
    token: AstToken,
) !?Self {
    const allocator = arena.allocator();
    var text_buffer = std.ArrayList(u8).init(allocator);
    const node = AstNode.fromTokenIndex(doc.ast_context, token.index);
    if (AstIdentifier.init(node)) |id| {
        const token_info = try token.allocPrint(allocator);
        const node_info = try node.allocPrint(allocator);
        const w = text_buffer.writer();
        try w.print("`{s} => {s}`\n\n", .{ node_info, token_info });

        var may_resolved: ?AstNode = null;
        switch (id.kind) {
            .field_access => {
                may_resolved = try project.resolveFieldAccess(arena.allocator(), node);
            },
            .reference => {
                may_resolved = try project.resolveType(arena.allocator(), node);
            },
            .var_decl => {},
            .container_field => {},
            .if_payload => {},
            .while_payload => {},
            .switch_case_payload => {},
            .enum_literal => {},
            .error_value => {},
        }

        if (may_resolved) |resolved| {
            if (FunctionSignature.fromNode(allocator, resolved, 0)) |signature| {
                const text = try signature.allocPrintSignature(allocator);
                try w.print("\n```zig\n{s}\n```\n", .{text});
                return Self{
                    .text = text_buffer.items,
                };
            } else |_| {
                const text = try resolved.allocPrint(allocator);
                try w.print("{s}", .{text});
                return Self{
                    .text = text_buffer.items,
                };
            }
        } else {
            try w.print("no resolved", .{});
        }
    } else {
        return error.NoIdentifier;
    }
    return Self{
        .text = text_buffer.items,
    };
}
