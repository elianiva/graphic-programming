const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});

    // add the C source file to the build
    const exe = b.addExecutable(.{
        .name = "triangle",
        .target = target,
        .optimize = mode,
    });
    exe.linkLibC();
    exe.addCSourceFiles(.{
        .files = &.{
            "src/main.c",
        },
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_exe.step);
}
