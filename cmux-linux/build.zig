const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "cmux",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link GTK4 and libadwaita via pkg-config
    exe.root_module.linkSystemLibrary("gtk4", .{});
    exe.root_module.linkSystemLibrary("libadwaita-1", .{});

    // Link OpenGL for terminal rendering
    exe.root_module.linkSystemLibrary("gl", .{});

    // libghostty: shared library built from ghostty submodule.
    // Build first: cd ../ghostty && zig build -Dapp-runtime=none -Drenderer=opengl
    // The .so bundles all deps (simdutf, glslang, imgui, spirv-cross, etc.)
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
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(t).step);
}
