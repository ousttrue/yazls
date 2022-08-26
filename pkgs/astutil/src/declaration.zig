//! search name_token in the source file.
const std = @import("std");
const Ast = std.zig.Ast;
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");
const AstContext = @import("./AstContext.zig");
const Project = @import("./Project.zig");
const PrimitiveType = @import("./primitives.zig").PrimitiveType;
const logger = std.log.scoped(.Declaration);

pub const LocalVariable = struct {
    node: AstNode, // var_decl, if, while, switch_case, fn_proto
    variable: union(enum) {
        var_decl,
        if_payload,
        while_payload,
        switch_case_payload,
        param: u32,
    },
    name_token: AstToken,

    pub fn getTypeNode(self: LocalVariable) !AstNode {
        const context = self.node.context;
        var buf: [2]u32 = undefined;
        const children = self.node.getChildren(&buf);
        switch (self.variable) {
            .var_decl => {
                switch (children) {
                    .var_decl => |full| {
                        if (full.ast.type_node != 0) {
                            return AstNode.init(context, full.ast.type_node);
                        } else if (full.ast.init_node != 0) {
                            return AstNode.init(context, full.ast.init_node);
                        } else {
                            return error.VarDeclHasNoTypeNode;
                        }
                    },
                    else => {
                        @panic("not var_decl");
                    },
                }
            },
            .if_payload => {
                switch (children) {
                    .@"if" => |full| {
                        return AstNode.init(context, full.ast.cond_expr);
                    },
                    else => {
                        @panic("not if");
                    },
                }
            },
            .while_payload => {
                switch (children) {
                    .@"while" => |full| {
                        return AstNode.init(context, full.ast.cond_expr);
                    },
                    else => {
                        @panic("not while");
                    },
                }
            },
            .switch_case_payload => {
                switch (children) {
                    .switch_case => {
                        if (self.node.getParent()) |parent| {
                            var buf2: [2]u32 = undefined;
                            switch (parent.getChildren(&buf2)) {
                                .@"switch" => |full| {
                                    return AstNode.init(context, full.ast.cond_expr);
                                },
                                else => {
                                    @panic("not switch");
                                },
                            }
                        } else {
                            return error.NoParent;
                        }
                    },
                    else => {
                        @panic("not switch_case");
                    },
                }
            },
            .param => |index| {
                switch (children) {
                    .fn_proto => |fn_proto| {
                        var it = fn_proto.iterate(&context.tree);
                        var i: u32 = 0;
                        while (it.next()) |param| : (i += 1) {
                            if (i == index) {
                                return AstNode.init(context, param.type_expr);
                            }
                        }
                        return error.NoParam;
                    },
                    else => {
                        @panic("not fn_proto");
                    },
                }
            },
        }
    }
};

pub const ContainerDecl = struct {
    container: AstNode,
    member: union(enum) {
        var_decl: AstNode,
        field: AstNode,
        fn_decl: AstNode,
        // test_decl: AstNode,
    },
    name_token: AstToken,

    pub fn getTypeNode(self: ContainerDecl) !AstNode {
        const context = self.container.context;
        var buf: [2]u32 = undefined;
        switch (self.member) {
            .var_decl => |node| {
                switch (node.getChildren(&buf)) {
                    .var_decl => |full| {
                        if (full.ast.type_node != 0) {
                            return AstNode.init(context, full.ast.type_node);
                        } else if (full.ast.init_node != 0) {
                            return AstNode.init(context, full.ast.init_node);
                        } else {
                            return error.VarDeclHasNoTypeNode;
                        }
                    },
                    else => {
                        @panic("not var_decl");
                    },
                }
            },
            .field => |node| {
                switch (node.getChildren(&buf)) {
                    .container_field => |full| {
                        return AstNode.init(context, full.ast.type_expr);
                    },
                    else => {
                        @panic("not container_field");
                    },
                }
            },
            .fn_decl => |node| {
                return node;
            },
        }
    }
};

