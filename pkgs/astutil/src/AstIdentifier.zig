const std = @import("std");
const AstContext = @import("./AstContext.zig");
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");
const Utf8Buffer = @import("./Utf8Buffer.zig");
const Project = @import("./Project.zig");
const Declaration = @import("./declaration.zig").Declaration;
const PrimitiveType = @import("./primitives.zig").PrimitiveType;
const LiteralType = @import("./literals.zig").LiteralType;
const logger = std.log.scoped(.AstIdentifier);

pub const AstIdentifierKind = union(enum) {
    /// top level reference
    /// u32; primitive
    /// null, undfined; literal
    /// std.zig.Ast;
    /// ^
    /// primitive or literal or type reference
    identifier,
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

    /// function parameter
    /// fn func_name(param: type) void;
    ///              ^
    function_param: u32,
};

pub const TypeNode = union(enum) {
    node: AstNode,
    primitive: PrimitiveType,
    literal: LiteralType,
};

const Self = @This();

node: AstNode,
kind: AstIdentifierKind,

pub fn init(node: AstNode, token: ?AstToken) ?Self {
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
        .fn_proto => |fn_proto| {
            if (token) |t| {
                var it = fn_proto.iterate(&node.context.tree);
                var i: u32 = 0;
                while (it.next()) |param| : (i += 1) {
                    if (param.name_token) |name_token| {
                        if (name_token == t.index) {
                            return Self{
                                .node = node,
                                .kind = .{ .function_param = i },
                            };
                        }
                    }
                }
                logger.err("token not found: {s} => {s}", .{ t.getText(), node.getText() });
                return null;
            } else {
                logger.err("no token: {s}", .{node.getText()});
                return null;
            }
        },
        else => {
            switch (node.getTag()) {
                .identifier => {
                    return Self{
                        .node = node,
                        .kind = .identifier,
                    };
                },
                .field_access => {
                    return Self{
                        .node = node,
                        .kind = .field_access,
                    };
                },
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
    return init(node).?;
}

pub fn getTypeNode(self: Self, allocator: std.mem.Allocator, project: Project) !TypeNode {
    const node = self.node;
    var buf: [2]u32 = undefined;
    const type_node = switch (self.kind) {
        .field_access => try project.resolveFieldAccess(allocator, node),
        .identifier => blk: {
            if (PrimitiveType.fromName(node.getText())) |primitive| {
                return TypeNode{
                    .primitive = primitive,
                };
            } else if (LiteralType.fromName(node.getText())) |literal| {
                return TypeNode{
                    .literal = literal,
                };
            } else if (Declaration.find(node)) |decl| {
                break :blk try decl.getTypeNode();
            } else {
                logger.err("{s}", .{node.getText()});
                return error.NoDeclForIdentifier;
            }
        },
        .container_field => switch (node.getChildren(&buf)) {
            .container_field => |full| AstNode.init(node.context, full.ast.type_expr),
            else => {
                unreachable;
            },
        },
        .var_decl => switch (node.getChildren(&buf)) {
            .var_decl => |full| if (full.ast.type_node != 0)
                AstNode.init(node.context, full.ast.type_node)
            else if (full.ast.init_node != 0)
                AstNode.init(node.context, full.ast.init_node)
            else {
                unreachable;
            },
            else => {
                unreachable;
            },
        },
        .if_payload => switch (node.getChildren(&buf)) {
            .@"if" => |full| blk: {
                std.debug.assert(full.payload_token != null);
                break :blk AstNode.init(node.context, full.ast.cond_expr);
            },
            else => {
                unreachable;
            },
        },
        .while_payload => switch (node.getChildren(&buf)) {
            .@"while" => |full| blk: {
                std.debug.assert(full.payload_token != null);
                break :blk AstNode.init(node.context, full.ast.cond_expr);
            },
            else => {
                unreachable;
            },
        },
        .switch_case_payload => switch (node.getChildren(&buf)) {
            .switch_case => |full| blk: {
                std.debug.assert(full.payload_token != null);
                if (node.getParent()) |parent| {
                    std.debug.assert(parent.isChildrenTagName("switch"));
                    switch (parent.getChildren(&buf)) {
                        .@"switch" => |switch_full| {
                            break :blk AstNode.init(node.context, switch_full.ast.cond_expr);
                        },
                        else => {
                            unreachable;
                        },
                    }
                } else {
                    return error.NoSwitchCaseParent;
                }
            },
            else => {
                unreachable;
            },
        },
        .function_param => |index| switch(node.getChildren(&buf))
        {
            .fn_proto => |fn_proto| blk: {
                var it = fn_proto.iterate(&node.context.tree);
                var i: u32 = 0;
                while(it.next())|param|:(i+=1)
                {
                    if(i==index)
                    {
                        break :blk AstNode.init(node.context, param.type_expr);
                    }
                }
                unreachable;
            },
            else => {
                    return error.NoFnProto;
            },
        },
    };

    return TypeNode{
        .node = type_node,
    };
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
        try std.testing.expectEqual(AstIdentifierKind.identifier, id.kind);
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
        try std.testing.expectEqual(AstIdentifierKind.var_decl, id.kind);
    }
    {
        const value = context.getToken(11, 28).?;
        try std.testing.expectEqualStrings("value", value.getText());
        const id = fromToken(context, value);
        try std.testing.expectEqual(AstIdentifierKind.if_payload, id.kind);
    }
    {
        const value = context.getToken(3, 0).?;
        try std.testing.expectEqualStrings("value", value.getText());
        const id = fromToken(context, value);
        try std.testing.expectEqual(AstIdentifierKind.container_field, id.kind);
    }
}
