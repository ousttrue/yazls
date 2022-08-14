const std = @import("std");
const astutil = @import("astutil");
const Project = astutil.Project;
const Document = astutil.Document;
const AstToken = astutil.AstToken;
const AstNode = astutil.AstNode;
const FunctionSignature = astutil.FunctionSignature;
// const builtin_completions = @import("./builtin_completions.zig");
const logger = std.log.scoped(.Signature);

/// triggerd
///
/// @import()
///         ^ r_paren
pub fn getSignature(
    arena: *std.heap.ArenaAllocator,
    project: Project,
    doc: *Document,
    token: AstToken,
) !?FunctionSignature {
    const node = AstNode.fromTokenIndex(doc.ast_context, token.index);
    var buf: [2]u32 = undefined;
    switch (node.getChildren(&buf)) {
        .call => |full| {
            const fn_node = AstNode.init(node.context, full.ast.fn_expr);
            const resolved = try project.resolveType(fn_node);
            return try FunctionSignature.fromNode(
                arena.allocator(),
                resolved,
                @intCast(u32, full.ast.params.len),
            );
        },
        // .builtin_call => |full| {
        //     const name = node.getMainToken().getText();
        //     for (builtin_completions.data()) |b| {
        //         if (std.mem.eql(u8, b.name, name)) {
        //             var fs = FunctionSignature.init(
        //                 arena.allocator(),
        //                 b.signature,
        //                 b.documentation,
        //                 "",
        //                 @intCast(u32, full.ast.params.len),
        //             );
        //             for (b.arguments) |arg| {
        //                 if (std.mem.indexOf(u8, arg, ":")) |found| {
        //                     try fs.args.append(.{
        //                         .name = arg[0..found],
        //                         .document = arg[found + 1 ..],
        //                     });
        //                 } else {
        //                     try fs.args.append(.{
        //                         .name = arg,
        //                         .document = arg,
        //                     });
        //                 }
        //             }
        //             return fs;
        //         }
        //     }
        //     logger.err("builtin {s} not found", .{name});
        // },
        else => {
            logger.debug("getSignature: not function call: {s}", .{try node.allocPrint(arena.allocator())});
            return null;
        },
    }

    return null;
}
