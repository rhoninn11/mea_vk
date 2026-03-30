const std = @import("std");

const glfw = @import("third_party/glfw.zig");
const vk = @import("third_party/vk.zig");
const t = @import("types.zig");

const c = @import("c.zig");
const Allocator = std.mem.Allocator;

const swpchn = @import("swapchain.zig");

const required_layer_names = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};

// TODO: https://claude.ai/chat/a8727d87-0510-44f0-a8af-664e93844a26
const required_device_extensions = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
    vk.extensions.khr_multiview.name,
    vk.extensions.khr_synchronization_2.name,
};

/// There are 3 levels of bindings in vulkan-zig:
/// - The Dispatch types (vk.BaseDispatch, vk.InstanceDispatch, vk.DeviceDispatch)
///   are "plain" structs which just contain the function pointers for a particular
///   object.
/// - The Wrapper types (vk.Basewrapper, vk.InstanceWrapper, vk.DeviceWrapper) contains
///   the Dispatch type, as well as Ziggified Vulkan functions - these return Zig errors,
///   etc.
/// - The Proxy types (vk.InstanceProxy, vk.DeviceProxy, vk.CommandBufferProxy,
///   vk.QueueProxy) contain a pointer to a Wrapper and also contain the object's handle.
///   Calling Ziggified functions on these types automatically passes the handle as
///   the first parameter of each function. Note that this type accepts a pointer to
///   a wrapper struct as there is a problem with LLVM where embedding function pointers
///   and object pointer in the same struct leads to missed optimizations. If the wrapper
///   member is a pointer, LLVM will try to optimize it as any other vtable.
/// The wrappers contain
const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const DeviceWrapper = vk.DeviceWrapper;

const Instance = vk.InstanceProxy;
const Device = vk.DeviceProxy;

// imgs
pub const RGBImage = struct {
    const Self = @This();

    gc: *const GraphicsContext,
    dvk_img: vk.Image,
    dvk_mem: vk.DeviceMemory,
    dvk_size: usize,
    vk_format: vk.Format,
    vk_img_view: ?vk.ImageView = null,
    vk_sampler: ?vk.Sampler = null,

    pub fn init(gc: *const GraphicsContext, x: u8, y: u8) !Self {
        const devk = gc.dev;
        const format: vk.Format = .a8b8g8r8_srgb_pack32;

        const img_create_info: vk.ImageCreateInfo = .{
            .image_type = .@"2d",
            .format = format,
            .extent = .{ .height = y, .width = x, .depth = 1 },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = .optimal,
            .usage = .{
                .sampled_bit = true,
                .transfer_dst_bit = true,
            },
            .sharing_mode = .exclusive,
            .initial_layout = .undefined,
        };
        const vk_img = try devk.createImage(&img_create_info, null);
        errdefer devk.destroyImage(vk_img, null);

        const mem_req = devk.getImageMemoryRequirements(vk_img);
        const vk_mem = try gc.allocate(
            mem_req,
            baked.memory_gpu,
        );
        errdefer devk.freeMemory(vk_mem, null);

        try devk.bindImageMemory(vk_img, vk_mem, 0);

        // gfctx.createBuffer(gc, gfctx.baked.cpu_accesible_memory, mem_req.size , .{ .transfer_src_bit = true });
        return Self{
            .gc = gc,
            .dvk_img = vk_img,
            .dvk_mem = vk_mem,
            .dvk_size = mem_req.size,
            .vk_format = format,
        };
    }

    pub fn createImageView(self: *Self, gc: *const GraphicsContext) !void {
        const devk = gc.dev;
        const image_view_create_info: vk.ImageViewCreateInfo = .{
            .image = self.dvk_img,
            .format = self.vk_format,
            .view_type = .@"2d",
            .subresource_range = baked.color_img_subrng,
            .components = baked.identity_mapping,
        };

        self.vk_img_view = try devk.createImageView(&image_view_create_info, null);
    }
    pub fn createSampler(self: *Self, gc: *const GraphicsContext) !void {
        const props = gc.instance.getPhysicalDeviceProperties(gc.pdev);
        const sample_create_info: vk.SamplerCreateInfo = .{
            .mag_filter = .linear,
            .min_filter = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
            .anisotropy_enable = .false, // TODO: temprly disabled
            .max_anisotropy = props.limits.max_sampler_anisotropy,
            .border_color = .int_opaque_black,
            .unnormalized_coordinates = .false,
            .compare_enable = .false,
            .compare_op = .always,
            .mipmap_mode = .linear,
            .mip_lod_bias = 0.0,
            .min_lod = 0.0,
            .max_lod = 0.0,
        };
        self.vk_sampler = try gc.dev.createSampler(&sample_create_info, null);
    }

    pub fn deinit(self: *Self) void {
        const devk = self.gc.dev;
        if (self.vk_sampler) |_sampler| {
            devk.destroySampler(_sampler, null);
        }
        if (self.vk_img_view) |_img_view| {
            devk.destroyImageView(_img_view, null);
        }

        devk.freeMemory(self.dvk_mem, null);
        devk.destroyImage(self.dvk_img, null);
    }
};
const imgs = @import("imgs.zig");
pub const DepthImage = imgs.DepthImage;

