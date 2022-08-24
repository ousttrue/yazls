const std = @import("std");
const astutil = @import("astutil");
const AstToken = astutil.AstToken;
const AstNode = astutil.AstNode;
const Declaration = astutil.Declaration;
const FunctionSignature = astutil.FunctionSignature;
const AstIdentifier = astutil.AstIdentifier;
const TypeResolver = astutil.TypeResolver;
// const builtin_completions = @import("./builtin_completions.zig");
const logger = std.log.scoped(.Hover);

pub fn getHover(
    allocator: std.mem.Allocator,
    token: AstToken,
    node: AstNode,
    resolved: TypeResolver.AstType,
) ![]const u8 {
    var text_buffer = std.ArrayList(u8).init(allocator);
    const w = text_buffer.writer();
    const token_info = try token.allocPrint(allocator);
    const node_info = try node.allocPrint(allocator);
    try w.print("`{s} => {s}`\n\n", .{ node_info, token_info });
    if (FunctionSignature.fromNode(allocator, resolved.node, 0)) |signature| {
        const text = try signature.allocPrintSignature(allocator);
        try w.print("\n```zig\n{s}\n```\n", .{text});
    } else |_| {
        const text = try resolved.node.allocPrint(allocator);
        try w.print("resolved: {s}", .{text});
    }
    return text_buffer.toOwnedSlice();
}
