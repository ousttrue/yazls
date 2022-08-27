const std = @import("std");
const logger = std.log.scoped(.AstNodeSemantic);
const AstNode = @import("./AstNode.zig");

const Self = @This();

kind: union(enum) {
    varDecl: AstNode,
    fieldDecl: AstNode,
    fnProto: AstNode,
    blockVar: AstNode,
    structInit: AstNode,
},

pub fn init(node: AstNode) ?Self {
    var it = node.parentIterator();
    while (it.current) |current| : (it.next()) {
        if (current.index == 0) {
            // 編集中、不完全の場合など
            return null;
        }
        var buf: [2]u32 = undefined;
        switch (current.getChildren(&buf)) {
            .var_decl => return Self{
                .kind = .{ .varDecl = current },
            },
            .container_field => return Self{
                .kind = .{ .fieldDecl = current },
            },
            .fn_proto => return Self{
                .kind = .{ .fnProto = current },
            },
            .block => return Self{
                .kind = .{ .blockVar = current },
            },
            .struct_init => return Self{
                .kind = .{ .structInit = current },
            },
            else => {},
        }
    }

    logger.err("{s}", .{node.getText()});
    it = node.parentIterator();
    while (it.current) |current| : (it.next()) {
        logger.err("{}", .{current.getTag()});
    }
    unreachable;
}