pub const OneShotCommanded = struct {
    pic: *const PoolInCtx,
    cmds: vk.CommandBuffer,

    pub fn resolve(self: *const OneShotCommanded) !void {
        const vkdev = self.pic.gc.dev;
        const vkq = self.pic.gc.graphics_queue.handle;

        try vkdev.endCommandBuffer(self.cmds);

        const submmit_info: vk.SubmitInfo = .{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&self.cmds),
        };
        try vkdev.queueSubmit(vkq, 1, @ptrCast(&submmit_info), .null_handle);
        try vkdev.queueWaitIdle(vkq);

        vkdev.freeCommandBuffers(self.pic.pool, 1, @ptrCast(&self.cmds));
    }
    pub fn init(pic: *const PoolInCtx) !OneShotCommanded {
        const vkd = pic.gc.dev;
        var cmds: vk.CommandBuffer = undefined;

        const cb_alloc_info: vk.CommandBufferAllocateInfo = .{
            .s_type = .command_buffer_allocate_info,
            .command_pool = pic.pool,
            .level = .primary,
            .command_buffer_count = 1,
        };
        try vkd.allocateCommandBuffers(
            &cb_alloc_info,
            @ptrCast(&cmds),
        );

        const begin_info: vk.CommandBufferBeginInfo = .{
            .flags = .{ .one_time_submit_bit = true },
        };
        try vkd.beginCommandBuffer(cmds, &begin_info);

        return .{
            .pic = pic,
            .cmds = cmds,
        };
    }
};

pub const BufferData = struct {
    dvk_bfr: vk.Buffer,
    dvk_mem: vk.DeviceMemory,
    mapping: ?*anyopaque,

    pub fn deinit(self: *const BufferData, gc: *const GraphicsContext) void {
        const dev = gc.dev;
        if (self.mapping) |_| dev.unmapMemory(self.dvk_mem);
        dev.freeMemory(self.dvk_mem, null);
        dev.destroyBuffer(self.dvk_bfr, null);
    }
};

