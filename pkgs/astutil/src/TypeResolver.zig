const std = @import("std");
const AstContext = @import("./AstContext.zig");
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");
const ImportSolver = @import("./ImportSolver.zig");
const DocumentStore = @import("./DocumentStore.zig");
const Project = @import("./Project.zig");
const FixedPath = @import("./FixedPath.zig");
const Self = @This();

path: std.ArrayList(AstNode),

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .path = std.ArrayList(AstNode).init(allocator),
    };
}

pub fn deinit(self: Self) void {
    self.path.deinit();
}

pub fn resolve(self: *Self, project: Project, node: AstNode) ![]const u8 {
    var current = node;
    var i: u32 = 0;
    while (true) : (i += 1) {
        if (i > 100) {
            for (self.path.items) |p, j| {
                std.debug.print("[{}] {s}: {s}\n", .{ j, p.context.path.slice(), p.getText() });
            }
            unreachable;
        }
        try self.path.append(current);
        switch (current.getTag()) {
            .field_access => {
                const field = try project.resolveFieldAccess(current);
                if (field.index == current.index) {
                    break;
                }
                current = field;
            },
            else => {
                const type_node = try project.resolveType(current);
                if (type_node.index == current.index) {
                    break;
                }
                current = type_node;
            },
        }
    }
    return current.getText();
}

test {
    const source =
        \\const std = @import("std");
        \\_ = std.mem.eql(u8, "a", "b");
    ;
    const allocator = std.testing.allocator;
    const text: [:0]const u8 = try allocator.dupeZ(u8, source);
    defer allocator.free(text);
    const context = try AstContext.new(allocator, .{}, text);
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
    for (resolver.path.items) |p, i| {
        std.debug.print("[{}] {s}: {s}\n", .{ i, p.context.path.slice(), p.getText() });
    }
    try std.testing.expectEqualStrings("bool", resolved);
}
