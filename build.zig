const std = @import("std");

const astutil_pkg = std.build.Pkg{
    .name = "astutil",
    .source = .{ .path = "pkgs/astutil/src/main.zig" },
};

const jsonrpc_pkg = std.build.Pkg{
    .name = "jsonrpc",
    .source = .{ .path = "pkgs/jsonrpc/src/main.zig" },
};

const lsp_pkg = std.build.Pkg{
    .name = "language_server_protocol",
    .source = .{ .path = "pkgs/language_server_protocol/src/main.zig" },
};

const ls_pkg = std.build.Pkg{
    .name = "language_server",
    .source = .{ .path = "pkgs/language_server/src/main.zig" },
    .dependencies = &.{lsp_pkg, astutil_pkg},
};

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("yazls", "src/main.zig");
    exe.use_stage1 = true;    
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    exe.addPackage(astutil_pkg);
    exe.addPackage(jsonrpc_pkg);
    exe.addPackage(ls_pkg);
    b.installFile("install/build_runner.zig", "bin/build_runner.zig");

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