pub fn createBuffer(
    gc: *const GraphicsContext,
    mem_flags: vk.MemoryPropertyFlags,
    usage: vk.BufferUsageFlags,
    bsize: u64,
) !BufferData {
    const devk = gc.dev;
    const default_size = bsize;

    const bfr = try devk.createBuffer(&vk.BufferCreateInfo{
        .size = default_size,
        .usage = usage,
        .sharing_mode = .exclusive,
    }, null);

    const r = devk.getBufferMemoryRequirements(bfr);
    if (r.size != default_size) {
        std.debug.print("??? requested low amount of memory: requested - {d}, resulted - {d}\n", .{ default_size, r.size });
    }

    const memory = try gc.allocate(r, mem_flags);

    try gc.dev.bindBufferMemory(bfr, memory, 0);

    var mapping: ?*anyopaque = null;
    if (mem_flags.host_visible_bit) {
        mapping = try devk.mapMemory(memory, 0, r.size, .{});
    }
    return BufferData{
        .dvk_bfr = bfr,
        .dvk_mem = memory,
        .mapping = mapping,
    };
}
pub const PoolInCtx = struct {
    gc: *const GraphicsContext,
    pool: vk.CommandPool,
};

pub const FrameRecorder = struct {
    gc: *const GraphicsContext,
    pool: vk.CommandPool,
    cmgs: vk.CommandBuffer,
};

