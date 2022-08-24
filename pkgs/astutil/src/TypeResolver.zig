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
        container,
        fn_decl,
        fn_proto,
        literal,
        block,
        call,
    },
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

fn getReturnNode(node: AstNode) ?AstNode {
    if (node.getTag() == .@"return") {
        return AstNode.init(node.context, node.getData().lhs);
    }

    var it = AstNodeIterator.init(node.index);
    _ = async it.iterateAsync(&node.context.tree);
    while (it.value) |value| : (it.next()) {
        if (getReturnNode(AstNode.init(node.context, value))) |found| {
            return found;
        }
    }

    return null;
}

pub fn resolve(self: *Self, project: Project, node: AstNode) anyerror!AstType {
    // if (node.getParent()) |parent| {
    //     // call
    //     var buf: [2]u32 = undefined;
    //     switch (parent.getChildren(&buf)) {
    //         .call => {
    //             return self.resolve(project, parent);
    //         },
    //         else => {},
    //     }
    // }

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

    if (AstIdentifier.init(node)) |id| {
        // get_type from identifier
        const type_node = try id.getTypeNode(self.allocator, project);
        return self.resolve(project, type_node);
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
                return self.resolve(project, node);
            },
            // .container_field => |full| {
            //     return self.resolve(project, AstNode.init(node.context, full.ast.type_expr));
            // },
            .call => |call| {
                const fn_decl = try self.resolve(project, AstNode.init(node.context, call.ast.fn_expr));
                std.debug.assert(fn_decl.node.getTag() == .fn_decl);
                // const fn_node = AstNode.init(fn_decl.node.context, fn_decl.node.getData().lhs);
                // var buf2: [2]u32 = undefined;
                // switch (fn_node.getChildren(&buf2)) {
                //     .fn_proto => |fn_proto| {
                //         return try self.resolve(project, AstNode.init(fn_node.context, fn_proto.ast.return_type));
                //     },
                //     else => {
                //         return error.FnProtoNotFound;
                //     },
                // }
                // return AstType{
                //     .node = node,
                //     .kind = .call,
                // };
                const signature = try FunctionSignature.fromNode(self.allocator, fn_decl.node, 0);
                defer signature.deinit();
                return self.resolve(project, signature.return_type_node);
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
                return self.resolve(project, AstNode.init(node.context, ptr_type.ast.child_type));
            },
            // .block => {
            //     return AstType{
            //         .node = node,
            //         .kind = .block,
            //     };
            // },
            .fn_proto => {
                return AstType{
                    .node = node,
                    .kind = .fn_proto,
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
                            return self.resolve(project, type_node);
                        } else {
                            return error.NoDecl;
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
                                return self.resolve(project, signature.return_type_node);
                            }
                        }

                        return self.resolve(project, field);
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
                    //         , .enum_literal, .error_value => {
                    //             return AstType{
                    //                 .node = node,
                    //                 .kind = .literal,
                    //             };
                    //         },
                    .optional_type, .@"try", .@"orelse", .array_access => {
                        return self.resolve(project, AstNode.init(node.context, node.getData().lhs));
                    },
                    .error_union, .array_type => {
                        return self.resolve(project, AstNode.init(node.context, node.getData().rhs));
                    },
                    else => {},
                }
            },
        }

        std.debug.print("\n", .{});
        for (self.path.items) |item, i| {
            std.debug.print("[{}]{}: {s}: {s}\n", .{ i, item.getTag(), item.context.path.slice(), item.getText() });
        }
        unreachable;
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
    const resolved = try resolver.resolve(project, node);
    // for (resolver.path.items) |p, i| {
    //     std.debug.print("[{}] {s}: {s}\n", .{ i, p.context.path.slice(), p.getText() });
    // }
    try std.testing.expectEqual(resolved.kind, .{ .primitive = PrimitiveType.bool });
}
