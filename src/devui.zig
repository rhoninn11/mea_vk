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
pub fn ProcesEvents(ev: sdl.events.Event) void {
    if (imgui_ctx) |_| {
        const raw = ev.toSdl();
        _ = cimgui.cImGui_ImplSDL3_ProcessEvent(@ptrCast(&raw));
    }
}

var io: [*c]cimgui.ImGuiIO = undefined;
var imgui_ctx: ?*cimgui.struct_ImGuiContext_t = null;
var imgui_dset_pool: ?vk.DescriptorPool = null;
var dev_prox: ?vk.DeviceProxy = null;

pub fn integrate(
    window: *const sdl.video.Window,
    gm: *const gc.GraphicsContext,
    inflight_count: u32,
    render_pass: vk.RenderPass,
) !void {
    _ = cimgui.CIMGUI_CHECKVERSION();
    imgui_ctx = cimgui.ImGui_CreateContext(null);
    if (imgui_ctx == null) return error.ImGuiCreateContext;
    errdefer cimgui.ImGui_DestroyContext(imgui_ctx);

    std.debug.print("+++ imgui context initialized\n", .{});
    io = cimgui.ImGui_GetIO();
    io[0].ConfigFlags |= cimgui.ImGuiConfigFlags_NavEnableKeyboard;
    io[0].ConfigFlags |= cimgui.ImGuiConfigFlags_NavEnableGamepad;
    cimgui.ImGui_StyleColorsDark(null);

    const pool_sizes = [_]vk.DescriptorPoolSize{
        .{
            .type = .sampled_image,
            .descriptor_count = cimgui.IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE,
        },
        .{
            .type = .sampler,
            .descriptor_count = cimgui.IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE,
        },
    };
    var desc_pool_create_info = vk.DescriptorPoolCreateInfo{
        .flags = .{ .free_descriptor_set_bit = true },
        .max_sets = 0,
    };
    for (pool_sizes) |pool_size| desc_pool_create_info.max_sets += pool_size.descriptor_count;
    desc_pool_create_info.pool_size_count = pool_sizes.len;
    desc_pool_create_info.p_pool_sizes = &pool_sizes;

    dev_prox = gm.device_proxy;
    imgui_dset_pool = try dev_prox.?.createDescriptorPool(&desc_pool_create_info, null);
    errdefer gm.device_proxy.destroyDescriptorPool(imgui_dset_pool.?, null);

    const winptr: *cimgui.SDL_Window = @ptrCast(window.value);
    if (!cimgui.cImGui_ImplSDL3_InitForVulkan(winptr)) return error.imguiSdlInitFail;
    errdefer cimgui.cImGui_ImplSDL3_Shutdown();

    var init_info = cimgui.ImGui_ImplVulkan_InitInfo{};
    init_info.Instance = @ptrFromInt(@intFromEnum(gm.inst));
    init_info.PhysicalDevice = @ptrFromInt(@intFromEnum(gm.phy_dev));
    init_info.Device = @ptrFromInt(@intFromEnum(gm.dev));
    init_info.QueueFamily = gm.graphics_queue.family;
    init_info.Queue = @ptrFromInt(@intFromEnum(gm.graphics_queue.handle));
    init_info.PipelineCache = null;
    init_info.DescriptorPool = @ptrFromInt(@intFromEnum(imgui_dset_pool.?));
    init_info.MinImageCount = 2;
    init_info.ImageCount = inflight_count;

    init_info.UseDynamicRendering = false;

    const one_msaa_sample = vk.SampleCountFlags{ .@"1_bit" = true };
    init_info.PipelineInfoMain.MSAASamples = one_msaa_sample.toInt();
    init_info.PipelineInfoMain.Subpass = 0;
    init_info.PipelineInfoMain.RenderPass = @ptrFromInt(@intFromEnum(render_pass));

    init_info.Allocator = null;
    init_info.CheckVkResultFn = null;

    if (!cimgui.cImGui_ImplVulkan_Init(&init_info)) return error.imguiVkInitFail;
    errdefer cimgui.cImGui_ImplVulkan_Shutdown();
}

pub fn shutdown() void {
    cimgui.cImGui_ImplVulkan_Shutdown();
    cimgui.cImGui_ImplSDL3_Shutdown();
    dev_prox.?.destroyDescriptorPool(imgui_dset_pool.?, null);
    cimgui.ImGui_DestroyContext(imgui_ctx);
}

pub fn newFrame() void {
    cimgui.cImGui_ImplVulkan_NewFrame();
    cimgui.cImGui_ImplSDL3_NewFrame();
    cimgui.ImGui_NewFrame();
}

pub const ShowDemoWindow = cimgui.ImGui_ShowDemoWindow;
pub const DevuiDrawData = [*c]cimgui.ImDrawData;

pub fn finalizeFrame() DevuiDrawData {
    cimgui.ImGui_Render();
    return cimgui.ImGui_GetDrawData();
}

pub fn recordCommands(data: DevuiDrawData, cb: vk.CommandBuffer) void {
    const cb_ptr: cimgui.VkCommandBuffer = @ptrFromInt(@intFromEnum(cb));
    cimgui.cImGui_ImplVulkan_RenderDrawData(data, cb_ptr);
}