pub const GraphicsContext = struct {
    pub const CommandBuffer = vk.CommandBufferProxy;
    const Self = @This();

    allocator: Allocator,

    vkb: BaseWrapper,

    instance: Instance,
    debug_messenger: vk.DebugUtilsMessengerEXT,
    surface: vk.SurfaceKHR,
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    mem_props: vk.PhysicalDeviceMemoryProperties,

    dev: Device,
    graphics_queue: Queue,
    present_queue: Queue,

    pub fn init(allocator: Allocator, app_name: [*:0]const u8, window: *glfw.Window) !GraphicsContext {
        var self: GraphicsContext = undefined;
        self.allocator = allocator;
        self.vkb = BaseWrapper.load(c.glfwGetInstanceProcAddress);

        std.debug.print("whats the problem?\n", .{});
        if (try checkLayerSupport(&self.vkb, self.allocator) == false) {
            return error.MissingLayer;
        }

        var extension_names: std.ArrayList([*:0]const u8) = .empty;
        defer extension_names.deinit(allocator);
        try extension_names.append(allocator, vk.extensions.ext_debug_utils.name);
        // the following extensions are to support vulkan in mac os
        // see https://github.com/glfw/glfw/issues/2335
        // try extension_names.append(allocator, vk.extensions.khr_portability_enumeration.name);
        // it crush intel on intel gpu with this extension on  ^^^^^^^^^^^^^^^^^^^^^^^^^^^

        try extension_names.append(allocator, vk.extensions.khr_get_physical_device_properties_2.name);

        var glfw_exts_count: u32 = 0;
        const glfw_exts0 = glfw.getRequiredInstanceExtensions(&glfw_exts_count).?;
        try extension_names.appendSlice(allocator, @ptrCast(glfw_exts0[0..glfw_exts_count]));

        for (extension_names.items) |name| {
            std.debug.print("+++ we are looking for {s} exension\n", .{name});
        }

        const instance = try self.vkb.createInstance(&.{
            .p_application_info = &.{
                .p_application_name = app_name,
                .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
                .p_engine_name = app_name,
                .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
                .api_version = @bitCast(vk.API_VERSION_1_2),
            },

            .enabled_layer_count = required_layer_names.len,
            .pp_enabled_layer_names = @ptrCast(&required_layer_names),
            .enabled_extension_count = @intCast(extension_names.items.len),
            .pp_enabled_extension_names = extension_names.items.ptr,
            // enumerate_portability_bit_khr to support vulkan in mac os
            // see https://github.com/glfw/glfw/issues/2335
            .flags = .{ .enumerate_portability_bit_khr = false },
            // .flags = .{ .enumerate_portability_bit_khr = true }, // for apple
            // should be commented but it just warns so no big deal
        }, null);

        const vki = try allocator.create(InstanceWrapper);
        errdefer allocator.destroy(vki);
        vki.* = InstanceWrapper.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr.?);
        self.instance = Instance.init(instance, vki);
        errdefer self.instance.destroyInstance(null);

        self.debug_messenger = try self.instance.createDebugUtilsMessengerEXT(&.{
            .message_severity = .{
                //.verbose_bit_ext = true,
                //.info_bit_ext = true,
                .warning_bit_ext = true,
                .error_bit_ext = true,
            },
            .message_type = .{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
            },
            .pfn_user_callback = &debugUtilsMessengerCallback,
            .p_user_data = null,
        }, null);

        self.surface = try createSurface(self.instance, window);
        errdefer self.instance.destroySurfaceKHR(self.surface, null);

        const candidate = try pickPhysicalDevice(self.instance, allocator, self.surface);
        self.pdev = candidate.pdev;
        self.props = candidate.props;

        const dev = try initializeCandidate(self.instance, candidate);

        const vkd = try allocator.create(DeviceWrapper);
        errdefer allocator.destroy(vkd);
        vkd.* = DeviceWrapper.load(dev, self.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
        self.dev = Device.init(dev, vkd);
        errdefer self.dev.destroyDevice(null);

        self.graphics_queue = Queue.init(self.dev, candidate.queues.graphics_family);
        self.present_queue = Queue.init(self.dev, candidate.queues.present_family);

        try self.memoryPropsWithExp();
        try self.propsExplore();

        return self;
    }

    fn memoryPropsWithExp(self: *Self) !void {
        const props = self.instance.getPhysicalDeviceMemoryProperties(self.pdev);
        self.mem_props = props;
        // ---- explore area -----
        const mem_t_count = props.memory_type_count;
        const mem_h_count = props.memory_heap_count;
        std.debug.print("+++ instance info:\n", .{});
        std.debug.print("+++ memory types ({d}), memory heaps ({d})\n", .{ mem_t_count, mem_h_count });

        const my_first_memory_flags = vk.MemoryPropertyFlags{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        };
        const my_first_usage = vk.BufferUsageFlags{
            .transfer_src_bit = true,
        };
        const test_buffer = try createBuffer(self, my_first_memory_flags, my_first_usage, 4);
        std.debug.print("+++ test buffor created\n", .{});
        test_buffer.deinit(self);
    }

    fn propsExplore(self: *const Self) !void {
        const props = self.instance.getPhysicalDeviceProperties(self.pdev);

        const ubo_alingment = props.limits.min_uniform_buffer_offset_alignment;
        const sbo_alignment = props.limits.min_storage_buffer_offset_alignment;

        std.debug.print("--------------- \n", .{});
        std.debug.print("+++ essunia ubo every {}bytes\n", .{ubo_alingment});
        std.debug.print("+++ essunia sbo every {}bytes \n", .{sbo_alignment});
        std.debug.print("--------------- \n", .{});
    }

    pub fn deinit(self: GraphicsContext) void {
        self.dev.destroyDevice(null);
        self.instance.destroySurfaceKHR(self.surface, null);
        self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
        self.instance.destroyInstance(null);

        // Don't forget to free the tables to prevent a memory leak.
        self.allocator.destroy(self.dev.wrapper);
        self.allocator.destroy(self.instance.wrapper);
    }

    pub fn deviceName(self: *const GraphicsContext) []const u8 {
        return std.mem.sliceTo(&self.props.device_name, 0);
    }

    pub fn findMemoryTypeIndex(self: GraphicsContext, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
        for (self.mem_props.memory_types[0..self.mem_props.memory_type_count], 0..) |mem_type, i| {
            if (memory_type_bits & (@as(u32, 1) << @truncate(i)) != 0 and mem_type.property_flags.contains(flags)) {
                return @truncate(i);
            }
        }

        return error.NoSuitableMemoryType;
    }

    pub fn allocate(self: GraphicsContext, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
        return try self.dev.allocateMemory(&.{
            .s_type = .memory_allocate_info,
            .allocation_size = requirements.size,
            .memory_type_index = try self.findMemoryTypeIndex(requirements.memory_type_bits, flags),
        }, null);
    }
};

