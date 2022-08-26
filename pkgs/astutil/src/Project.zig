const std = @import("std");
const ImportSolver = @import("./ImportSolver.zig");
const DocumentStore = @import("./DocumentStore.zig");
const Document = @import("./Document.zig");
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");
const AstContainer = @import("./AstContainer.zig");
const TypeResolver = @import("./TypeResolver.zig");
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

pub fn resolveFieldAccess(self: Self, allocator: std.mem.Allocator, node: AstNode) anyerror!AstNode {
    if (node.getTag() != .field_access) {
        return error.NotFieldAccess;
    }
    const data = node.getData();

    // lhs
    const lhs = AstNode.init(node.context, data.lhs);
    var buf: [2]u32 = undefined;
    const type_node = switch (lhs.getChildren(&buf)) {
        .call, .builtin_call => try self.resolveType(allocator, lhs),
        else => switch (lhs.getTag()) {
            .field_access => try self.resolveFieldAccess(allocator, lhs),
            .identifier => try self.resolveType(allocator, lhs),
            else => return error.UnknownLhs,
        },
    };

    // rhs
    const rhs = AstToken.init(&node.context.tree, data.rhs);
    if (AstContainer.init(type_node)) |container| {
        if (container.getMember(rhs.getText())) |member| {
            return try self.resolveType(allocator, member.node);
        }
    }

    logger.warn("member: {}.{s}", .{ lhs.getTag(), rhs.getText() });
    return error.FieldNotFound;
}

pub fn resolveType(self: Self, allocator: std.mem.Allocator, node: AstNode) !AstNode {
    var resolver = TypeResolver.init(allocator);
    defer resolver.deinit();
    const resolved = try resolver.resolve(self, node, null);
    return resolved.node;
}
