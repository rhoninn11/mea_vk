const std = @import("std");
const gc = @import("graphics_context.zig");

const glfw = @import("third_party/glfw.zig");
const vk = @import("vulkan-zig");
const input = @import("input.zig");
const sdlh = @import("sdlh.zig");
const imgs = @import("imgs/imgs.zig");
const devui = @import("devui.zig");

pub const EasyAcces = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    host: SdlHost,
    gm: *const gc.GraphicsContext,
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
    var sdl_ctx = sdlh.initSDL() catch |err| {
        std.debug.print("!!! sdl init failed with |> {s}\n", .{@errorName(err)});
        return err;
    };
    defer sdlh.exitSDL();

    var gm = try gc.GraphicsContext.initUnderSdl(
        init.gpa,
        sdl_name,
        sdl_ctx.window.?,
    );
    defer gm.deinit();

    // cimgui.cImGui_ImplVulkan_LoadFunctions(vk.API_VERSION_1_2, loader_func: ?*const fn ([*c]const u8, ?*anyopaque) ?*const fn () void)
    // function loading propably here
    try devui.prelode();
    var loader = devui.Loader.from(&gm);
    const ok = devui.BindToVulkan(
        vk.API_VERSION_1_2.toU32(),
        devui.Loader.load,
        &loader,
    );
    if (!ok) return error.devuiVkBindFailed;
    try devui.createImguiContext();

    // devui.Loader

    var imga = try imgs.ImgaAllocator.init(
        &gm,
        .{ .device_local_bit = true },
    );
    defer imga.deinit(&gm);
    // imga.verbose = true;

    std.log.debug("Using device: {s}", .{gm.deviceName()});
    const access = EasyAcces{
        .host = .{ .ctx = &sdl_ctx },
        .gm = &gm,
        .gpa = init.gpa,
        .io = init.io,
        .imga = &imga,
    };

    passenger(access) catch |err| {
        std.debug.print("passanger error {s}\n", .{@errorName(err)});
    };

    std.debug.print("+++ leaving host\n", .{});
}
