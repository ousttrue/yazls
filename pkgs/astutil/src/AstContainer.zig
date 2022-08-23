const std = @import("std");
const Ast = std.zig.Ast;
const AstContext = @import("./AstContext.zig");
const AstNode = @import("./AstNode.zig");
const AstToken = @import("./AstToken.zig");
const AstNodeIterator = @import("./AstNodeIterator.zig");
const logger = std.log.scoped(.AstContainer);

fn getFnProtoName(node: AstNode, fn_proto: Ast.full.FnProto) ?AstToken {
    return if (fn_proto.name_token) |name_token|
        AstToken.init(&node.context.tree, name_token)
    else
        null;
}

fn getFnDeclName(node: AstNode) ?AstToken {
    // fn_decl.lhs => fn_proto.name
    std.debug.assert(node.getTag() == .fn_decl);
    const proto = AstNode.init(node.context, node.getData().lhs);
    var buf: [2]u32 = undefined;
    if (proto.getFnProto(&buf)) |fn_proto| {
        return getFnProtoName(proto, fn_proto);
    } else {
        unreachable;
    }
}

fn getTestName(node: AstNode) ?AstToken {
    const data = node.getData();
    return if (data.lhs != 0)
        AstToken.init(&node.context.tree, data.lhs)
    else
        null;
}

pub const Member = struct {
    node: AstNode,
    name_token: ?AstToken,
    kind: enum {
        field,
        var_decl,
        fn_proto,
        fn_decl,
        test_decl,
    },

    pub fn init(node: AstNode) ?Member {
        var buf: [2]u32 = undefined;
        return switch (node.getChildren(&buf)) {
            .container_field => |container_field| .{
                .node = node,
                .name_token = AstToken.init(&node.context.tree, container_field.ast.name_token),
                .kind = .field,
            },
            .var_decl => |var_decl| .{
                .node = node,
                .name_token = AstToken.init(&node.context.tree, var_decl.ast.mut_token + 1),
                .kind = .var_decl,
            },
            .fn_proto => |fn_proto| .{
                .node = node,
                .name_token = getFnProtoName(node, fn_proto),
                .kind = .fn_proto,
            },
            else => switch (node.getTag()) {
                .fn_decl => Member{
                    .node = node,
                    .name_token = getFnDeclName(node),
                    .kind = .fn_decl,
                },
                .test_decl => Member{
                    .node = node,
                    .name_token = getTestName(node),
                    .kind = .test_decl,
                },
                else => {
                    logger.err("{}", .{node.getTag()});
                    return null;
                },
            },
        };
    }
};

const ContainerIterator = struct {
    context: *const AstContext,
    full: Ast.full.ContainerDecl,
    pos: u32 = 0,

    pub fn init(node: AstNode, buf: []u32) ContainerIterator {
        switch (node.getChildren(buf)) {
            .container_decl => |container_decl| {
                return .{
                    .context = node.context,
                    .full = container_decl,
                };
            },
            else => {
                unreachable;
            },
        }
    }

    pub fn next(self: *ContainerIterator) ?Member {
        if (self.pos >= self.full.ast.members.len) {
            return null;
        }
        defer self.pos += 1;
        return Member.init(AstNode.init(self.context, self.full.ast.members[self.pos]));
    }
};

const Self = @This();

node: AstNode,

pub fn init(node: AstNode) ?Self {
    return if (node.isChildrenTagName("container_decl"))
        Self{
            .node = node,
        }
    else
        null;
}

pub fn iterator(self: Self, buf: []u32) ContainerIterator {
    return ContainerIterator.init(self.node, buf);
}

pub fn getMember(self: Self, name: []const u8) ?Member {
    var buf: [2]u32 = undefined;
    var it = self.iterator(&buf);
    while (it.next()) |member| {
        if (member.name_token) |token| {
            if (std.mem.eql(u8, token.getText(), name)) {
                return member;
            }
        } else {
            logger.err("no member name", .{});
        }
    }

    logger.err("not found: {s} from {s}", .{ name, self.node.getMainToken().getText() });
    return null;
}

test {
    const source = @embedFile("test_source.zig");
    const allocator = std.testing.allocator;
    const text: [:0]const u8 = try allocator.dupeZ(u8, source);
    defer allocator.free(text);
    const context = try AstContext.new(allocator, .{}, text);
    defer context.delete();

    const root = Self.init(AstNode.init(context, 0)).?;
    try std.testing.expectEqual(root.getMember("Self").?.kind, .var_decl);
    try std.testing.expectEqual(root.getMember("value").?.kind, .field);
    try std.testing.expectEqual(root.getMember("init").?.kind, .fn_decl);
    try std.testing.expectEqual(root.getMember("\"empty_test\"").?.kind, .test_decl);
    try std.testing.expectEqual(root.getMember("external_func").?.kind, .fn_proto);
}
