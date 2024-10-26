const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const gl = @import("gl");

// we need to set WL_EGL_PLATFORM to 1 so that the imported file also includes
// the typedef needed for wayland
const egl = @cImport({
    @cDefine("WL_EGL_PLATFORM", "1");
    @cInclude("EGL/egl.h");
    @cInclude("EGL/eglext.h");
    @cUndef("WL_EGL_PLATFORM");
});

const Context = struct {
    compositor: ?*wl.Compositor,
    shm: ?*wl.Shm,
    wm_base: ?*xdg.WmBase,
};

pub fn main() !void {
    var ctx = Context{
        .compositor = null,
        .shm = null,
        .wm_base = null,
    };

    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();
    registry.setListener(*Context, registryListener, &ctx);

    // send events to wayland server
    if (display.dispatch() != .SUCCESS) return error.RoundtripFailed;

    // a bunch of setups
    const compositor = ctx.compositor orelse return error.CompositorNotFound;
    const wm_base = ctx.wm_base orelse return error.WMBaseNotFound;

    const surface = try compositor.createSurface();
    defer surface.destroy();

    const xdg_surface = try wm_base.getXdgSurface(surface);
    defer xdg_surface.destroy();

    const xdg_toplevel = try xdg_surface.getToplevel();
    defer xdg_toplevel.destroy();

    // this keeps track of the current application running state
    // false means it's closed
    var running = true;

    // listens for xdg events
    xdg_surface.setListener(*wl.Surface, xdgSurfaceListener, surface);
    xdg_toplevel.setListener(*bool, xdgToplevelListener, &running);

    // listens for wm events (ping)
    wm_base.setListener(*xdg.WmBase, wmBaseListener, wm_base);

    // commit the surface
    surface.commit();
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    // setup egl display since it needs a display
    // we need to pass in that our platform is wayland khr (stands for khronos)
    const egl_display = egl.eglGetPlatformDisplay(egl.EGL_PLATFORM_WAYLAND_KHR, display, null);

    // initialise the egl display, useful to know the version
    var major_ver: egl.EGLint = 0;
    var minor_ver: egl.EGLint = 0;
    if (egl.eglInitialize(egl_display, &major_ver, &minor_ver) == egl.EGL_TRUE) {
        std.debug.print("EGL version: {d}.{d}\n", .{ major_ver, minor_ver });
    } else switch (egl.eglGetError()) {
        egl.EGL_NOT_INITIALIZED => return error.EGLNotInitialized,
        egl.EGL_BAD_DISPLAY => return error.EGLBadDisplay,
        else => return error.EGLInitFailed,
    }
    // don't forget to cleanup
    defer _ = egl.eglTerminate(egl_display);

    // some options for the egl surface
    // we're using a list of egl attributes but it's kinda like
    // a list of tuples, but because c doesn't have that, well we end up with this
    const egl_surface_attributes = [12:egl.EGL_NONE]egl.EGLint{
        egl.EGL_SURFACE_TYPE,    egl.EGL_WINDOW_BIT,
        egl.EGL_RENDERABLE_TYPE, egl.EGL_OPENGL_BIT,
        egl.EGL_RED_SIZE,        8,
        egl.EGL_GREEN_SIZE,      8,
        egl.EGL_BLUE_SIZE,       8,
        egl.EGL_ALPHA_SIZE,      8,
    };

    // we're wrapping this in a block so that we don't expose unneeded variables
    // to the rest of the code
    const egl_config = config: {
        var config: egl.EGLConfig = null;
        var num_configs: egl.EGLint = 0;
        // basically the way it works is that it will try to find a config
        // that matches the attributes, if it doesn't find one, it will try
        // to find a config that is closest to the attributes, if it doesn't
        // find one, it will return an error
        // this is because platforms varies
        const result = egl.eglChooseConfig(
            egl_display,
            &egl_surface_attributes,
            &config,
            1,
            &num_configs,
        );
        if (result != egl.EGL_TRUE) {
            switch (egl.eglGetError()) {
                egl.EGL_NOT_INITIALIZED => return error.EGLNotInitialized,
                egl.EGL_BAD_DISPLAY => return error.EGLBadDisplay,
                egl.EGL_BAD_ATTRIBUTE => return error.EGLBadAttribute,
                else => return error.EGLChooseConfigFailed,
            }
        }
        if (num_configs == 0) return error.EGLConfigNotFound;
        break :config config;
    };

    // bind the egl api to opengl
    if (egl.eglBindAPI(egl.EGL_OPENGL_API) != egl.EGL_TRUE) {
        switch (egl.eglGetError()) {
            egl.EGL_BAD_DISPLAY => return error.EGLBadDisplay,
            egl.EGL_NOT_INITIALIZED => return error.EGLNotInitialized,
            egl.EGL_BAD_PARAMETER => return error.EGLBadParameter,
            else => return error.EGLBindAPIFailed,
        }
    }

    // finally create the context using specified attributes
    const context_attributes = [4:egl.EGL_NONE]egl.EGLint{
        egl.EGL_CONTEXT_MAJOR_VERSION, 4,
        egl.EGL_CONTEXT_MINOR_VERSION, 5,
    };
    // set the share context to null since we're only using single context
    const egl_context = egl.eglCreateContext(egl_display, egl_config, null, &context_attributes) orelse switch (egl.eglGetError()) {
        egl.EGL_BAD_ATTRIBUTE => return error.EGLBadAttribute,
        egl.EGL_BAD_CONFIG => return error.EGLBadConfig,
        egl.EGL_BAD_MATCH => return error.EGLBadMatch,
        else => return error.EGLCreateContextFailed,
    };
    defer _ = egl.eglDestroyContext(egl_display, egl_context);

    // load opengl functions generated by the zig opengl binding (the one with dotnet lol)
    try gl.load({}, getProcAddress);

    // finally, friggin finally, we can create the window with wayland egl
    const egl_window = try wl.EglWindow.create(surface, 720, 600);
    // make an egl surface for our window to render to
    const egl_surface = egl.eglCreateWindowSurface(egl_display, egl_config, @ptrCast(egl_window), null) orelse switch (egl.eglGetError()) {
        egl.EGL_BAD_MATCH => return error.EGLBadMatch,
        egl.EGL_BAD_CONFIG => return error.EGLBadConfig,
        egl.EGL_BAD_NATIVE_WINDOW => return error.EGLBadNativeWindow,
        else => return error.EGLCreateWindowSurfaceFailed,
    };
    defer _ = egl.eglDestroySurface(egl_display, egl_surface);

    // since egl supports using multiple contexts, we need to make sure
    // which one is set for the current one
    // the draw and read parameter should be the same to avoid EGL_BAD_MATCH error
    if (egl.eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context) != egl.EGL_TRUE) {
        switch (egl.eglGetError()) {
            egl.EGL_BAD_ACCESS => return error.EGLBadAccess,
            egl.EGL_BAD_MATCH => return error.EGLBadMatch,
            egl.EGL_BAD_NATIVE_WINDOW => return error.EGLBadNativeWindow,
            egl.EGL_BAD_CONTEXT => return error.EGLBadContext,
            egl.EGL_BAD_ALLOC => return error.EGLBadAlloc,
            else => return error.EGLMakeCurrentFailed,
        }
    }

    const vertex_shader = try createShader(@embedFile("vertex.glsl"), gl.VERTEX_SHADER);
    const fragment_shader = try createShader(@embedFile("fragment.glsl"), gl.FRAGMENT_SHADER);

    const program = gl.createProgram();
    gl.attachShader(program, vertex_shader);
    gl.attachShader(program, fragment_shader);
    gl.linkProgram(program);

    // make sure it's linked
    var success: gl.GLint = 0;
    gl.getProgramiv(program, gl.LINK_STATUS, &success);
    if (success == gl.FALSE) {
        // no idea how to get the error message
        std.debug.print("Program linking failed\n", .{});
        return error.ProgramLinkingFailed;
    }

    // delete shaders since we've linked the program and we don't need them anymore
    gl.deleteShader(vertex_shader);
    gl.deleteShader(fragment_shader);

    // create a vertex array object (VAO) to store the vertex data
    const triangle: gl.GLuint = vao: {
        var vao: gl.GLuint = 0;
        gl.genVertexArrays(1, &vao);
        break :vao vao;
    };
    gl.bindVertexArray(triangle);

    {
        // this contains the position and the colour of the triangle
        // zig fmt: off
        const vertices = [_]f32{
            // position      // colour
            -0.5,-0.5, 0.0,  1.0, 0.0, 0.0, // bottom left corner
             0.0, 0.5, 0.0,  0.0, 1.0, 0.0, // top middle
             0.5,-0.5, 0.0,  0.0, 0.0, 1.0, // bottom right corner
        };

        // load vertex position data to the gpu using a buffer object
        var vbo: gl.GLuint = 0;
        gl.genBuffers(1, &vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.STATIC_DRAW);
    }

    // see: https://learnopengl.com/Getting-started/Hello-Triangle
    // position attribute
    gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 6 * @sizeOf(f32), @ptrFromInt(0));
    gl.enableVertexAttribArray(0);
    // colour attribute
    gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 6 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    gl.enableVertexAttribArray(1);

    gl.clearColor(0.0, 0.0, 0.0, 1.0);

    while (running) {
        gl.clear(gl.COLOR_BUFFER_BIT);

        // use the shader program we've defined before
        gl.useProgram(program);
        gl.bindVertexArray(triangle);
        gl.drawArrays(gl.TRIANGLES, 0, 3);

        gl.flush();

        // after drawing, we need to swap the buffers
        if (egl.eglSwapBuffers(egl_display, egl_surface) != egl.EGL_TRUE) {
            switch (egl.eglGetError()) {
                egl.EGL_NOT_INITIALIZED => return error.EGLNotInitialized,
                egl.EGL_BAD_SURFACE => return error.EGLBadSurface,
                egl.EGL_BAD_DISPLAY => return error.EGLBadDisplay,
                egl.EGL_CONTEXT_LOST => return error.EGLContextLost,
                else => return error.EGLSwapBuffersFailed,
            }
        }

        // as always, dispatch to wayland server
        if (display.dispatch() != .SUCCESS) return error.DispatchFailed;
    }
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    switch (event) {
        .global => |global| {
            // capture compositor interface
            if (std.mem.orderZ(u8, global.interface, wl.Compositor.getInterface().name) == .eq) {
                context.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            }
            // capture shm interface
            if (std.mem.orderZ(u8, global.interface, wl.Shm.getInterface().name) == .eq) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            }
            // capture xdg wm base interface
            if (std.mem.orderZ(u8, global.interface, xdg.WmBase.getInterface().name) == .eq) {
                context.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
            }
        },
        // don't care about other events
        else => {},
    }
}

