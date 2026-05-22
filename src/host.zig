const std = @import("std");
const gm = @import("graphics_context.zig");

const glfw = @import("third_party/glfw.zig");
const vk = @import("third_party/vk.zig");
const input = @import("input.zig");
const sdl_wrap = @import("sdl_wrap2.zig");

pub const EasyAcces = struct {
    io: std.Io,
    alloc: std.mem.Allocator,
    host: DualHostWin,
    vkctx: *const gm.GraphicsContext,
};

pub const OnHostErrors = error{
    passengerError,
    libVulkanProblem,
};

const DeeperClient = *const fn (acces: EasyAcces) OnHostErrors!void;

const Hosts = enum(u8) {
    glfw_h,
    sdl_h,
};
pub const DualHostWin = union(Hosts) {
    glfw_h: *glfw.Window,
    sdl_h: *sdl_wrap.SdlContext,

    pub fn extent(self: DualHostWin) !vk.Extent2D {
        switch (self) {
            .glfw_h => |win| {
                var resolution_extent: vk.Extent2D = undefined;
                resolution_extent.width, resolution_extent.height = blk: {
                    var w: c_int = undefined;
                    var h: c_int = undefined;
                    glfw.getFramebufferSize(win, &w, &h);
                    break :blk .{ @intCast(w), @intCast(h) };
                };
                return resolution_extent;
            },
            .sdl_h => |ctx| {
                const w, const h = try ctx.window.?.getSize();
                return vk.Extent2D{ .width = @intCast(w), .height = @intCast(h) };
            },
        }
    }

    pub fn shoudClose(self: DualHostWin) bool {
        switch (self) {
            .glfw_h => |win| {
                return glfw.windowShouldClose(win);
            },
            .sdl_h => |ctx| {
                return ctx.should_close;
            },
        }
    }

    pub fn setShoudClose(self: DualHostWin, val: bool) void {
        switch (self) {
            .glfw_h => |win| {
                glfw.setWindowShouldClose(win, val);
            },
            .sdl_h => {
                // std.debug.print("set shoud close not implemented for sdl\n", .{});
            },
        }
    }

    pub fn pollEvents(self: DualHostWin) void {
        switch (self) {
            .glfw_h => glfw.pollEvents(),
            .sdl_h => |ctx| ctx.pollEvents(),
        }
    }
};

const glfw_name = "glfw app name form host function";
const sld_name = "sld app name form host function";
pub fn glfwHost(init: std.process.Init, passenger: DeeperClient) !void {
    try glfw.init();
    defer glfw.terminate();

    // According to the GLFW docs:
    //
    // > Window systems put limits on window sizes. Very large or very small window dimensions
    // > may be overridden by the window system on creation. Check the actual size after creation.
    // -- https://www.glfw.org/docs/3.3/group__window.html#ga3555a418df92ad53f917597fe2f64aeb
    //
    // This happens in practice, for example, when using Wayland with a scaling factor that is not a
    // divisor of the initial window size (see https://github.com/Snektron/vulkan-zig/pull/192).
    // To fix it, just fetch the actual size here, after the windowing system has had the time to
    // update the window.
    if (!glfw.vulkanSupported()) {
        std.log.err("GLFW could not find libvulkan", .{});
        return error.NoVulkan;
    }

    // czym się różni vk.Rect2D od vk.Extend2D?
    const resolution_extent = vk.Extent2D{ .width = 1600, .height = 900 };
    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);
    const window = try glfw.createWindow(
        @intCast(resolution_extent.width),
        @intCast(resolution_extent.height),
        glfw_name,
        null,
        null,
    );
    defer glfw.destroyWindow(window);
    _ = glfw.setKeyCallback(window, input.key_callback);

    const d = DualHostWin{ .glfw_h = window };

    const ctx_glfw = try gm.GraphicsContext.init(
        init.gpa,
        glfw_name,
        window,
    );
    defer ctx_glfw.deinit();

    const access = EasyAcces{
        .host = d,
        .vkctx = &ctx_glfw,
        .alloc = init.gpa,
        .io = init.io,
    };

    return passenger(access);
}

pub fn sdlHost(init: std.process.Init, passenger: DeeperClient) !void {
    try sdl_wrap.initSDL();
    defer sdl_wrap.exitSDL();

    sdl_wrap.vulkanSupported() catch {
        std.log.err("!!! SDL could not find libvulkan", .{});
        return OnHostErrors.libVulkanProblem;
    };
    const sdl_ctx = sdl_wrap.getContext();
    const vkctx_sdl = try gm.GraphicsContext.initUnderSdl(init.gpa, sld_name, sdl_ctx.window.?);
    defer vkctx_sdl.deinit();

    std.log.debug("Using device: {s}", .{vkctx_sdl.deviceName()});
    const access = EasyAcces{
        .host = .{ .sdl_h = sdl_ctx },
        .vkctx = &vkctx_sdl,
        .alloc = init.gpa,
        .io = init.io,
    };
    return passenger(access);
}
