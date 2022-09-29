const std = @import("std");
const builtin = @import("builtin");
const astutil = @import("astutil");
// const known_folders = @import("known-folders");
const FixedPath = astutil.FixedPath;
const ImportSolver = astutil.ImportSolver;
const logger = std.log.scoped(.ZigEnv);

pub fn findZig(allocator: std.mem.Allocator) !?[]const u8 {
    const env_path = std.process.getEnvVarOwned(allocator, "PATH") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            return null;
        },
        else => return err,
    };
    defer allocator.free(env_path);

    const exe_extension = builtin.target.exeFileExt();
    const zig_exe = try std.fmt.allocPrint(allocator, "zig{s}", .{exe_extension});
    defer allocator.free(zig_exe);

    var it = std.mem.tokenize(u8, env_path, &[_]u8{std.fs.path.delimiter});
    while (it.next()) |path| {
        if (builtin.os.tag == .windows) {
            if (std.mem.indexOfScalar(u8, path, '/') != null) continue;
        }
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, zig_exe });
        defer allocator.free(full_path);

        if (!std.fs.path.isAbsolute(full_path)) continue;

        const file = std.fs.openFileAbsolute(full_path, .{}) catch continue;
        defer file.close();
        const stat = file.stat() catch continue;
        if (stat.kind == .Directory) continue;

        return try allocator.dupe(u8, full_path);
    }
    return null;
}

fn getZigLibAlloc(allocator: std.mem.Allocator, zig_exe_path: FixedPath) !FixedPath {
    // Use `zig env` to find the lib path
    const zig_env_result = try zig_exe_path.exec(allocator, &.{"env"});
    defer allocator.free(zig_env_result.stdout);
    defer allocator.free(zig_env_result.stderr);

    switch (zig_env_result.term) {
        .Exited => |exit_code| {
            if (exit_code == 0) {
                const Env = struct {
                    zig_exe: []const u8,
                    lib_dir: ?[]const u8,
                    std_dir: []const u8,
                    global_cache_dir: []const u8,
                    version: []const u8,
                    target: []const u8,
                };

                var stream = std.json.TokenStream.init(zig_env_result.stdout);
                var json_env = std.json.parse(
                    Env,
                    &stream,
                    .{ .allocator = allocator },
                ) catch {
                    logger.err("Failed to parse zig env JSON result", .{});
                    unreachable;
                };
                defer std.json.parseFree(Env, json_env, .{ .allocator = allocator });
                return FixedPath.fromFullpath(json_env.lib_dir.?);
            }
        },
        else => {
            logger.err("zig env invocation failed", .{});
        },
    }
    unreachable;
}

fn getZigBuiltinAlloc(
    allocator: std.mem.Allocator,
    zig_exe_path: FixedPath,
    config_dir: FixedPath,
) !FixedPath {
    const result = try zig_exe_path.exec(allocator, &.{
        "build-exe",
        "--show-builtin",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    var d = try std.fs.cwd().openDir(config_dir.slice(), .{});
    defer d.close();

    const f = try d.createFile("builtin.zig", .{});
    defer f.close();
    try f.writer().writeAll(result.stdout);

    var path = FixedPath.fromFullpath(config_dir.slice());
    path = path.child("builtin.zig");
    logger.info("{s}", .{path.slice()});

    return path;
}

fn getFullpath(dir: FixedPath, path: []const u8) FixedPath
{
    if(path[0] == '/' or path[0] == '\\')
    {
        return FixedPath.fromFullpath(path);
    }

    if(path[1] == ':')
    {
        // maybe with windows drive letter
        return FixedPath.fromFullpath(path);
    }

    return dir.child(path);
}

/// zig build-lib src/c.zig --z -I.
/// info(compilation): C import output: src\zig-cache\o\4cf7e05ea3dd9caa12de6a7fa9206deb\cimport.zig
const prefix = "info(compilation): C import output: ";
fn getZigCImport(
    allocator: std.mem.Allocator,
    zig_exe_path: FixedPath,
    compile_options: [][]const u8,
    root: FixedPath,
) !FixedPath {
    // chroot root
    const source = try std.fmt.allocPrint(allocator, "c.zig", .{});
    defer allocator.free(source);

    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();
    try args.appendSlice(&.{
        "build-lib",
        source,
        "-lc",
        "--verbose-cimport",
    });
    try args.appendSlice(compile_options);

    const result = try zig_exe_path.exec(allocator, args.items);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    var it = std.mem.split(u8, result.stderr, "\n");
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, prefix)) {
            logger.debug("{s}", .{line});
            return getFullpath(root, line[prefix.len..]);
        }
    }
    return error.NoCImport;
}

