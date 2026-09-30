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
    host: SdlHost,
    gm: *const gm.GraphicsContext,
    imga: *imgs.ImgaAllocator,
};

pub const OnHostErrors = error{
    passengerError,
    libVulkanProblem,
};

const DeeperClient = *const fn (acces: EasyAcces) OnHostErrors!void;

pub const SdlHost = struct {
    ctx: *sdlh.SdlContext,

    pub fn winExtent(self: SdlHost) !vk.Extent2D {
        const w, const h = try self.ctx.window.?.getSize();
        return vk.Extent2D{ .width = @intCast(w), .height = @intCast(h) };
    }

    pub fn shoudClose(self: SdlHost) bool {
        return self.ctx.should_close;
    }

    pub fn closeWindow(self: SdlHost) void {
        self.ctx.should_close = true;
    }

    pub fn pollEvents(self: SdlHost) void {
        self.ctx.pollEvents();
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

    var imga = try imgs.ImgaAllocator.init(
        &g_context,
        .{ .device_local_bit = true },
    );
    defer imga.deinit(&g_context);
    // imga.verbose = true;

    std.log.debug("Using device: {s}", .{g_context.deviceName()});
    const access = EasyAcces{
        .host = .{ .ctx = sdl_ctx },
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
