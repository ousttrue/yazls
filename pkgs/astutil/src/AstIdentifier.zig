const std = @import("std");
const AstContext = @import("./AstContext.zig");
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");
const Utf8Buffer = @import("./Utf8Buffer.zig");
const Project = @import("./Project.zig");
const Declaration = @import("./declaration.zig").Declaration;
const logger = std.log.scoped(.AstIdentifier);

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
    ///       ^     ^
    /// to resolve type, type_node or init_node
    var_decl,
    /// container field name
    /// name: u32 = 0,
    /// ^     ^
    /// to resolve type_node
    container_field,
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

    // fn_proto,
    // fn_decl,
    enum_literal,
    error_value,
};

const Self = @This();

node: AstNode,
kind: AstIdentifierKind,

pub fn init(node: AstNode) ?Self {
    var buf: [2]u32 = undefined;
    switch (node.getChildren(&buf)) {
        .var_decl => {
            return Self{
                .node = node,
                .kind = .var_decl,
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
                .kind = .container_field,
            };
        },
        // .fn_proto => {
        //     return Self{
        //         .node = node,
        //         .kind = .fn_proto,
        //     };
        // },
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
                // .fn_decl => {
                //     return Self{
                //         .node = node,
                //         .kind = .fn_decl,
                //     };
                // },
                else => {
                    return null;
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

pub fn getTypeNode(self: Self, allocator: std.mem.Allocator, project: Project) !AstNode {
    const node = self.node;
    var buf: [2]u32 = undefined;
    switch (self.kind) {
        .field_access => {
            return try project.resolveFieldAccess(allocator, node);
        },
        .reference => {
            if (Declaration.find(node)) |decl| {
                return try decl.getTypeNode();
            } else {
                return error.NoDecl;
            }
        },
        .container_field => {
            switch (node.getChildren(&buf)) {
                .container_field => |full| {
                    return AstNode.init(node.context, full.ast.type_expr);
                },
                else => {
                    unreachable;
                },
            }
        },
        .var_decl => {
            switch (node.getChildren(&buf)) {
                .var_decl => |full| {
                    if (full.ast.type_node != 0) {
                        return AstNode.init(node.context, full.ast.type_node);
                    } else if (full.ast.init_node != 0) {
                        return AstNode.init(node.context, full.ast.init_node);
                    } else {
                        unreachable;
                    }
                },
                else => {
                    unreachable;
                },
            }
        },
        .if_payload => {
            switch (node.getChildren(&buf)) {
                .@"if" => |full| {
                    std.debug.assert(full.payload_token != null);
                    return AstNode.init(node.context, full.ast.cond_expr);
                },
                else => {
                    unreachable;
                },
            }
        },
        .while_payload => {
            switch (node.getChildren(&buf)) {
                .@"while" => |full| {
                    std.debug.assert(full.payload_token != null);
                    return AstNode.init(node.context, full.ast.cond_expr);
                },
                else => {
                    unreachable;
                },
            }
        },
        .switch_case_payload => {
            switch (node.getChildren(&buf)) {
                .switch_case => |full| {
                    std.debug.assert(full.payload_token != null);
                    if (node.getParent()) |parent| {
                        std.debug.assert(parent.getTag() == .@"switch");
                        switch (parent.getChildren(&buf)) {
                            .@"switch" => |switch_full| {
                                return AstNode.init(node.context, switch_full.ast.cond_expr);
                            },
                            else => {
                                unreachable;
                            },
                        }
                    } else {
                        return error.NoSwitch;
                    }
                },
                else => {
                    unreachable;
                },
            }
        },
        // .fn_decl => {
        //     return node;
        // },
        // .fn_proto => {
        //     return node;
        // },
        .enum_literal => {
            unreachable;
        },
        .error_value => {
            unreachable;
        },
    }
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