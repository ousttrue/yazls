const std = @import("std");
const Ast = std.zig.Ast;
const AstContext = @import("./AstContext.zig");
const Utf8Buffer = @import("./Utf8Buffer.zig");
const AstToken = @import("./AstToken.zig");
const AstNodeIterator = @import("./AstNodeIterator.zig");
const PathPosition = @import("./PathPosition.zig");
const logger = std.log.scoped(.AstNode);
const Self = @This();

context: *const AstContext,
index: u32,

pub fn init(context: *const AstContext, index: u32) Self {
    return Self{
        .context = context,
        .index = index,
    };
}

pub fn fromTokenIndex(context: *const AstContext, token_idx: u32) Self {
    const idx = context.tokens_node[token_idx];
    return init(context, idx);
}

pub fn getPosition(self: Self) PathPosition {
    return .{
        .path = self.context.path,
        .loc = self.getMainToken().getLoc(),
    };
}

pub fn debugPrint(self: Self) void {
    logger.debug(
        "debugPrint: {s}:{} [{}]{s}",
        .{
            self.context.path.slice(),
            self.context.tree.tokenLocation(0, self.getMainToken().index).line + 1,
            self.getTag(),
            self.getMainToken().getText(),
        },
    );
}

fn printRec(self: Self, w: anytype) std.mem.Allocator.Error!void {
    var buffer: [2]u32 = undefined;
    const children = self.getChildren(&buffer);
    switch (children) {
        .container_decl, .block => {},
        else => {
            if (self.getParent()) |parent| {
                try parent.printRec(w);
                try w.print("/", .{});
            }
        },
    }
    switch (children) {
        .container_decl => try w.print("<{s}>", .{@tagName(self.getTag())}),
        .block => try w.print("[{s}]", .{@tagName(self.getTag())}),
        else => try w.print("{s}", .{@tagName(self.getTag())}),
    }
}

pub fn allocPrint(self: Self, allocator: std.mem.Allocator) ![]const u8 {
    if (self.index == 0) {
        // return "[root]";
        return self.context.path.getName();
    }

    var buffer = std.ArrayList(u8).init(allocator);
    const w = buffer.writer();

    // AST path
    try self.printRec(w);

    // var NAME
    // const NAME
    // fn NAME(ARG0: type) RESULT;
    // NAME: type,

    var buf: [2]u32 = undefined;
    switch (self.getChildren(&buf)) {
        .var_decl => {
            try w.print("[var_decl]", .{});
        },
        .switch_case => {
            try w.print("[switch_payload]", .{});
        },
        else => {},
    }

    return buffer.items;
}

pub fn getText(self: Self) []const u8 {
    const tree = &self.context.tree;
    const first = AstToken.init(tree, tree.firstToken(self.index)).getLoc();
    const last = AstToken.init(tree, tree.lastToken(self.index)).getLoc();
    return tree.source[first.start..last.end];
}

pub fn getTag(self: Self) Ast.Node.Tag {
    const tag = self.context.tree.nodes.items(.tag);
    return tag[self.index];
}

pub fn getData(self: Self) Ast.Node.Data {
    const data = self.context.tree.nodes.items(.data);
    return data[self.index];
}

pub fn getMainToken(self: Self) AstToken {
    const main_token = self.context.tree.nodes.items(.main_token);
    return AstToken.init(&self.context.tree, main_token[self.index]);
}

pub fn getChildren(self: Self, buffer: []u32) AstNodeIterator.NodeChildren {
    return AstNodeIterator.NodeChildren.init(self.context.tree, self.index, buffer);
}

pub fn isChildrenTagName(self: Self, tagName: []const u8) bool {
    var buffer: [2]u32 = undefined;
    const children = self.getChildren(&buffer);
    return std.mem.eql(u8, @tagName(children), tagName);
}

pub fn getContainerDecl(self: Self, buffer: []u32) ?Ast.full.ContainerDecl {
    const children = self.getChildren(buffer);
    return switch (children) {
        .container_decl => |container_decl| container_decl,
        else => null,
    };
}

/// from var or field
pub fn getTypeNode(self: Self) ?Self {
    var buf: [2]u32 = undefined;
    switch (self.getChildren(&buf)) {
        .var_decl => |var_decl| {
            if (var_decl.ast.type_node != 0) {
                return Self.init(self.context, var_decl.ast.type_node);
            } else {
                return Self.init(self.context, var_decl.ast.init_node);
            }
        },
        .container_field => |container_field| {
            if (container_field.ast.type_expr != 0) {
                return Self.init(self.context, container_field.ast.type_expr);
            } else {
                // enum decl
            }
        },
        else => {},
    }
    return null;
}

pub fn getParent(self: Self) ?Self {
    if (self.index == 0) {
        return null;
    }
    const index = self.context.nodes_parent[self.index];
    return init(self.context, index);
}

pub const Iterator = struct {
    current: ?Self,

    pub fn next(self: *@This()) void {
        if (self.current) |current| {
            self.current = current.getParent();
        }
    }
};

pub fn parentIterator(self: Self) Iterator {
    return Iterator{ .current = self };
}

test {
    const source =
        \\pub fn main() !void {
        \\    
        \\}
    ;
    const allocator = std.testing.allocator;
    const text: [:0]const u8 = try allocator.dupeZ(u8, source);
    defer allocator.free(text);
    const line_heads = try Utf8Buffer.allocLineHeads(allocator, text);
    defer allocator.free(line_heads);
    const context = try AstContext.new(allocator, .{}, text, line_heads);
    defer context.delete();

    const node = fromTokenIndex(context, 0);
    try std.testing.expectEqual(node.getTag(), .fn_proto_simple);

    const parent_node = node.getParent().?;
    try std.testing.expectEqual(parent_node.getTag(), .fn_decl);

    const root_node = parent_node.getParent().?;
    try std.testing.expectEqual(root_node.getTag(), .root);
}

/// container/decl/this => this is container
/// fn some(self: @This()) @This(){}
pub fn getContainerNodeForThis(self: Self) ?Self {
    var current = self;
    while (true) {
        if (current.getParent()) |parent| {
            var buf: [2]u32 = undefined;
            if (parent.getChildren(&buf) == .container_decl) {
                return parent;
            }
            current = parent;
        } else {
            break;
        }
    }
    return null;
}

test "@This" {
    const source = @embedFile("./test_source.zig");
    const allocator = std.testing.allocator;
    const text: [:0]const u8 = try allocator.dupeZ(u8, source);
    defer allocator.free(text);
    const line_heads = try Utf8Buffer.allocLineHeads(allocator, text);
    defer allocator.free(line_heads);
    const context = try AstContext.new(allocator, .{}, text, line_heads);
    defer context.delete();

    const node = Self.fromTokenIndex(context, 3);
    var buf: [2]u32 = undefined;
    try std.testing.expect(node.getChildren(&buf) == .builtin_call);

    const parent = node.getParent().?;
    try std.testing.expect(parent.getChildren(&buf) == .var_decl);

    const pp = parent.getParent().?;
    try std.testing.expect(pp.getChildren(&buf) == .container_decl);

    try std.testing.expectEqual(pp, node.getContainerNodeForThis().?);
}

pub fn gotoPosition(self: Self) PathPosition {
    return PathPosition{
        .path = self.context.path,
        .loc = self.getMainToken().getLoc(),
    };
}
