const std = @import("std");
const gm = @import("graphics_context.zig");

const glfw = @import("third_party/glfw.zig");
const vk = @import("vulkan-zig");
const input = @import("input.zig");
const sdlh = @import("sdlh.zig");
const imgs = @import("imgs/imgs.zig");

pub const EasyAcces = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    host: DualHostWin,
    gm: *const gm.GraphicsContext,
    imga: *imgs.LinearImageAllocator,
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
    sdl_h: *sdlh.SdlContext,

    pub fn winExtent(self: DualHostWin) !vk.Extent2D {
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

    pub fn closeWindow(self: DualHostWin) void {
        switch (self) {
            .sdl_h => {
                self.sdl_h.should_close = true;
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
    sdlh.initSDL() catch |err| {
        std.debug.print("!!! sdl init failed with |> {s}\n", .{@errorName(err)});
        return err;
    };
    defer sdlh.exitSDL();

    const sdl_ctx = sdlh.getContext();
    // sdl_ctx.should_close = true; // DEBUG SPOT

    const g_context = try gm.GraphicsContext.initUnderSdl(
        init.gpa,
        sdl_name,
        sdl_ctx.window.?,
    );
    defer g_context.deinit();

    var imga = try imgs.LinearImageAllocator.init(
        init.gpa,
        &g_context,
        .{ .device_local_bit = true },
    );
    defer imga.deinit(&g_context);
    // imga.verbose = true;

    std.log.debug("Using device: {s}", .{g_context.deviceName()});
    const access = EasyAcces{
        .host = .{ .sdl_h = sdl_ctx },
        .gm = &g_context,
        .gpa = init.gpa,
        .io = init.io,
        .imga = &imga,
    };

    passenger(access) catch |err| {
        std.debug.print("passanger error {s}\n", .{@errorName(err)});
    };

    std.debug.print("+++ leaving host\n", .{});
}
