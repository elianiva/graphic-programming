const std = @import("std");
const Build = std.Build;

const Scanner = @import("zig-wayland").Scanner;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.create(b, .{});

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");

    // Pass the maximum version implemented by your wayland server or client.
    // Requests, events, enums, etc. from newer versions will not be generated,
    // ensuring forwards compatibility with newer protocol xml.
    // This will also generate code for interfaces created using the provided
    // global interface, in this example wl_keyboard, wl_pointer, xdg_surface,
    // xdg_toplevel, etc. would be generated as well.
    scanner.generate("wl_compositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("xdg_wm_base", 3);

    const exe = b.addExecutable(.{
        .name = "triangle",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("wayland", wayland);
    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");
    exe.linkSystemLibrary("wayland-egl");
    exe.linkSystemLibrary("EGL");

    exe.root_module.addAnonymousImport("gl", .{
        .root_source_file = b.path("deps/zig-opengl/gl_4_5.zig"),
    });

    // TODO: remove when https://github.com/ziglang/zig/issues/131 is implemented
    scanner.addCSource(exe);

    b.installArtifact(exe);

    // add run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
