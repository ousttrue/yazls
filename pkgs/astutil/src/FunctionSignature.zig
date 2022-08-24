const std = @import("std");
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");
const AstContext = @import("./AstContext.zig");
const Utf8Buffer = @import("./Utf8Buffer.zig");
const AstContainer = @import("./AstContainer.zig");

const Param = struct {
    name_token: ?AstToken,
    type_node: AstNode,

    pub fn getName(self: @This()) []const u8 {
        return if (self.name_token) |name_token| name_token.getText() else "_";
    }
};

const Self = @This();

allocator: std.mem.Allocator,
name_token: ?AstToken,
params: []const Param,
active_param: u32 = 0,
return_type_node: AstNode,

pub fn init(
    allocator: std.mem.Allocator,
    context: *const AstContext,
    fn_proto: std.zig.Ast.full.FnProto,
    active_param: u32,
) Self {
    var params = std.ArrayList(Param).init(allocator);
    {
        var it = fn_proto.iterate(&context.tree);
        while (it.next()) |param| {
            params.append(.{
                .name_token = if (param.name_token) |name_token| AstToken.init(&context.tree, name_token) else null,
                .type_node = AstNode.init(context, param.type_expr),
            }) catch unreachable;
        }
    }

    return Self{
        .allocator = allocator,
        .name_token = if (fn_proto.name_token) |name_token| AstToken.init(&context.tree, name_token) else null,
        .params = params.toOwnedSlice(),
        .active_param = active_param,
        .return_type_node = AstNode.init(context, fn_proto.ast.return_type),
    };
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.params);
}

pub fn getName(self: Self) []const u8 {
    return if (self.name_token) |name_token| name_token.getText() else "";
}

pub fn allocPrintSignature(self: Self, allocator: std.mem.Allocator) ![]const u8 {
    var signature = std.ArrayList(u8).init(allocator);
    const w = signature.writer();
    try w.print("fn {s}(", .{self.getName()});
    for (self.params) |param, i| {
        if (i > 0) {
            try w.print(", ", .{});
        }
        try w.print("{s}: {s}", .{
            param.getName(),
            param.type_node.getText(),
        });
    }
    try w.print(") {s};", .{self.return_type_node.getText()});
    return signature.toOwnedSlice();
}

pub fn fromNode(allocator: std.mem.Allocator, node: AstNode, active_param: u32) !Self {
    var buf: [2]u32 = undefined;
    switch (node.getChildren(&buf)) {
        // extern
        .fn_proto => |full| {
            return init(allocator, node.context, full, active_param);
        },
        else => {
            switch (node.getTag()) {
                .fn_decl => {
                    // fn
                    const fn_proto_node = AstNode.init(node.context, node.getData().lhs);
                    switch (fn_proto_node.getChildren(&buf)) {
                        .fn_proto => |fn_proto| {
                            return init(allocator, node.context, fn_proto, active_param);
                        },
                        else => {
                            return error.NoFnProto;
                        },
                    }
                },
                else => {
                    return error.FnDeclNorFnProto;
                },
            }
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

    const root = AstContainer.init(AstNode.init(context, 0)).?;

    const init_member = root.getMember("init").?;
    try std.testing.expectEqualStrings("init", init_member.name_token.?.getText());

    const signature = try fromNode(allocator, init_member.node, 0);
    defer signature.deinit();
    try std.testing.expectEqualStrings("init", signature.getName());
    try std.testing.expectEqualStrings("Self", signature.return_type_node.getText());
}
