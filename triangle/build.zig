const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});

    // add the C source file to the build
    const exe = b.addExecutable(.{
        .name = "triangle",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = mode,
    });

    // add c libraries
    exe.linkLibC();

    // add wayland-client
    exe.linkSystemLibrary("wayland-client");

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_exe.step);
}
