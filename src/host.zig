const std = @import("std");
const gm = @import("graphics_context.zig");

const glfw = @import("third_party/glfw.zig");
const vk = @import("vulkan-zig");
const input = @import("input.zig");
const sdl_wrap = @import("sdl_wrap.zig");

pub const EasyAcces = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    host: DualHostWin,
    vkctx: *const gm.GraphicsContext,
};

pub const OnHostErrors = error{
    passengerError,
    libVulkanProblem,
};

const DeeperClient = *const fn (acces: EasyAcces) OnHostErrors!void;

const Hosts = enum(u8) {
    sdl_h,
};
pub const DualHostWin = union(Hosts) {
    sdl_h: *sdl_wrap.SdlContext,

    pub fn extent(self: DualHostWin) !vk.Extent2D {
        switch (self) {
            .sdl_h => |ctx| {
                const w, const h = try ctx.window.?.getSize();
                return vk.Extent2D{ .width = @intCast(w), .height = @intCast(h) };
            },
        }
    }

    pub fn shoudClose(self: DualHostWin) bool {
        switch (self) {
            .sdl_h => |ctx| {
                return ctx.should_close;
            },
        }
    }

    pub fn setShoudClose(self: DualHostWin, val: bool) void {
        switch (self) {
            .sdl_h => {
                _ = val;
            },
        }
    }

    pub fn pollEvents(self: DualHostWin) void {
        switch (self) {
            .sdl_h => |ctx| ctx.pollEvents(),
        }
    }
};

const glfw_name = "glfw app name form host function";
const sdl_name = "sld app name form host function";

pub fn sdlHost(init: std.process.Init, passenger: DeeperClient) !void {
    try sdl_wrap.initSDL();
    defer sdl_wrap.exitSDL();

    sdl_wrap.vulkanSupported() catch {
        std.log.err("!!! SDL could not find libvulkan", .{});
        return OnHostErrors.libVulkanProblem;
    };
    const sdl_ctx = sdl_wrap.getContext();
    const vkctx_sdl = try gm.GraphicsContext.initUnderSdl(init.gpa, sdl_name, sdl_ctx.window.?);
    defer vkctx_sdl.deinit();

    std.log.debug("Using device: {s}", .{vkctx_sdl.deviceName()});
    const access = EasyAcces{
        .host = .{ .sdl_h = sdl_ctx },
        .vkctx = &vkctx_sdl,
        .gpa = init.gpa,
        .io = init.io,
    };
    return passenger(access);
}