const Self = @This();

exe: FixedPath = .{},
lib: FixedPath = .{},
std_path: FixedPath = .{},
build_runner_path: FixedPath = .{},

pub fn init(allocator: std.mem.Allocator) !Self {
    // exe
    var zig_exe_path: FixedPath = .{};
    if (try findZig(allocator)) |exe| {
        defer allocator.free(exe);
        zig_exe_path = FixedPath.fromFullpath(exe);
    }
    logger.info("Using zig executable: {s}", .{zig_exe_path.slice()});

    // lib
    var zig_lib_path = try getZigLibAlloc(allocator, zig_exe_path);
    logger.info("Using zig lib path: {s}", .{zig_lib_path.slice()});

    // build_runner_path
    const exe_dir_path = try FixedPath.fromSelfExe();
    const build_runner_path = exe_dir_path.child("build_runner.zig");
    logger.info("Using build_runner_path: {s}", .{build_runner_path.slice()});

    return Self{
        .exe = zig_exe_path,
        .lib = zig_lib_path,
        .std_path = zig_lib_path.child("std/std.zig"),
        .build_runner_path = build_runner_path,
    };
}

pub fn spawnZigFmt(self: Self, allocator: std.mem.Allocator, src: []const u8) ![]const u8 {
    var process = std.ChildProcess.init(&[_][]const u8{ self.exe.slice(), "fmt", "--stdin" }, allocator);
    process.stdin_behavior = .Pipe;
    process.stdout_behavior = .Pipe;
    try process.spawn();
    try process.stdin.?.writeAll(src);
    process.stdin.?.close();
    process.stdin = null;
    const bytes = try process.stdout.?.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    switch (try process.wait()) {
        .Exited => |code| if (code == 0) {
            return bytes;
        } else {
            return error.ExitedNonZero;
        },
        else => {
            return error.ProcessError;
        },
    }
}

pub fn runBuildRunner(self: Self, allocator: std.mem.Allocator, build_file_path: FixedPath) ![]const u8 {
    const directory_path = build_file_path.parent().?;
    const zig_run_result = try self.exe.exec(allocator, &.{
        "run",
        self.build_runner_path.slice(),
        "--pkg-begin",
        "@build@",
        build_file_path.slice(),
        "--pkg-end",
        "--",
        self.exe.slice(),
        directory_path.slice(),
    });
    defer allocator.free(zig_run_result.stderr);
    return switch (zig_run_result.term) {
        .Exited => |exit_code| if (exit_code == 0)
            zig_run_result.stdout
        else
            return error.RunFailed,
        else => return error.RunFailed,
    };
}

// json types
const Object = struct {
    name: []const u8,
    entry_point: []const u8,
    compile_options: [][]const u8,
};

const NamePath = struct {
    name: []const u8,
    path: []const u8,
};

const Project = struct {
    // LibExeObjStep
    objects: []const Object,
    // Pkg
    packages: []const NamePath,
};

// build file is project_root/build.zig
pub fn initPackagesAndCImport(self: Self, allocator: std.mem.Allocator, import_solver: *ImportSolver, root: FixedPath) !void {
    // build runner
    const zig_run_result = try self.runBuildRunner(allocator, root.child("build.zig"));
    defer allocator.free(zig_run_result);

    var stream = std.json.TokenStream.init(zig_run_result);
    const options = std.json.ParseOptions{ .allocator = allocator, .ignore_unknown_fields = true };
    const project = try std.json.parse(Project, &stream, options);
    defer std.json.parseFree(Project, project, options);

    // packages
    for (project.packages) |pkg| {
        try import_solver.push(pkg.name, root.child(pkg.path));
    }

    // cimport
    const object = project.objects[0];
    if (getZigCImport(allocator, self.exe, object.compile_options, root)) |path| {
        // self.import_solver.c_import = path;
        try import_solver.push("c", path);
    } else |err| {
        logger.err("{}", .{err});
    }
}
