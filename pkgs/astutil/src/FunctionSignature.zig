const std = @import("std");
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");
const AstContext = @import("./AstContext.zig");
const AstContainer = @import("./AstContainer.zig");

const Arg = struct {
    name: []const u8,
    document: []const u8,
};

const Self = @This();

name: []const u8,
document: []const u8,
args: std.ArrayList(Arg),
return_type: []const u8,
active_param: u32 = 0,

pub fn init(
    allocator: std.mem.Allocator,
    name: []const u8,
    document: []const u8,
    return_type: []const u8,
    active_param: u32,
) Self {
    return Self{
        .name = name,
        .document = document,
        .args = std.ArrayList(Arg).init(allocator),
        .return_type = return_type,
        .active_param = active_param,
    };
}

pub fn deinit(self: Self) void {
    self.args.deinit();
}

fn fromFnProto(
    allocator: std.mem.Allocator,
    context: *const AstContext,
    fn_proto: std.zig.Ast.full.FnProto,
    active_param: u32,
) !Self {
    const return_type_node = AstNode.init(context, fn_proto.ast.return_type);

    // signature
    var signature = std.ArrayList(u8).init(allocator);
    const w = signature.writer();
    try w.print("fn {s}(", .{AstToken.init(&context.tree, fn_proto.name_token.?).getText()});
    {
        var it = fn_proto.iterate(&context.tree);
        var i: u32 = 0;
        while (it.next()) |param| : (i += 1) {
            if (i > 0) {
                try w.print(", ", .{});
            }
            try w.print("{s}: {s}", .{
                AstToken.init(&context.tree, param.name_token.?).getText(),
                AstNode.init(context, param.type_expr).getText(),
            });
        }
    }
    try w.print(") {s};", .{return_type_node.getText()});
    //
    //
    var self = init(allocator, signature.items, "", "", active_param);
    {
        var it = fn_proto.iterate(&context.tree);
        while (it.next()) |param| {
            try self.args.append(.{
            .name = AstToken.init(&context.tree, param.name_token.?).getText(),
            .document = AstNode.init(context, param.type_expr).getText(),
            });
        }
    }
    return self;
}

pub fn fromNode(allocator: std.mem.Allocator, node: AstNode, active_param: u32) !Self {
    var buf: [2]u32 = undefined;
    switch (node.getChildren(&buf)) {
        // extern
        .fn_proto => |full| {
            return fromFnProto(allocator, node.context, full, active_param);
        },
        else => {
            switch (node.getTag()) {
                .fn_decl => {
                    // fn
                    const fn_proto_node = AstNode.init(node.context, node.getData().lhs);
                    const fn_proto = fn_proto_node.getFnProto(&buf) orelse return error.NoFnProto;
                    return fromFnProto(allocator, node.context, fn_proto, active_param);
                },
                else => {
                    return error.FnDeclNorFnProto;
                },
            }
        },
    }
}

pub fn allocPrint(self: Self, allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const w = buf.writer();

    try w.print("## {s}\n\n", .{self.name});

    if (self.document.len > 0) {
        try w.print("{s}", .{self.document});
    }

    return buf.toOwnedSlice();
}

test {
    const source = @embedFile("test_source.zig");
    const allocator = std.testing.allocator;
    const text: [:0]const u8 = try allocator.dupeZ(u8, source);
    defer allocator.free(text);
    const context = try AstContext.new(allocator, .{}, text);
    defer context.delete();

    const root = AstContainer.init(AstNode.init(context, 0));
    _ = root;
    // const init = root.getMember("init").?;
    // const signature = Self.init(init.node);

    // try std.testing.expectEqual(root.getMember("Self").?.kind, .var_decl);
    // try std.testing.expectEqual(root.getMember("value").?.kind, .field);
    // try std.testing.expectEqual(root.getMember("\"empty_test\"").?.kind, .test_decl);
    // try std.testing.expectEqual(root.getMember("external_func").?.kind, .fn_proto);
}
