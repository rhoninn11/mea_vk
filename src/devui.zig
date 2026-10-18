const vk = @import("vulkan-zig");
const std = @import("std");
const sdl = @import("sdl3");
const gc = @import("graphics_context.zig");

const cimgui = @import("cimgui");

pub var getInstanceProcAddress: vk.PfnGetInstanceProcAddr = undefined;

pub fn prelode() !void {
    const fn_addr_hmm = try sdl.vulkan.getVkGetInstanceProcAddr();
    std.debug.print("+++ prelode for devui\n", .{});
    getInstanceProcAddress = @ptrCast(fn_addr_hmm);
}

pub const Loader = struct {
    instance: *vk.Instance,
    device: *vk.Device,

    pub fn from(gm: *gc.GraphicsContext) Loader {
        return Loader{
            .instance = &gm.inst,
            .device = &gm.dev,
        };
    }

    fn loadGlobal(name: [*c]const u8) vk.PfnVoidFunction {
        return getInstanceProcAddress(vk.Instance.null_handle, name);
    }

    fn loadInstance(self: *const @This(), name: [*c]const u8) vk.PfnVoidFunction {
        return getInstanceProcAddress(self.instance.*, name);
    }

    fn loadDevice(self: *const @This(), name: [*c]const u8) vk.PfnVoidFunction {
        return @as(vk.PfnGetDeviceProcAddr, @ptrCast(self.loadInstance("vkGetDeviceProcAddr")))(self.device.*, name);
    }

    pub fn load(funcname: [*c]const u8, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) vk.PfnVoidFunction {
        var self: *@This() = @ptrCast(@alignCast(user_data));
        if (self.loadDevice(funcname)) |func| return func;
        if (self.loadInstance(funcname)) |func| return func;
        if (loadGlobal(funcname)) |func| return func;
        return null;
    }
};
pub const BindToVulkan = cimgui.cImGui_ImplVulkan_LoadFunctionsEx;

var io: [*c]cimgui.ImGuiIO = undefined;
pub fn createImguiContext() !void {
    _ = cimgui.CIMGUI_CHECKVERSION();
    const ctx = cimgui.ImGui_CreateContext(null);
    if (ctx == null) return error.ImGuiCreateContext;
    std.debug.print("+++ imgui context initialized\n", .{});
    io = cimgui.ImGui_GetIO();
    io[0].ConfigFlags |= cimgui.ImGuiConfigFlags_NavEnableKeyboard;
    io[0].ConfigFlags |= cimgui.ImGuiConfigFlags_NavEnableGamepad;
    cimgui.ImGui_StyleColorsDark(null);
}
