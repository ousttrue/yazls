const std = @import("std");
const AstContext = @import("./AstContext.zig");
const Utf8Buffer = @import("./Utf8Buffer.zig");
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");
const ImportSolver = @import("./ImportSolver.zig");
const DocumentStore = @import("./DocumentStore.zig");
const Project = @import("./Project.zig");
const FixedPath = @import("./FixedPath.zig");
const Declaration = @import("./declaration.zig").Declaration;
const FunctionSignature = @import("./FunctionSignature.zig");
const PrimitiveType = @import("./primitives.zig").PrimitiveType;
const AstNodeIterator = @import("./AstNodeIterator.zig");
const AstIdentifier = @import("./AstIdentifier.zig");
const logger = std.log.scoped(.TypeResolver);
const Self = @This();

pub const AstType = struct {
    node: AstNode,
    kind: union(enum) {
        primitive: PrimitiveType,
        string_literal,
        enum_literal,
        error_value,
        container,
        fn_decl,
        fn_proto,
        literal,
        block,
        call,
        struct_init,
    },

    pub fn allocPrint(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).init(allocator);
        const w = buf.writer();

        switch (self.kind) {
            .primitive => |prim| {
                try w.print("{s}", .{@tagName(prim)});
            },
            else => {
                const text = try self.node.allocPrint(allocator);
                defer allocator.free(text);
                try w.print("[{s}] {s}", .{ @tagName(self.kind), text });
            },
        }

        return buf.toOwnedSlice();
    }
};

allocator: std.mem.Allocator,
path: std.ArrayList(AstNode),

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .path = std.ArrayList(AstNode).init(allocator),
    };
}

pub fn deinit(self: Self) void {
    self.path.deinit();
}

fn contains(items: []const AstNode, find: AstNode) bool {
    for (items) |item| {
        if (item.index == find.index) {
            return true;
        }
    }
    return false;
}

fn getReturnNode(node: AstNode, is_container_decl: bool) ?AstNode {
    if (node.getTag() == .@"return") {
        const lhs = AstNode.init(node.context, node.getData().lhs);
        if (is_container_decl) {
            if (lhs.isChildrenTagName("container_decl")) {
                return lhs;
            }
        } else {
            if (!lhs.isChildrenTagName("container_decl")) {
                return lhs;
            }
        }
    }

    var it = AstNodeIterator.init(node.index);
    _ = async it.iterateAsync(&node.context.tree);
    while (it.value) |value| : (it.next()) {
        if (getReturnNode(AstNode.init(node.context, value), is_container_decl)) |found| {
            return found;
        }
    }

    return null;
}

