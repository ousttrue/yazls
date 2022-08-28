const std = @import("std");
const AstContext = @import("./AstContext.zig");
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");
const AstNodeSemantic = @import("./AstNodeSemantic.zig");

pub const Param = struct {
    index: u32,
    node: AstNode,
};

const Self = @This();

token_index: u32,
kind: union(enum) {
    unknown: AstNode,
    varName: AstNode,
    varType: AstNode,
    fieldName: AstNode,
    fieldType: AstNode,
    fnName: AstNode,
    fnParamName: Param,
    fnParamType: Param,
    fnReturnType: AstNode,
    structInitType: AstNode,
    expression: AstNode,
},

pub fn init(context: *const AstContext, token_index: u32) Self {
    const token = AstToken.init(&context.tree, token_index);
    std.debug.assert(token.getTag() == .identifier);

    const node = AstNode.fromTokenIndex(context, token_index);
    const node_semantic = AstNodeSemantic.init(node) orelse {
        return Self{
            .token_index = token_index,
            .kind = .{ .unknown = node },
        };
    };

    var buf: [2]u32 = undefined;
    switch (node_semantic.kind) {
        .varDecl => |semantic_node| {
            switch (semantic_node.getChildren(&buf)) {
                .var_decl => |full| {
                    if (full.ast.mut_token + 1 == token_index) {
                        return Self{
                            .token_index = token_index,
                            .kind = .{ .varName = semantic_node },
                        };
                    }

                    if (full.ast.type_node != 0) {
                        const type_node = AstNode.init(semantic_node.context, full.ast.type_node);
                        if (type_node.containsToken(token_index)) {
                            return Self{
                                .token_index = token_index,
                                .kind = .{ .varType = type_node },
                            };
                        }
                    }

                    if (full.ast.init_node != 0) {
                        const init_node = AstNode.init(semantic_node.context, full.ast.init_node);
                        if (init_node.containsToken(token_index)) {
                            return Self{
                                .token_index = token_index,
                                .kind = .{ .expression = init_node },
                            };
                        }
                    }
                },
                else => {},
            }
            return Self{
                .token_index = token_index,
                .kind = .{ .unknown = node },
            };
        },
        .fieldDecl => |semantic_node| {
            switch (semantic_node.getChildren(&buf)) {
                .container_field => |full| {
                    if (full.ast.name_token == token_index) {
                        return Self{
                            .token_index = token_index,
                            .kind = .{ .fieldName = semantic_node },
                        };
                    }

                    if (full.ast.type_expr != 0) {
                        const type_node = AstNode.init(semantic_node.context, full.ast.type_expr);
                        if (type_node.containsToken(token_index)) {
                            return Self{
                                .token_index = token_index,
                                .kind = .{ .fieldType = type_node },
                            };
                        }
                    }

                    if (full.ast.value_expr != 0) {
                        const expr_node = AstNode.init(semantic_node.context, full.ast.value_expr);
                        if (expr_node.containsToken(token_index)) {
                            return Self{
                                .token_index = token_index,
                                .kind = .{ .expression = expr_node },
                            };
                        }
                    }
                },
                else => {},
            }
            unreachable;
        },
        .structInit => |semantic_node| {
            if (semantic_node.index == node.index) {
                return Self{
                    .token_index = token_index,
                    .kind = .{ .fieldName = semantic_node },
                };
            }

            switch (semantic_node.getChildren(&buf)) {
                .struct_init => |full| {
                    if (full.ast.type_expr != 0) {
                        const type_node = AstNode.init(semantic_node.context, full.ast.type_expr);
                        if (type_node.containsToken(token_index)) {
                            return Self{
                                .token_index = token_index,
                                .kind = .{ .structInitType = type_node },
                            };
                        }
                    }

                    for (full.ast.fields) |field_node_index| {
                        const field_node = AstNode.init(semantic_node.context, field_node_index);
                        if (field_node.containsToken(token_index)) {
                            return Self{
                                .token_index = token_index,
                                .kind = .{ .expression = field_node },
                            };
                        }
                    }
                },
                else => {},
            }

            unreachable;
        },
        .fnProto => |semantic_node| {
            switch (semantic_node.getChildren(&buf)) {
                .fn_proto => |full| {
                    if (full.name_token) |name_token| {
                        if (name_token == token_index) {
                            return Self{
                                .token_index = token_index,
                                .kind = .{ .fnName = semantic_node },
                            };
                        }
                    }

                    const return_type_node = AstNode.init(semantic_node.context, full.ast.return_type);
                    if (return_type_node.containsToken(token_index)) {
                        return Self{
                            .token_index = token_index,
                            .kind = .{ .fnReturnType = semantic_node },
                        };
                    }

                    var it = full.iterate(&semantic_node.context.tree);
                    var i: u32 = 0;
                    while (it.next()) |param| : (i += 1) {
                        if (param.name_token == token_index) {
                            return Self{
                                .token_index = token_index,
                                .kind = .{ .fnParamName = .{ .index = i, .node = semantic_node } },
                            };
                        }

                        const type_node = AstNode.init(semantic_node.context, param.type_expr);
                        if (type_node.containsToken(token_index)) {
                            return Self{
                                .token_index = token_index,
                                .kind = .{ .fnParamType = .{ .index = i, .node = type_node } },
                            };
                        }
                    }
                },
                else => {},
            }
            unreachable;
        },
        // call, field_access, identifier
        .blockVar => |semantic_node| {
            return Self{
                .token_index = token_index,
                .kind = .{ .expression = semantic_node },
            };
        },
    }
}

pub fn allocPrint(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const w = buf.writer();

    try w.print("{s}", .{@tagName(self.kind)});

    return buf.toOwnedSlice();
}

test "AstTokenSemantic" {
    const source = @embedFile("test_source.zig");
    const allocator = std.testing.allocator;
    const text: [:0]const u8 = try allocator.dupeZ(u8, source);
    defer allocator.free(text);
    const Utf8Buffer = @import("./Utf8Buffer.zig");
    const line_heads = try Utf8Buffer.allocLineHeads(allocator, text);
    defer allocator.free(line_heads);
    const context = try AstContext.new(allocator, .{}, text, line_heads);
    defer context.delete();

    try std.testing.expectEqualStrings(@tagName(.varName), @tagName(init(context, context.getToken(0, 6).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.varName), @tagName(init(context, context.getToken(1, 6).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fieldName), @tagName(init(context, context.getToken(3, 0).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fieldType), @tagName(init(context, context.getToken(3, 8).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fnName), @tagName(init(context, context.getToken(5, 4).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fnName), @tagName(init(context, context.getToken(10, 4).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fnParamName), @tagName(init(context, context.getToken(10, 7).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fnParamType), @tagName(init(context, context.getToken(10, 13).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fnReturnType), @tagName(init(context, context.getToken(10, 19).?.index).kind));
}
