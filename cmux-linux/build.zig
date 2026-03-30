const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const headless = b.option(bool, "headless", "Build terminal-only mode (no GTK4/GUI)") orelse false;

    const root_source = if (headless)
        b.path("src/main_headless.zig")
    else
        b.path("src/main.zig");

    const exe = b.addExecutable(.{
        .name = if (headless) "cmux-term" else "cmux",
        .root_module = b.createModule(.{
            .root_source_file = root_source,
            .target = target,
            .optimize = optimize,
        }),
    });

    if (!headless) {
        // Full GUI mode: GTK4 + libadwaita + OpenGL + WebKitGTK
        exe.root_module.linkSystemLibrary("gtk4", .{});
        exe.root_module.linkSystemLibrary("libadwaita-1", .{});
        exe.root_module.linkSystemLibrary("gl", .{});
        exe.root_module.linkSystemLibrary("webkitgtk-6.0", .{});
    }

    // libghostty: shared library built from ghostty submodule.
    // Build first: cd ../ghostty && zig build -Dapp-runtime=none -Drenderer=opengl
    exe.root_module.addLibraryPath(.{ .cwd_relative = "../ghostty/zig-out/lib" });
    exe.root_module.addSystemIncludePath(.{ .cwd_relative = "../ghostty/include" });
    exe.root_module.linkSystemLibrary("ghostty", .{});

    exe.root_module.link_libc = true;

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run cmux-linux");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const test_step = b.step("test", "Run unit tests");
    const t = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/config.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(t).step);
}
