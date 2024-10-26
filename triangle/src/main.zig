const std = @import("std");
const wayland = @cImport({
    @cInclude("wayland-client.h");
});
const cString = @cImport({
    @cInclude("string.h");
});
const cStdio = @cImport({
    @cInclude("stdio.h");
});

var shell: ?*wayland.wl_shell = null;
var compositor: ?*wayland.wl_compositor = null;

pub fn main() void {
    const display = wayland.wl_display_connect(null);
    if (display == null) {
        std.debug.print("Can't connect to display\n", .{});
        return;
    }

    const registry = wayland.wl_display_get_registry(display);
    if (registry == null) {
        std.debug.print("Can't get registry\n", .{});
        return;
    }

    const registryListener = [_]wayland.wl_registry_listener{wayland.wl_registry_listener{
        .global = globalRegistryHandler,
    }};
    _ = wayland.wl_registry_add_listener(registry, &registryListener, null);

    // wait for the registry to be ready and then dispatch the events
    std.debug.print("waiting for registry\n", .{});
    _ = wayland.wl_display_dispatch(display);
    _ = wayland.wl_display_roundtrip(display);
    std.debug.print("finished waiting for registry\n", .{});

    // make sure the compositor and the shell exists
    if (compositor == null) {
        std.debug.print("Can't get compositor\n", .{});
        return;
    }
    if (shell == null) {
        std.debug.print("Can't get shell\n", .{});
        return;
    }

    // spawn the shell
    std.debug.print("spawning shell\n", .{});
    const surface = wayland.wl_compositor_create_surface(compositor);
    if (surface == null) {
        std.debug.print("Can't get shell surface\n", .{});
        return;
    }

    const shell_surface = wayland.wl_shell_get_shell_surface(shell, surface);
    wayland.wl_shell_surface_set_toplevel(shell_surface);

    std.debug.print("connected to display\n", .{});
    wayland.wl_display_disconnect(display);
    std.debug.print("disconnected from display\n", .{});
}

fn globalRegistryHandler(_: ?*anyopaque, registry: ?*wayland.wl_registry, id: u32, interface: ?[*]const u8, version: u32) callconv(.C) void {
    _ = cStdio.printf("interface: %s\n", interface);

    if (interface) |iface| {
        if (cString.strcmp("wl_compositor", iface) == 0) {
            if (registry) |reg| {
                std.debug.print("compositor found\n", .{});
                compositor = if (wayland.wl_registry_bind(reg, id, &wayland.wl_compositor_interface, version)) |ptr| @ptrCast(ptr) else null;
            }
            return;
        }

        if (cString.strcmp("xdg_wm_base", iface) == 0) {
            if (registry) |reg| {
                std.debug.print("shell found\n", .{});
                shell = if (wayland.wl_registry_bind(reg, id, &wayland.wl_compositor_interface, version)) |ptr| @ptrCast(ptr) else null;
            }
        }
    }
}