fn wmBaseListener(wm_base: *xdg.WmBase, event: xdg.WmBase.Event, _: *xdg.WmBase) void {
    switch (event) {
        .ping => |ping| {
            wm_base.pong(ping.serial);
        },
    }
}

fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, surface: *wl.Surface) void {
    switch (event) {
        .configure => |configure| {
            xdg_surface.ackConfigure(configure.serial);
            surface.commit();
        },
    }
}

fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, running: *bool) void {
    switch (event) {
        .configure => {},
        .close => running.* = false,
    }
}

// a wrapper for gl.load since it also gives us the context but we don't need it
fn getProcAddress(_: void, name: [:0]const u8) ?gl.FunctionPointer {
    return egl.eglGetProcAddress(name);
}

fn createShader(shader_src: [:0]const u8, shader_type: gl.GLenum) !gl.GLuint {
    // cast to c pointer
    const src_ptr: [*c]const u8 = shader_src;

    // create and compile shader
    const shader: gl.GLuint = gl.createShader(shader_type);
    gl.shaderSource(shader, 1, &src_ptr, null);
    gl.compileShader(shader);

    // make sure if it compiled
    var success: gl.GLint = 0;
    gl.getShaderiv(shader, gl.COMPILE_STATUS, &success);
    if (success == gl.FALSE) {
        // actually no idea how to get the error message lmao
        std.debug.print("Shader compilation failed", .{});
        return error.ShaderCompilationFailed;
    }

    return shader;
}
