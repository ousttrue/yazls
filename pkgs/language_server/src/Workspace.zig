const std = @import("std");
const astutil = @import("astutil");
const FixedPath = astutil.FixedPath;
const ImportSolver = astutil.ImportSolver;
const DocumentStore = astutil.DocumentStore;
const Project = astutil.Project;
const ZigEnv = @import("./ZigEnv.zig");
const logger = std.log.scoped(.Workspace);
const Self = @This();

path: FixedPath,
import_solver: ImportSolver,
store: DocumentStore,

pub fn init(allocator: std.mem.Allocator, path: FixedPath, zigenv: ZigEnv) !Self {
    var self = Self{
        .path = path,
        .import_solver = ImportSolver.init(allocator),
        .store = DocumentStore.init(allocator),
    };

    logger.info("new: {s}", .{path.slice()});

    // initialize import_solver
    self.import_solver.push("std", zigenv.std_path) catch unreachable;
    try zigenv.initPackagesAndCImport(allocator, &self.import_solver, path);

    return self;
}

pub fn deinit(self: *Self) void {
    self.import_solver.deinit();
    self.store.deinit();
}

pub fn project(self: *Self) Project {
    return .{
        .import_solver = self.import_solver,
        .store = &self.store,
    };
}
