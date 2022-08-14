const std = @import("std");
const astutil = @import("astutil");
const Project = astutil.Project;
const Document = astutil.Document;
const AstToken = astutil.AstToken;
const AstNode = astutil.AstNode;
const Declaration = astutil.Declaration;
const FunctionSignature = astutil.FunctionSignature;
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
    _ = project;
    const allocator = arena.allocator();
    const token_info = try token.allocPrint(allocator);
    const node = AstNode.fromTokenIndex(doc.ast_context, token.index);
    const node_info = try node.allocPrint(allocator);

    var text_buffer = std.ArrayList(u8).init(allocator);
    const w = text_buffer.writer();
    try w.print("`{s} => {s}`\n\n", .{ node_info, token_info });

    switch (token.getTag()) {
        // .builtin => {
        //     if (builtin_completions.find(token.getText())) |builtin| {
        //         try w.print(
        //             "\n```zig\n{s}\n```\n\n{s}",
        //             .{ builtin.signature, builtin.documentation },
        //         );
        //         return Self{
        //             .text = text_buffer.items,
        //         };
        //     }
        // },
        .identifier => {
            // .call => {
            //     const resolved = try project.resolveType(node);
            //     const text = try resolved.allocPrint(allocator);
            //     try w.print("{s}", .{text});
            //     return Self{
            //         .text = text_buffer.items,
            //     };
            // },
            switch (node.getTag()) {
                .identifier => {
                    if (Declaration.find(node)) |decl| {
                        const text = try decl.allocPrint(allocator);
                        try w.print("{s}", .{text});
                        switch (decl) {
                            .local => |local| {
                                return Self{
                                    .text = text_buffer.items,
                                    .loc = local.name_token.getLoc(),
                                };
                            },
                            .container => |container| {
                                return Self{
                                    .text = text_buffer.items,
                                    .loc = container.name_token.getLoc(),
                                };
                            },
                            .primitive => {},
                        }
                    } else {
                        logger.debug("identifier: {s}: decl not found", .{token.getText()});
                    }
                },
                .field_access => {
                    const resolved = try project.resolveFieldAccess(node);
                    if (FunctionSignature.fromNode(allocator, resolved, 0)) |signature| {
                        const text = try signature.allocPrint(allocator);
                        try w.print("{s}", .{text});
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
                },
                else => {
                    // const var_type = try VarType.init(project, node);
                    // const text = try var_type.allocPrint(allocator);
                    // try w.print("var_type: {s}", .{text});
                    // return Self{
                    //     .text = text_buffer.items,
                    // };
                },
            }
        },
        else => {},
    }

    return Self{
        .text = text_buffer.items,
    };
}