pub fn resolve(self: *Self, project: Project, node: AstNode, param_token: ?AstToken) anyerror!AstType {
    // debug
    if (self.path.items.len >= 100 or contains(self.path.items, node)) {
        std.debug.print("\n", .{});
        for (self.path.items) |item, i| {
            if (std.meta.eql(item, node)) {
                std.debug.print("<{}> {s}: {} {s}\n", .{ i, item.context.path.slice(), item.getTag(), item.getText() });
            } else {
                std.debug.print("[{}] {s}: {} {s}\n", .{ i, item.context.path.slice(), item.getTag(), item.getText() });
            }
        }
        unreachable;
    }
    try self.path.append(node);

    if (AstIdentifier.init(node, param_token)) |id| {
        // get_type from identifier
        switch (try id.getTypeNode(self.allocator, project)) {
            .primitive => |primitive| {
                return AstType{
                    .node = node,
                    .kind = .{ .primitive = primitive },
                };
            },
            .literal => |literal| {
                switch (literal) {
                    .@"true", .@"false" => {
                        return AstType{
                            .node = node,
                            .kind = .{ .primitive = PrimitiveType.bool },
                        };
                    },
                    .@"null", .@"undefined" => {
                        logger.err("type? {s}", .{node.getText()});
                        return error.NullValue;
                    },
                }
            },
            .node => |type_node| {
                return self.resolve(project, type_node, null);
            },
        }
    } else {
        // type node
        var buf: [2]u32 = undefined;
        switch (node.getChildren(&buf)) {
            .container_decl => {
                return AstType{
                    .node = node,
                    .kind = .container,
                };
            },
            .var_decl => {
                return self.resolve(project, node, null);
            },
            .call => |call| {
                const fn_decl = try self.resolve(project, AstNode.init(node.context, call.ast.fn_expr), null);
                std.debug.assert(fn_decl.node.getTag() == .fn_decl);
                const signature = try FunctionSignature.fromNode(self.allocator, fn_decl.node, 0);
                defer signature.deinit();
                const resolved = try self.resolve(project, signature.return_type_node, null);
                switch (resolved.kind) {
                    .primitive => |prim| {
                        if (prim == PrimitiveType.type) {
                            if (getReturnNode(fn_decl.node, true)) |type_type| {
                                logger.err("getReturnNode => {}: {s}", .{ type_type.getTag(), type_type.getText() });
                                return self.resolve(project, type_type, null);
                            } else if (getReturnNode(fn_decl.node, false)) |type_type| {
                                logger.err("getReturnNode => {}: {s}", .{ type_type.getTag(), type_type.getText() });
                                return self.resolve(project, type_type, null);
                            } else {
                                return error.NoTypeForType;
                            }
                        }
                    },
                    else => {},
                }
                return resolved;
            },
            .builtin_call => {
                const builtin_name = node.getMainToken().getText();
                if (std.mem.eql(u8, builtin_name, "@import")) {
                    if (try project.resolveImport(node)) |imported| {
                        return AstType{
                            .node = imported,
                            .kind = .container,
                        };
                    } else {
                        return error.FailImport;
                    }
                } else if (std.mem.eql(u8, builtin_name, "@This")) {
                    //
                    if (node.getContainerNodeForThis()) |container| {
                        return AstType{
                            .node = container,
                            .kind = .container,
                        };
                    } else {
                        return error.NoConainerDecl;
                    }
                } else if (std.mem.eql(u8, builtin_name, "@cImport")) {
                    const imported = try project.resolveCImport();
                    return AstType{
                        .node = imported,
                        .kind = .container,
                    };
                } else {
                    logger.err("{s}", .{builtin_name});
                    return error.UnknownBuiltin;
                }
            },
            .ptr_type => |ptr_type| {
                return self.resolve(project, AstNode.init(node.context, ptr_type.ast.child_type), null);
            },
            .block => {
                return AstType{
                    .node = node,
                    .kind = .block,
                };
            },
            .fn_proto => {
                return AstType{
                    .node = node,
                    .kind = .fn_proto,
                };
            },
            .@"switch" => |full| {
                return self.resolve(project, AstNode.init(node.context, full.ast.cond_expr), null);
            },
            .struct_init => {
                return AstType{
                    .node = node,
                    .kind = .struct_init,
                };
            },
            else => {
                switch (node.getTag()) {
                    .identifier => {
                        if (PrimitiveType.fromName(node.getText())) |primitive| {
                            return AstType{
                                .node = node,
                                .kind = .{ .primitive = primitive },
                            };
                        } else if (Declaration.find(node)) |decl| {
                            const type_node = try decl.getTypeNode();
                            return self.resolve(project, type_node, null);
                        } else {
                            return error.NoDeclForType;
                        }
                    },
                    .field_access => {
                        const field = try project.resolveFieldAccess(self.allocator, node);
                        if (std.meta.eql(field, node)) {
                            unreachable;
                        }
                        if (node.getParent()) |parent| {
                            if (parent.getTag() == .call) {
                                // field is fn_decl or fn_proto
                                const signature = try FunctionSignature.fromNode(self.allocator, field, 0);
                                defer signature.deinit();
                                return self.resolve(project, signature.return_type_node, null);
                            }
                        }

                        return self.resolve(project, field, null);
                    },
                    .fn_decl => {
                        return AstType{
                            .node = node,
                            .kind = .fn_decl,
                        };
                    },
                    .string_literal, .multiline_string_literal => {
                        return AstType{
                            .node = node,
                            .kind = .string_literal,
                        };
                    },
                    .enum_literal => {
                        return AstType{
                            .node = node,
                            .kind = .enum_literal,
                        };
                    },
                    .error_value => {
                        return AstType{
                            .node = node,
                            .kind = .error_value,
                        };
                    },
                    .optional_type, .@"try", .@"orelse", .array_access => {
                        return self.resolve(project, AstNode.init(node.context, node.getData().lhs), null);
                    },
                    .error_union, .array_type => {
                        return self.resolve(project, AstNode.init(node.context, node.getData().rhs), null);
                    },
                    else => {},
                }
            },
        }

        std.debug.print("\n", .{});
        for (self.path.items) |item, i| {
            std.debug.print("[{}]{}: {s}: {s}\n", .{ i, item.getTag(), item.context.path.slice(), item.getText() });
        }
        return TypeCannotResolved;
    }
}

test {
    const source =
        \\const std = @import("std");
        \\_ = std.mem.eql(u8, "a", "b");
    ;
    const allocator = std.testing.allocator;
    const text: [:0]const u8 = try allocator.dupeZ(u8, source);
    defer allocator.free(text);
    const line_heads = try Utf8Buffer.allocLineHeads(allocator, text);
    defer allocator.free(line_heads);
    const context = try AstContext.new(allocator, .{}, text, line_heads);
    defer context.delete();

    std.debug.print("\n", .{});

    const mem = AstToken.init(&context.tree, 14);
    try std.testing.expectEqualStrings("eql", mem.getText());
    const node = AstNode.fromTokenIndex(context, mem.index);
    try std.testing.expectEqual(node.getTag(), std.zig.Ast.Node.Tag.field_access);

    var import_solver = ImportSolver.init(allocator);
    defer import_solver.deinit();

    const zig = try FixedPath.findZig(allocator);
    try import_solver.push("std", zig.parent().?.child("lib/std/std.zig"));

    var store = DocumentStore.init(allocator);
    defer store.deinit();
    const project = Project.init(import_solver, &store);
    var resolver = init(allocator);
    defer resolver.deinit();

    std.debug.print("node: {} '{s}'\n", .{ node.getTag(), node.getText() });
    const resolved = try resolver.resolve(project, node, mem);
    // for (resolver.path.items) |p, i| {
    //     std.debug.print("[{}] {s}: {s}\n", .{ i, p.context.path.slice(), p.getText() });
    // }
    try std.testing.expectEqual(resolved.kind, .fn_decl);
}