fn checkLayerSupport(vkb: *const BaseWrapper, alloc: Allocator) !bool {
    const available_layers = try vkb.enumerateInstanceLayerPropertiesAlloc(alloc);
    defer alloc.free(available_layers);
    std.debug.print(
        "our instance has {d} layers\n we require {d} layers\n",
        .{ available_layers.len, required_layer_names.len },
    );

    //https://claude.ai/chat/c91e18de-8740-4c55-bcd9-21280657196e
    var result = true;
    for (required_layer_names) |required_layer| {
        for (available_layers) |layer| {
            if (std.mem.eql(u8, std.mem.span(required_layer), std.mem.sliceTo(&layer.layer_name, 0))) {
                break;
            }
        } else {
            std.debug.print("_ Layer | {s} | is missing in vulkan\n", .{required_layer});
            result = false;
        }
    }
    return result;
}

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(device: Device, family: u32) Queue {
        return .{
            .handle = device.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

fn createSurface(instance: Instance, window: *glfw.Window) !vk.SurfaceKHR {
    var surface: u64 = undefined;

    if (glfw.createWindowSurface(@intFromEnum(instance.handle), window, null, &surface) != .success) {
        return error.SurfaceInitFailed;
    }

    return @enumFromInt(surface);
}

fn initializeCandidate(instance: Instance, candidate: DeviceCandidate) !vk.Device {
    const priority = [_]f32{1};
    const qci = [_]vk.DeviceQueueCreateInfo{
        .{
            .queue_family_index = candidate.queues.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
        .{
            .queue_family_index = candidate.queues.present_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
    };

    const queues_the_same = candidate.queues.graphics_family == candidate.queues.present_family;
    const queue_count: u32 = if (queues_the_same) 1 else 2;

    var sync2: vk.PhysicalDeviceSynchronization2Features = .{
        .p_next = null,
    };

    var features2 = vk.PhysicalDeviceFeatures2{
        .p_next = @ptrCast(&sync2),
        .features = undefined,
    };

    instance.getPhysicalDeviceFeatures2(candidate.pdev, &features2);

    if (sync2.synchronization_2 == .false) {
        return error.FeatureNotPresent;
    }

    const dev_create_info: vk.DeviceCreateInfo = .{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
        .p_next = &sync2,
    };

    return try instance.createDevice(candidate.pdev, &dev_create_info, null);
}

const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueAllocation,
};

const QueueAllocation = struct {
    graphics_family: u32,
    present_family: u32,
};

fn severityTag(sev: vk.DebugUtilsMessageSeverityFlagsEXT) []const u8 {
    if (sev.verbose_bit_ext) return "\x1b[34m verbose \x1b[0m";
    if (sev.info_bit_ext) return "\x1b[34m info \x1b[0m";
    if (sev.warning_bit_ext) return "\x1b[33m warning \x1b[0m";
    if (sev.error_bit_ext) return "\x1b[31m error \x1b[0m";
    return "\x1b[34m unknown\x1b[0m";
}

fn typeBit(msg_type: vk.DebugUtilsMessageTypeFlagsEXT) []const u8 {
    if (msg_type.general_bit_ext) return "general";
    if (msg_type.validation_bit_ext) return "validation";
    if (msg_type.performance_bit_ext) return "performance";
    if (msg_type.device_address_binding_bit_ext) return "device addr";
    return "unknown";
}

fn debugUtilsMessengerCallback(severity: vk.DebugUtilsMessageSeverityFlagsEXT, msg_type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(.c) vk.Bool32 {
    const severity_str = severityTag(severity);
    const type_str = typeBit(msg_type);

    const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";
    std.debug.print("[{s}][{s}]. Message:\n  {s}\n", .{ severity_str, type_str, message });
    return .false;
}

fn pickPhysicalDevice(
    instance: Instance,
    allocator: Allocator,
    surface: vk.SurfaceKHR,
) !DeviceCandidate {
    const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(pdevs);

    std.debug.print("+++ physicale device options: {d}\n", .{pdevs.len});
    for (pdevs) |pdev| {
        if (try checkSuitable(instance, pdev, allocator, surface)) |candidate| {
            return candidate;
        }
    }

    return error.NoSuitableDevice;
}

fn checkSuitable(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    allocator: Allocator,
    surface: vk.SurfaceKHR,
) !?DeviceCandidate {
    if (!try checkExtensionSupport(instance, pdev, allocator)) {
        return null;
    }

    if (!try checkSurfaceSupport(instance, pdev, surface)) {
        return null;
    }
    const queue_allocation = try allocateQueues(instance, pdev, allocator, surface);
    if (queue_allocation) |allocation| {
        var mv_props: vk.PhysicalDeviceMultiviewProperties = .{
            .max_multiview_instance_index = undefined,
            .max_multiview_view_count = undefined,
        };

        var phys_pros: vk.PhysicalDeviceProperties2 = .{
            .properties = undefined,
            .p_next = &mv_props,
        };

        instance.getPhysicalDeviceProperties2(pdev, &phys_pros);
        std.debug.print("+++ multiview props: {d} - (views), {d} - (instances)\n", .{
            mv_props.max_multiview_view_count,
            mv_props.max_multiview_instance_index,
        });

        var pds2: vk.PhysicalDeviceSynchronization2FeaturesKHR = .{ .synchronization_2 = .true };

        var pddif: vk.PhysicalDeviceDescriptorIndexingFeatures = .{
            .descriptor_binding_partially_bound = .true,
            .descriptor_binding_variable_descriptor_count = .true,
            .shader_sampled_image_array_non_uniform_indexing = .true,
            .p_next = &pds2,
        };

        var features2: vk.PhysicalDeviceFeatures2 = .{
            .features = undefined,
            .p_next = &pddif,
        };
        instance.getPhysicalDeviceFeatures2(pdev, &features2);
        var choose_cond = features2.features.sampler_anisotropy == .true;
        choose_cond = choose_cond;
        if (!choose_cond) {
            return null;
        }

        return DeviceCandidate{
            .pdev = pdev,
            .props = phys_pros.properties,
            .queues = allocation,
        };
    }

    return null;
}

fn allocateQueues(instance: Instance, pdev: vk.PhysicalDevice, allocator: Allocator, surface: vk.SurfaceKHR) !?QueueAllocation {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);
    std.debug.print("+++ device queue count {d}\n", .{families.len});

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (present_family == null and (try instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surface)) == .true) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        return QueueAllocation{
            .graphics_family = graphics_family.?,
            .present_family = present_family.?,
        };
    }

    return null;
}

fn checkSurfaceSupport(instance: Instance, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !bool {
    var format_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);

    return format_count > 0 and present_mode_count > 0;
}

fn checkExtensionSupport(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    allocator: Allocator,
) !bool {
    const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
    defer allocator.free(propsv);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}

pub const baked = struct {
    pub const DSetInit = struct {
        usage: UsageType,
        memory_property: vk.MemoryPropertyFlags,
        shader_stage: vk.ShaderStageFlags,
    };

    pub const UsageType = struct {
        usage_flag: vk.BufferUsageFlags,
        descriptor_type: vk.DescriptorType,
    };

    pub const usage_src: vk.BufferUsageFlags = .{ .transfer_src_bit = true };
    pub const usage_vert_dst: vk.BufferUsageFlags = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true };
    pub const usage_as_uniform: vk.BufferUsageFlags = .{ .uniform_buffer_bit = true };
    pub const usage_as_storage: vk.BufferUsageFlags = .{ .storage_buffer_bit = true };

    const uniform_usage: UsageType = .{
        .usage_flag = usage_as_uniform,
        .descriptor_type = .uniform_buffer,
    };
    const uniform_dynamic_usage: UsageType = .{
        .usage_flag = usage_as_uniform,
        .descriptor_type = .uniform_buffer_dynamic,
    };
    const storage_usage: UsageType = .{
        .usage_flag = usage_as_storage,
        .descriptor_type = .storage_buffer,
    };
    const storage_dynamic_usage: UsageType = .{
        .usage_flag = usage_as_storage,
        .descriptor_type = .storage_buffer_dynamic,
    };
    const texture_usage: UsageType = .{ // also for bindles
        // buffer in descriptor is not used by texture btw.
        .usage_flag = usage_as_storage,
        .descriptor_type = .combined_image_sampler,
    };

    pub const memory_cpu: vk.MemoryPropertyFlags = .{
        .host_visible_bit = true,
        .host_coherent_bit = true,
    };

    pub const memory_gpu: vk.MemoryPropertyFlags = .{
        .device_local_bit = true,
    };

    pub const shader_both: vk.ShaderStageFlags = .{ .vertex_bit = true, .fragment_bit = true };
    pub const shader_vert_only: vk.ShaderStageFlags = .{ .vertex_bit = true };
    pub const shader_frag_only: vk.ShaderStageFlags = .{ .fragment_bit = true };

    pub const uniform_frag_vert = DSetInit{
        .usage = uniform_usage,
        .memory_property = memory_cpu,
        .shader_stage = shader_both,
    };
    pub const uniformd_frag_vert = DSetInit{
        .usage = uniform_dynamic_usage,
        .memory_property = memory_cpu,
        .shader_stage = shader_both,
    };
    pub const storage_frag_vert = DSetInit{
        .usage = storage_usage,
        .memory_property = memory_cpu,
        .shader_stage = shader_both,
    };
    pub const storaged_frag_vert = DSetInit{
        .usage = storage_dynamic_usage,
        .memory_property = memory_cpu,
        .shader_stage = shader_both,
    };
    pub const texture_frag = DSetInit{
        .usage = texture_usage,
        .memory_property = memory_cpu,
        .shader_stage = shader_frag_only,
    };

    pub const BindingInfo = struct {
        set_binding: u32,
        size: u32,
        num: u32 = 1,
    };

    const depth_flag: vk.ImageAspectFlags = .{
        .depth_bit = true,
    };
    const color_flag: vk.ImageAspectFlags = .{
        .color_bit = true,
    };

    pub const depth_img_subrng: vk.ImageSubresourceRange = .{
        .aspect_mask = depth_flag,
        .base_mip_level = 0,
        .level_count = 1,
        .base_array_layer = 0,
        .layer_count = 1,
    };

    pub const color_img_subrng: vk.ImageSubresourceRange = .{
        .aspect_mask = color_flag,
        .base_mip_level = 0,
        .level_count = 1,
        .base_array_layer = 0,
        .layer_count = 1,
    };

    pub const color_bfr2img_sublyr: vk.ImageSubresourceLayers = .{
        .aspect_mask = color_flag,
        .mip_level = 0,
        .base_array_layer = 0,
        .layer_count = 1,
    };

    pub const undefined_to_transfered: t.TransitPrep = .{
        .accesses = .{
            .src = .{},
            .dst = .{
                .transfer_write_bit = true,
            },
        },
        .stages = .{
            .src = .{
                .top_of_pipe_bit = true,
            },
            .dst = .{
                .transfer_bit = true,
            },
        },
    };

    pub const transfered_to_fragment_readed: t.TransitPrep = .{
        .accesses = .{
            .src = .{
                .transfer_write_bit = true,
            },
            .dst = .{
                .shader_read_bit = true,
            },
        },
        .stages = .{
            .src = .{
                .transfer_bit = true,
            },
            .dst = .{
                .fragment_shader_bit = true,
            },
        },
    };

    pub const identity_mapping: vk.ComponentMapping = .{
        .a = .identity,
        .b = .identity,
        .g = .identity,
        .r = .identity,
    };
};
