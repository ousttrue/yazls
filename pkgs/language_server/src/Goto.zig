const std = @import("std");
const astutil = @import("astutil");
const Project = astutil.Project;
const Document = astutil.Document;
const AstToken = astutil.AstToken;
const AstNode = astutil.AstNode;
const AstContainer = astutil.AstContainer;
const PathPosition = astutil.PathPosition;
const FixedPath = astutil.FixedPath;
const Declaration = astutil.Declaration;
const logger = std.log.scoped(.Goto);

fn gotoImport(project: Project, import_from: FixedPath, text: []const u8) ?PathPosition {
    if (project.import_solver.solve(import_from, text)) |path| {
        return PathPosition{ .path = path, .loc = .{ .start = 0, .end = 0 } };
    }
    return null;
}

pub fn getGoto(
    arena: *std.heap.ArenaAllocator,
    project: Project,
    doc: *Document,
    token: AstToken,
) !?PathPosition {
    const node = AstNode.fromTokenIndex(doc.ast_context, token.index);

    switch (token.getTag()) {
        .string_literal => {
            // goto import file
            return gotoImport(project, doc.path, token.getText());
        },
        .builtin => {
            if (std.mem.eql(u8, token.getText(), "@import")) {
                var buf: [2]u32 = undefined;
                switch (node.getChildren(&buf)) {
                    .builtin_call => |full| {
                        const param_node = AstNode.init(node.context, full.ast.params[0]);
                        return gotoImport(project, doc.path, param_node.getMainToken().getText());
                    },
                    else => {},
                }
            }
            return null;
        },
        .identifier => {
            var buf: [2]u32 = undefined;
            switch (node.getChildren(&buf)) {
                .var_decl => |var_decl| {
                    // to rhs
                    const init_node = AstNode.init(node.context, var_decl.ast.init_node);
                    // TODO: GetType
                    return PathPosition{ .path = doc.path, .loc = init_node.getMainToken().getLoc() };
                },
                else => {
                    switch (node.getTag()) {
                        .identifier => {
                            if (Declaration.find(node)) |decl| {
                                const text = try decl.allocPrint(arena.allocator());
                                logger.debug("{s}", .{text});
                                switch (decl) {
                                    .local => |local| {
                                        return PathPosition{ .path = doc.path, .loc = local.name_token.getLoc() };
                                    },
                                    .container => |container| {
                                        return PathPosition{ .path = doc.path, .loc = container.name_token.getLoc() };
                                    },
                                    .primitive => {
                                        return error.Primitive;
                                    },
                                }
                            } else {
                                return error.DeclNotFound;
                            }
                        },
                        .field_access => {
                            const type_node = try project.resolveFieldAccess(arena.allocator(), node);
                            return type_node.getPosition();
                        },
                        .fn_decl => {
                            return null;
                        },
                        .enum_literal => {
                            if (node.getParent()) |parent| {
                                switch (parent.getChildren(&buf)) {
                                    .switch_case => {
                                        if (parent.getParent()) |pp| {
                                            switch (pp.getChildren(&buf)) {
                                                .@"switch" => |full| {
                                                    const resolved = try project.resolveType(arena.allocator(), AstNode.init(node.context, full.ast.cond_expr));
                                                    if (AstContainer.init(resolved)) |container| {
                                                        if (container.getMember(node.getMainToken().getText())) |member| {
                                                            return member.node.gotoPosition();
                                                        }
                                                    }
                                                    return resolved.gotoPosition();
                                                },
                                                else => {},
                                            }
                                        } else {
                                            return error.NoParentParent;
                                        }
                                    },
                                    else => {},
                                }
                            } else {
                                return error.NoParent;
                            }
                        },
                        else => {
                            logger.debug("getGoto: unknown node tag: {s}", .{@tagName(node.getTag())});
                            return null;
                        },
                    }
                },
            }
        },
        else => {},
    }
    return null;
}
