const std = @import("std");
const AstContext = @import("./AstContext.zig");
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");
const Utf8Buffer = @import("./Utf8Buffer.zig");
const logger = std.log.scoped(.IdentifierToken);

pub const AstIdentifierKind = enum {
    /// top level reference
    /// std.zig.Ast;
    /// ^
    /// to resolve type, search scope for name symbol
    reference,
    /// field access
    /// std.zig.Ast;
    ///     ^   ^
    field_access,
    /// variable decl name
    /// const name: u32 = 0;
    ///       ^
    /// to resolve type, type_node or init_node
    var_name,
    /// container field name
    /// name: u32 = 0,
    /// ^
    /// to resolve type_node
    field_name,
    /// if payload
    /// if(some)|payload|
    ///          ^
    /// to resolve condition_node
    if_payload,
    /// while / for payload
    /// while(some)|payload|
    ///             ^
    /// to resolve condition_node
    while_payload,
    /// switch case payload
    /// .var_decl => |full|
    ///               ^
    /// to resolve condition_node
    switch_case_payload,

    fn_proto,
    enum_literal,
    error_value,
};

const Self = @This();

node: AstNode,
kind: AstIdentifierKind,

pub fn init(node: AstNode) Self {
    var buf: [2]u32 = undefined;
    switch (node.getChildren(&buf)) {
        .var_decl => {
            return Self{
                .node = node,
                .kind = .var_name,
            };
        },
        .@"if" => {
            return Self{
                .node = node,
                .kind = .if_payload,
            };
        },
        .@"while" => {
            return Self{
                .node = node,
                .kind = .while_payload,
            };
        },
        .switch_case => {
            return Self{
                .node = node,
                .kind = .switch_case_payload,
            };
        },
        .container_field => {
            return Self{
                .node = node,
                .kind = .field_name,
            };
        },
        .fn_proto => {
            return Self{
                .node = node,
                .kind = .fn_proto,
            };
        },
        else => {
            switch (node.getTag()) {
                .identifier => {
                    return Self{
                        .node = node,
                        .kind = .reference,
                    };
                },
                .field_access => {
                    return Self{
                        .node = node,
                        .kind = .field_access,
                    };
                },
                .enum_literal => {
                    return Self{
                        .node = node,
                        .kind = .enum_literal,
                    };
                },
                .error_value => {
                    return Self{
                        .node = node,
                        .kind = .error_value,
                    };
                },
                else => {
                    logger.err("{}: {s}", .{ node.getTag(), node.getText() });
                    unreachable;
                },
            }
        },
    }
}

pub fn fromToken(context: *const AstContext, token: AstToken) Self {
    std.debug.assert(token.getTag() == .identifier);
    const node = AstNode.fromTokenIndex(context, token.index);
    return init(node);
}

test {
    const source = @embedFile("test_source.zig");
    const allocator = std.testing.allocator;
    const text: [:0]const u8 = try allocator.dupeZ(u8, source);
    defer allocator.free(text);
    const line_heads = try Utf8Buffer.allocLineHeads(allocator, text);
    defer allocator.free(line_heads);
    const context = try AstContext.new(allocator, .{}, text, line_heads);
    defer context.delete();

    {
        const value = context.getToken(5, 10).?;
        try std.testing.expectEqualStrings("Self", value.getText());
        const id = fromToken(context, value);
        try std.testing.expectEqual(AstIdentifierKind.reference, id.kind);
    }
    {
        const value = context.getToken(6, 11).?;
        try std.testing.expectEqualStrings("debug", value.getText());
        const id = fromToken(context, value);
        try std.testing.expectEqual(AstIdentifierKind.field_access, id.kind);
    }
    {
        const value = context.getToken(1, 6).?;
        try std.testing.expectEqualStrings("Self", value.getText());
        const id = fromToken(context, value);
        try std.testing.expectEqual(AstIdentifierKind.var_name, id.kind);
    }
    {
        const value = context.getToken(11, 28).?;
        try std.testing.expectEqualStrings("value", value.getText());
        const id = fromToken(context, value);
        try std.testing.expectEqual(AstIdentifierKind.if_payload, id.kind);
    }
    {
        const value = context.getToken(10, 3).?;
        try std.testing.expectEqualStrings("get", value.getText());
        const id = fromToken(context, value);
        try std.testing.expectEqual(AstIdentifierKind.function_name, id.kind);
    }
    {
        const value = context.getToken(10, 7).?;
        try std.testing.expectEqualStrings("self", value.getText());
        const id = fromToken(context, value);
        try std.testing.expectEqual(AstIdentifierKind.function_param_name, id.kind);
    }
    {
        const value = context.getToken(3, 0).?;
        try std.testing.expectEqualStrings("value", value.getText());
        const id = fromToken(context, value);
        try std.testing.expectEqual(AstIdentifierKind.field_name, id.kind);
    }
}
