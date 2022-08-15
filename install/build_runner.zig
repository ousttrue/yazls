///! This is a modified build runner to extract information out of build.zig
///! Modified from the std.special.build_runner
const root = @import("@build@");
const std = @import("std");
const fmt = std.fmt;
const io = std.io;
const log = std.log;
const process = std.process;
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;
const InstallArtifactStep = std.build.InstallArtifactStep;
const LibExeObjStep = std.build.LibExeObjStep;
const ArrayList = std.ArrayList;

const NamePath = struct {
    name: []const u8,
    path: []const u8,
};

const Object = struct {
    name: []const u8,
    entry_point: []const u8,
    compile_options: [][]const u8,
};

const Project = struct {
    // LibExeObjStep
    objects: []const Object,
    // Pkg
    packages: []const NamePath,
};

const Aggregator = struct {
    const Self = @This();

    arena: *std.heap.ArenaAllocator,
    objects: std.StringArrayHashMap(Object),
    packages: std.StringHashMap([]const u8),

    fn init(arena: *std.heap.ArenaAllocator) Self {
        return Self{
            .arena = arena,
            .objects = std.StringArrayHashMap(Object).init(arena.allocator()),
            .packages = std.StringHashMap([]const u8).init(arena.allocator()),
        };
    }

    fn processStep(
        self: *Self,
        step: *std.build.Step,
    ) anyerror!void {
        // if (step.cast(InstallArtifactStep)) |install_exe| {
        //     try self.processObject(install_exe.artifact);
        // } else
        if (step.cast(LibExeObjStep)) |exe| {
            try self.processObject(exe);
        } else {
            for (step.dependencies.items) |unknown_step| {
                try self.processStep(unknown_step);
            }
        }
    }

    fn processObject(self: *Self, exe: *const LibExeObjStep) !void {
        if (exe.root_src) |root_src| {
            if (fileSourcePath(root_src)) |path| {
                var compile_options = std.ArrayList([]const u8).init(self.arena.allocator());
                for (exe.include_dirs.items) |item| {
                    try compile_options.append(try std.fmt.allocPrint(
                        self.arena.allocator(),
                        "-I{s}",
                        .{item.raw_path},
                    ));
                }
                for (exe.c_macros.items) |item| {
                    try compile_options.append(try std.fmt.allocPrint(
                        self.arena.allocator(),
                        "-D{s}",
                        .{item},
                    ));
                }
                try self.objects.put(exe.name, .{
                    .name = exe.name,
                    .entry_point = path,
                    .compile_options = compile_options.items,
                });
            }
        }
        for (exe.packages.items) |pkg| {
            try self.processPackage(pkg);
        }
    }

    fn processPackage(self: *Self, pkg: Pkg) anyerror!void {
        if (fileSourcePath(pkg.source)) |path| {
            try self.packages.put(pkg.name, path);
        }
        if (pkg.dependencies) |dependencies| {
            for (dependencies) |dep| {
                try self.processPackage(dep);
            }
        }
    }

    /// write json
    fn writeTo(self: Self, w: anytype, is_debug: bool) !void {
        std.log.debug("{}", .{is_debug});
        var option = std.json.StringifyOptions{ .emit_null_optional_fields = false };
        if (is_debug) {
            option.whitespace = .{};
        }

        var packages = std.ArrayList(NamePath).init(self.arena.allocator());
        defer packages.deinit();
        {
            var it = self.packages.iterator();
            while (it.next()) |entry| {
                try packages.append(.{
                    .name = entry.key_ptr.*,
                    .path = entry.value_ptr.*,
                });
            }
        }

        var objects = std.ArrayList(Object).init(self.arena.allocator());
        defer objects.deinit();
        {
            var it = self.objects.iterator();
            while (it.next()) |entry| {
                try objects.append(entry.value_ptr.*);
            }
        }

        try std.json.stringify(Project{
            .objects = objects.items,
            .packages = packages.items,
        }, option, w);
    }
};

///
/// path_to_zig/zig.exe run path_to_zls/zig-out/bin/build_runner.zig --pkg-begin @build@ path_to_project/build.zig --pkg-end -- arg1 arg2 arg3 arg4
///
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    // skip my own exe name
    var arg_idx: usize = 1;

    const zig_exe = nextArg(args, &arg_idx) orelse {
        log.warn("Expected first argument to be path to zig compiler\n", .{});
        return error.InvalidArgs;
    };
    const build_root = nextArg(args, &arg_idx) orelse {
        log.warn("Expected second argument to be build root directory path\n", .{});
        return error.InvalidArgs;
    };
    var cache_root: []const u8 = "zig-cache";
    var global_cache_root: []const u8 = "YAZLS_DONT_CARE";

    if (nextArg(args, &arg_idx)) |arg| {
        cache_root = arg;
    }
    if (nextArg(args, &arg_idx)) |arg| {
        global_cache_root = arg;
    }

    const builder = try Builder.create(
        allocator,
        zig_exe,
        build_root,
        cache_root,
        global_cache_root,
    );

    defer builder.destroy();

    builder.resolveInstallPrefix(null, Builder.DirList{});
    try runBuild(builder);

    // TODO: We currently add packages from every LibExeObj step that the install step depends on.
    //       Should we error out or keep one step or something similar?
    // We also flatten them, we should probably keep the nested structure.
    var aggregator = Aggregator.init(&arena);

    for (builder.top_level_steps.items) |tls| {
        for (tls.step.dependencies.items) |step| {
            try aggregator.processStep(step);
        }
    }

    try aggregator.writeTo(io.getStdOut().writer(), true);
}

fn fileSourcePath(source: std.build.FileSource) ?[]const u8 {
    return switch (source) {
        .path => |path| path,
        .generated => |generated| generated.path,
    };
}

fn runBuild(builder: *Builder) anyerror!void {
    switch (@typeInfo(@typeInfo(@TypeOf(root.build)).Fn.return_type.?)) {
        .Void => root.build(builder),
        .ErrorUnion => try root.build(builder),
        else => @compileError("expected return type of build to be 'void' or '!void'"),
    }
}

fn nextArg(args: [][]const u8, idx: *usize) ?[]const u8 {
    if (idx.* >= args.len) return null;
    defer idx.* += 1;
    return args[idx.*];
}