pub const Declaration = union(enum) {
    const Self = @This();
    // var | const, payload, param
    local: LocalVariable,
    // container member. var | const, field, fn
    container: ContainerDecl,
    // u32, bool, ... etc
    primitive: PrimitiveType,

    /// find local variable in from block scope
    pub fn findFromBlockNode(scope: AstNode, symbol: []const u8) ?Self {
        const tree = &scope.context.tree;
        var buffer: [2]u32 = undefined;
        switch (scope.getChildren(&buffer)) {
            .block => |block| {
                for (block.ast.statements) |statement| {
                    const statement_node = AstNode.init(scope.context, statement);
                    var buffer2: [2]u32 = undefined;
                    switch (statement_node.getChildren(&buffer2)) {
                        .var_decl => {
                            const name_token = statement_node.getMainToken().getNext();
                            if (std.mem.eql(u8, name_token.getText(), symbol)) {
                                return Self{ .local = .{
                                    .node = statement_node,
                                    .variable = .var_decl,
                                    .name_token = name_token,
                                } };
                            }
                        },
                        else => {},
                    }
                }
            },
            .@"if" => |full| {
                if (full.payload_token) |payload_token| {
                    const name_token = AstToken.init(tree, payload_token);
                    if (std.mem.eql(u8, name_token.getText(), symbol)) {
                        return Self{
                            .local = .{
                                .node = scope,
                                .variable = .if_payload,
                                .name_token = name_token,
                            },
                        };
                    }
                }
            },
            .@"while" => |full| {
                if (full.payload_token) |payload_token| {
                    const name_token = AstToken.init(tree, payload_token);
                    if (std.mem.eql(u8, name_token.getText(), symbol)) {
                        return Self{
                            .local = .{
                                .node = scope,
                                .variable = .while_payload,
                                .name_token = name_token,
                            },
                        };
                    }
                }
            },
            .switch_case => |full| {
                if (full.payload_token) |payload_token| {
                    const name_token = AstToken.init(tree, payload_token);
                    if (std.mem.eql(u8, name_token.getText(), symbol)) {
                        return Self{
                            .local = .{
                                .node = scope,
                                .variable = .switch_case_payload,
                                .name_token = name_token,
                            },
                        };
                    }
                }
            },
            else => {
                switch (scope.getTag()) {
                    .fn_decl => {
                        const fn_proto_node = AstNode.init(scope.context, scope.getData().lhs);
                        var buffer2: [2]u32 = undefined;
                        switch (fn_proto_node.getChildren(&buffer2)) {
                            .fn_proto => |fn_proto| {
                                var params = fn_proto.iterate(tree);
                                var i: u32 = 0;
                                while (params.next()) |param| : (i += 1) {
                                    if (param.name_token) |name_token_index| {
                                        const name_token = AstToken.init(tree, name_token_index);
                                        if (std.mem.eql(u8, name_token.getText(), symbol)) {
                                            return Self{
                                                .local = .{
                                                    .node = fn_proto_node,
                                                    .variable = .{ .param = i },
                                                    .name_token = name_token,
                                                },
                                            };
                                        }
                                    }
                                }
                            },
                            else => {
                                unreachable;
                            },
                        }
                    },
                    else => {},
                }
            },
        }
        return null;
    }

    /// find declaration from container scope
    pub fn findFromContainerNode(scope: AstNode, symbol: []const u8) ?Self {
        const tree = &scope.context.tree;
        var buffer: [2]u32 = undefined;
        switch (scope.getChildren(&buffer)) {
            .container_decl => |container_decl| {
                for (container_decl.ast.members) |member| {
                    const member_node = AstNode.init(scope.context, member);
                    var buf2: [2]u32 = undefined;
                    switch (member_node.getChildren(&buf2)) {
                        .var_decl => {
                            const name_token = member_node.getMainToken().getNext();
                            if (std.mem.eql(u8, name_token.getText(), symbol)) {
                                return Self{
                                    .container = .{
                                        .container = scope,
                                        .member = .{ .var_decl = member_node },
                                        .name_token = name_token,
                                    },
                                };
                            }
                        },
                        .container_field => {},
                        else => {
                            switch (member_node.getTag()) {
                                .fn_decl => {
                                    const fn_proto_node = AstNode.init(scope.context, member_node.getData().lhs);
                                    var buf3: [2]u32 = undefined;
                                    switch (fn_proto_node.getChildren(&buf3)) {
                                        .fn_proto => |fn_proto| {
                                            if (fn_proto.name_token) |name_token_index| {
                                                const name_token = AstToken.init(tree, name_token_index);
                                                if (std.mem.eql(u8, name_token.getText(), symbol)) {
                                                    return Self{
                                                        .container = .{
                                                            .container = scope,
                                                            .member = .{ .fn_decl = member_node },
                                                            .name_token = name_token,
                                                        },
                                                    };
                                                }
                                            }
                                        },
                                        else => {},
                                    }
                                },
                                .test_decl => {},
                                else => {
                                    logger.debug("unknown: {}", .{member_node.getTag()});
                                },
                            }
                        },
                    }
                }
            },
            else => {},
        }
        return null;
    }

    pub fn find(node: AstNode) ?Self {
        if (node.getTag() != .identifier) {
            return null;
        }
        const symbol = node.getMainToken().getText();

        // from block
        {
            var it = node.parentIterator();
            while (it.current) |current| : (it.next()) {
                if (findFromBlockNode(current, symbol)) |local| {
                    return local;
                }
                if (current.getTag() == .fn_decl) {
                    break;
                }
                var buf: [2]u32 = undefined;
                if (current.getChildren(&buf) == .container_decl) {
                    break;
                }
            }
        }

        // from container
        {
            var it = node.parentIterator();
            while (it.current) |current| : (it.next()) {
                if (findFromContainerNode(current, symbol)) |decl| {
                    return decl;
                }
                if (findFromBlockNode(current, symbol)) |local| {
                    return local;
                }
            }
        }

        return null;
    }

    pub fn getTypeNode(self: Self) !AstNode {
        return switch (self) {
            .local => |local| try local.getTypeNode(),
            .container => |container| try container.getTypeNode(),
            .primitive => error.Primitive,
        };
    }

    pub fn allocPrint(
        self: Self,
        allocator: std.mem.Allocator,
    ) anyerror![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const w = buffer.writer();

        switch (self) {
            .local => {
                try w.print("[local]", .{});
            },
            .container => {
                try w.print("[container]", .{});
            },
            .primitive => {
                try w.print("[primitive]", .{});
            },
            // .var_decl => |full| {
            //     // getType: var decl type part => eval expression
            //     _ = full;
            //     // const var_type = VarType.fromVarDecl(self.context, full);
            //     // const info = try var_type.allocPrint(allocator);
            //     // defer allocator.free(info);
            //     try w.print("[var_decl]", .{});
            // },
            // .if_payload => |full| {
            //     // getType: eval expression
            //     _ = full;
            //     try w.print("[if_payload]", .{});
            // },
            // .while_payload => |full| {
            //     // getType: eval expression
            //     _ = full;
            //     try w.print("[while_payload]", .{});
            // },
            // .switch_case_payload => |full| {
            //     // getType: union type part
            //     _ = full;
            //     try w.print("[swtich_case_payload]", .{});
            // },
            // .param => |full| {
            //     _ = full;
            //     // getType: param decl
            //     // const var_type = try VarType.fromParam(project, self.context, full);
            //     // const info = try var_type.allocPrint(allocator);
            //     // defer allocator.free(info);
            //     // try w.print("[param] {s}", .{info});
            //     try w.print("[param]", .{});
            // },
            // .fn_decl => {
            //     try w.print("[global] fn", .{});
            // },
        }

        return buffer.items;
    }
};
