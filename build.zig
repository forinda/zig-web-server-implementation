const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Optional: enable SQLite adapter (requires libsqlite3-dev)
    const enable_sqlite = b.option(bool, "sqlite", "Enable SQLite adapter (requires libsqlite3-dev)") orelse false;

    const exe = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    if (enable_sqlite) {
        exe.root_module.link_libc = true;
        exe.root_module.linkSystemLibrary("sqlite3", .{});
    }

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the web server");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);

    // Dev mode: hot reload with file watching
    const dev_step = b.step("dev", "Run with hot reload (watches src/ for changes)");
    const dev_cmd = b.addSystemCommand(&.{ "bash", "dev.sh" });
    dev_cmd.setCwd(b.path("."));
    dev_step.dependOn(&dev_cmd.step);
}
