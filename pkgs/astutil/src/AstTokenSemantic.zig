const std = @import("std");
const AstContext = @import("./AstContext.zig");
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");

pub const Param = struct {
    index: u32,
    node: AstNode,
};

const Self = @This();

token_index: u32,
kind: union(enum) {
    unknown: AstNode,
    containerVarName: AstNode,
    fieldName: AstNode,
    fieldType: AstNode,
    fnName: AstNode,
    fnParamName: Param,
    fnParamType: Param,
    fnReturnType: AstNode,
},

pub fn init(context: *const AstContext, token_index: u32) Self {
    const token = AstToken.init(&context.tree, token_index);
    std.debug.assert(token.getTag() == .identifier);

    const node = AstNode.fromTokenIndex(context, token_index);
    var buf: [2]u32 = undefined;
    return switch (node.getChildren(&buf)) {
        .var_decl => blk: {
            break :blk Self{
                .token_index = token_index,
                .kind = .{ .containerVarName = node },
            };
        },
        .container_field => Self{
            .token_index = token_index,
            .kind = .{ .fieldName = node },
        },
        .fn_proto => |full| blk: {
            if (full.name_token) |name_token| {
                if (name_token == token_index) {
                    break :blk Self{
                        .token_index = token_index,
                        .kind = .{ .fnName = node },
                    };
                }
            }
            var it = full.iterate(&context.tree);
            var i: u32 = 0;
            while (it.next()) |param| : (i += 1) {
                if (param.name_token) |name_token| {
                    if (name_token == token_index) {
                        break :blk Self{
                            .token_index = token_index,
                            .kind = .{ .fnParamName = .{ .index = i, .node = node } },
                        };
                    }
                }
            }
            unreachable;
        },
        else => switch (node.getTag()) {
            // reference to local var or global var
            .identifier => blk: {
                var it = node.parentIterator();
                it.next();
                while (it.current) |parent| : (it.next()) {
                    switch (parent.getChildren(&buf)) {
                        .container_field => {
                            break :blk Self{
                                .token_index = token_index,
                                .kind = .{ .fieldType = parent },
                            };
                        },
                        .fn_proto => |full| {
                            if (full.ast.return_type == node.index) {
                                break :blk Self{
                                    .token_index = token_index,
                                    .kind = .{ .fnReturnType = parent },
                                };
                            }
                            var param_it = full.iterate(&context.tree);
                            var i: u32 = 0;
                            while (param_it.next()) |param| : (i += 1) {
                                if (param.type_expr == node.index) {
                                    break :blk Self{
                                        .token_index = token_index,
                                        .kind = .{ .fnParamType = .{ .index = i, .node = parent } },
                                    };
                                }
                            }
                        },
                        else => {},
                    }
                }
                break :blk Self{
                    .token_index = token_index,
                    .kind = .{ .unknown = node },
                };
            },
            else => Self{
                .token_index = token_index,
                .kind = .{ .unknown = node },
            },
        },
    };
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

    try std.testing.expectEqualStrings(@tagName(.containerVarName), @tagName(init(context, context.getToken(0, 6).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.containerVarName), @tagName(init(context, context.getToken(1, 6).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fieldName), @tagName(init(context, context.getToken(3, 0).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fieldType), @tagName(init(context, context.getToken(3, 8).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fnName), @tagName(init(context, context.getToken(5, 4).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fnName), @tagName(init(context, context.getToken(10, 4).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fnParamName), @tagName(init(context, context.getToken(10, 7).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fnParamType), @tagName(init(context, context.getToken(10, 13).?.index).kind));
    try std.testing.expectEqualStrings(@tagName(.fnReturnType), @tagName(init(context, context.getToken(10, 19).?.index).kind));
}
