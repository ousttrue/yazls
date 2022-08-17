const std = @import("std");
const ImportSolver = @import("./ImportSolver.zig");
const DocumentStore = @import("./DocumentStore.zig");
const Document = @import("./Document.zig");
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");
const AstContainer = @import("./AstContainer.zig");
const Declaration = @import("./declaration.zig").Declaration;
const logger = std.log.scoped(.Project);
const Self = @This();

import_solver: ImportSolver,
store: *DocumentStore,

pub fn init(import_solver: ImportSolver, store: *DocumentStore) Self {
    return Self{
        .import_solver = import_solver,
        .store = store,
    };
}

pub fn resolveCImport(self: Self) !AstNode {
    const path = self.import_solver.c_import orelse {
        return error.NoCImportPath;
    };
    if (try self.store.getOrLoad(path)) |doc| {
        // root node
        return AstNode.init(doc.ast_context, 0);
    } else {
        return error.DocumentNotFound;
    }
}

pub fn resolveImport(self: Self, node: AstNode) !?AstNode {
    var buf: [2]u32 = undefined;
    switch (node.getChildren(&buf)) {
        .builtin_call => |full| {
            if (std.mem.eql(u8, node.getMainToken().getText(), "@import")) {
                if (full.ast.params.len == 1) {
                    const text = AstNode.init(node.context, full.ast.params[0]).getMainToken().getText();
                    if (self.import_solver.solve(node.context.path, text)) |path| {
                        if (try self.store.getOrLoad(path)) |doc| {
                            // root node
                            return AstNode.init(doc.ast_context, 0);
                        } else {
                            return error.DocumentNotFound;
                        }
                    } else {
                        return error.FailPath;
                    }
                } else {
                    return error.InalidParams;
                }
            } else {
                return error.NotImport;
            }
        },
        else => {
            return error.NotBuiltinCall;
        },
    }
}

pub fn resolveFieldAccess(self: Self, node: AstNode) anyerror!AstNode {
    std.debug.assert(node.getTag() == .field_access);
    const data = node.getData();

    // lhs
    const lhs = AstNode.init(node.context, data.lhs);
    var buf: [2]u32 = undefined;
    const type_node = switch (lhs.getChildren(&buf)) {
        .call, .builtin_call => try self.resolveType(lhs),
        else => switch (lhs.getTag()) {
            .field_access => try self.resolveFieldAccess(lhs),
            .identifier => try self.resolveType(lhs),
            else => return error.UnknownLhs,
        },
    };

    // rhs
    const rhs = AstToken.init(&node.context.tree, data.rhs);
    if (AstContainer.init(type_node).getMember(rhs.getText())) |member| {
        return try self.resolveType(member.node);
    } else {
        logger.warn("member: {}.{s}", .{ lhs.getTag(), rhs.getText() });
        return error.FieldNotFound;
    }
}

pub fn resolveType(self: Self, node: AstNode) anyerror!AstNode {
    var buf: [2]u32 = undefined;
    switch (node.getChildren(&buf)) {
        .container_decl => {
            return node;
        },
        .var_decl => |var_decl| {
            if (var_decl.ast.init_node != 0) {
                return self.resolveType(AstNode.init(node.context, var_decl.ast.init_node));
            } else {
                return error.NoInit;
            }
        },
        .container_field => |full| {
            return self.resolveType(AstNode.init(node.context, full.ast.type_expr));
        },
        .builtin_call => {
            const builtin_name = node.getMainToken().getText();
            if (std.mem.eql(u8, builtin_name, "@import")) {
                if (try self.resolveImport(node)) |imported| {
                    return imported;
                } else {
                    return error.FailImport;
                }
            } else if (std.mem.eql(u8, builtin_name, "@This")) {
                //
                if (node.getContainerNodeForThis()) |container| {
                    return container;
                } else {
                    return error.NoConainerDecl;
                }
            } else if (std.mem.eql(u8, builtin_name, "@cImport")) {
                return try self.resolveCImport();
            } else {
                logger.err("{s}", .{builtin_name});
                return error.UnknownBuiltin;
            }
        },
        .ptr_type => |ptr_type| {
            return self.resolveType(AstNode.init(node.context, ptr_type.ast.child_type));
        },
        .call => |call| {
            const fn_decl = try self.resolveType(AstNode.init(node.context, call.ast.fn_expr));
            const fn_node = AstNode.init(fn_decl.context, fn_decl.getData().lhs);
            var buf2: [2]u32 = undefined;
            if (fn_node.getFnProto(&buf2)) |fn_proto| {
                return self.resolveType(AstNode.init(fn_node.context, fn_proto.ast.return_type));
            } else {
                return error.FnProtoNotFound;
            }
        },
        else => {
            switch (node.getTag()) {
                .identifier => {
                    if (Declaration.find(node)) |decl| {
                        const type_node = try decl.getTypeNode();
                        return self.resolveType(type_node);
                    } else {
                        return error.NoDecl;
                    }
                },
                .field_access => {
                    const field = try self.resolveFieldAccess(node);
                    return self.resolveType(field);
                },
                .optional_type, .@"try", .@"orelse", .array_access => {
                    return self.resolveType(AstNode.init(node.context, node.getData().lhs));
                },
                .error_union => {
                    return self.resolveType(AstNode.init(node.context, node.getData().rhs));
                },
                else => {
                    node.debugPrint();
                    return node;
                },
            }
        },
    }
}
