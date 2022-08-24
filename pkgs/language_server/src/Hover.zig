const std = @import("std");
const astutil = @import("astutil");
const Project = astutil.Project;
const Document = astutil.Document;
const AstToken = astutil.AstToken;
const AstNode = astutil.AstNode;
const Declaration = astutil.Declaration;
const FunctionSignature = astutil.FunctionSignature;
const IdentifierToken = astutil.IdentifierToken;
// const builtin_completions = @import("./builtin_completions.zig");
const logger = std.log.scoped(.Hover);
const Self = @This();

text: []const u8,
loc: ?std.zig.Token.Loc = null,

fn resolve(
    arena: *std.heap.ArenaAllocator,
    project: Project,
    node: AstNode,
) ?AstNode {
    if (project.resolveFieldAccess(arena.allocator(), node)) |resolved| {
        return resolved;
    } else |_| {
        // not field
    }

    if (project.resolveType(arena.allocator(), node)) |resolved| {
        return resolved;
    } else |_| {
        // no type
    }

    return null;
}

pub fn getHover(
    arena: *std.heap.ArenaAllocator,
    project: Project,
    doc: *Document,
    token: AstToken,
) !?Self {
    const allocator = arena.allocator();
    var text_buffer = std.ArrayList(u8).init(allocator);
    if (token.getTag() == .identifier) {
        const token_info = try token.allocPrint(allocator);
        const node = AstNode.fromTokenIndex(doc.ast_context, token.index);
        const node_info = try node.allocPrint(allocator);
        const w = text_buffer.writer();
        try w.print("`{s} => {s}`\n\n", .{ node_info, token_info });

        const id = IdentifierToken.init(doc.ast_context, token);
        switch (id.kind) {
            .reference => {},
            .field_access => {},
            .var_name => {},
            .field_name => {},
            .if_payload => {},
            .while_payload => {},
            .switch_case_payload => {},
            .function_name => {},
            .function_param_name => {},
        }

        if (resolve(arena, project, node)) |resolved| {
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
    }
    return Self{
        .text = text_buffer.items,
    };
}
