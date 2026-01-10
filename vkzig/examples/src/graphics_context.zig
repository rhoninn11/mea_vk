const std = @import("std");

const glfw = @import("third_party/glfw.zig");
const vk = @import("third_party/vk.zig");

const c = @import("c.zig");
const Allocator = std.mem.Allocator;

const swpchn = @import("swapchain.zig");

const required_layer_names = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};

const required_device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

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

pub const LTransRelated = struct {
    const Stages = struct {
        src: vk.PipelineStageFlags,
        dst: vk.PipelineStageFlags,
    };
    const Accesses = struct {
        src: vk.AccessFlags,
        dst: vk.AccessFlags,
    };

    stages: Stages,
    accesses: Accesses,
};

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

    const uniform_usage: UsageType = .{
        .usage_flag = .{
            .uniform_buffer_bit = true,
        },
        .descriptor_type = .uniform_buffer,
    };
    const storage_usage: UsageType = .{
        .usage_flag = .{
            .storage_buffer_bit = true,
        },
        .descriptor_type = .storage_buffer,
    };

    pub const cpu_accesible_memory: vk.MemoryPropertyFlags = .{
        .host_visible_bit = true,
        .host_coherent_bit = true,
    };

    pub const uniform_frag_vert = DSetInit{
        .usage = uniform_usage,
        .memory_property = cpu_accesible_memory,
        .shader_stage = .{
            .vertex_bit = true,
            .fragment_bit = true,
        },
    };
    pub const storage_frag_vert = DSetInit{
        .usage = storage_usage,
        .memory_property = cpu_accesible_memory,
        .shader_stage = .{
            .vertex_bit = true,
            .fragment_bit = true,
        },
    };

    pub const UniformInfo = struct {
        location: u32,
        size: u32,
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

    pub const undefined_to_transfered: LTransRelated = .{
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

    pub const transfered_to_fragment_readed: LTransRelated = .{
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
};

// imgs
pub const RGBImage = struct {
    const Self = @This();

    gc: *const GraphicsContext,
    dvk_img: vk.Image,
    dvk_mem: vk.DeviceMemory,
    dvk_size: usize,

    pub fn init(gc: *const GraphicsContext, x: u8, y: u8) !Self {
        const devk = gc.dev;

        const img_create_info: vk.ImageCreateInfo = .{
            .image_type = .@"2d",
            .format = .a8b8g8r8_uint_pack32,
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
            baked.cpu_accesible_memory,
        );
        errdefer devk.freeMemory(vk_mem, null);

        try devk.bindImageMemory(vk_img, vk_mem, 0);

        // gfctx.createBuffer(gc, gfctx.baked.cpu_accesible_memory, mem_req.size , .{ .transfer_src_bit = true });
        return Self{
            .gc = gc,
            .dvk_img = vk_img,
            .dvk_mem = vk_mem,
            .dvk_size = mem_req.size,
        };
    }

    pub fn deinit(self: *Self) void {
        const devk = self.gc.dev;
        devk.freeMemory(self.dvk_mem, null);
        devk.destroyImage(self.dvk_img, null);
    }
};

const DepthImage = struct {
    const Self = @This();
    img: ?vk.Image = null,
    dev_mem: ?vk.DeviceMemory = null,
    img_view: ?vk.ImageView = null,

    fn getFormat(gc: *const GraphicsContext) !vk.Format {
        return swpchn.findSupportedFormat(
            gc,
            &.{ vk.Format.d32_sfloat, vk.Format.d32_sfloat_s8_uint, vk.Format.d24_unorm_s8_uint },
            vk.ImageTiling.optimal,
            .{ .depth_stencil_attachment_bit = true },
        );
    }
    fn hasSetncilComponent(format: vk.Format) bool {
        return format == .d32_sfloat_s8_uint or format == .d24_unorm_s8_uint;
    }

    pub fn init(gc: *const GraphicsContext) !Self {
        const fmt = try Self.getFormat(gc);
        _ = hasSetncilComponent(fmt);

        // const depth_aspect_flag: vk.ImageAspectFlags = .{
        //     .depth_bit = true,
        // };
        // const no_swizzle_mapping: vk.ComponentMapping = .{
        //     .r = .identity,
        //     .g = .identity,
        //     .b = .identity,
        //     .a = .identity,
        // };

        // const img_viu_info: vk.ImageViewCreateInfo = .{
        //     .s_type = .image_view_create_info,
        //     .view_type = .@"2d",
        //     .format = fmt,
        //     .subresource_range = .{
        //         .aspect_mask = depth_aspect_flag,
        //         .base_mip_level = 0,
        //         .level_count = 1,
        //         .base_array_layer = 0,
        //         .layer_count = 1,
        //     },
        //     .image = .null_handle,
        //     .components = no_swizzle_mapping,
        // };

        // const img_viu = try gc.dev.createImageView(&img_viu_info, null);

        // return Self{
        //     .img_view = img_viu,
        // };
        return Self{};
    }
};

pub fn beginSingleCmd(gc: *const GraphicsContext, pool: vk.CommandPool) !vk.CommandBuffer {
    const devk = gc.dev;
    var bfr: vk.CommandBuffer = undefined;

    const cb_alloc_info: vk.CommandBufferAllocateInfo = .{
        .s_type = .command_buffer_allocate_info,
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    };
    try devk.allocateCommandBuffers(
        &cb_alloc_info,
        @ptrCast(&bfr),
    );

    const begin_info: vk.CommandBufferBeginInfo = .{
        .flags = .{ .one_time_submit_bit = true },
    };
    try devk.beginCommandBuffer(bfr, &begin_info);

    return bfr;
}

pub fn endSingleCmd(gc: *const GraphicsContext, cmd_buff: vk.CommandBuffer) !void {
    const devk = gc.dev;
    try devk.endCommandBuffer(cmd_buff);

    const submmit_info: vk.SubmitInfo = .{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmd_buff),
    };
    const vkq = gc.graphics_queue.handle;
    try devk.queueSubmit(vkq, 1, @ptrCast(&submmit_info), .null_handle);
    try devk.queueWaitIdle(vkq);
}

pub const BufferData = struct {
    dvk_bfr: vk.Buffer,
    dvk_mem: vk.DeviceMemory,
    mapping: ?*anyopaque,

    pub fn deinit(self: BufferData, dev: vk.DeviceProxy) void {
        dev.destroyBuffer(self.dvk_bfr, null);
        dev.freeMemory(self.dvk_mem, null);
    }
};
pub fn createBuffer(
    gc: *const GraphicsContext,
    mem_flags: vk.MemoryPropertyFlags,
    bsize: u64,
    usage: vk.BufferUsageFlags,
) !BufferData {
    const devk = gc.dev;
    const default_size = bsize;

    const bfr = try devk.createBuffer(&vk.BufferCreateInfo{
        .s_type = .buffer_create_info,
        .size = default_size,
        .sharing_mode = .exclusive,
        .usage = usage,
    }, null);

    const r = devk.getBufferMemoryRequirements(bfr);
    if (r.size != default_size) {
        std.debug.print("??? requested low amount of memory: requested - {d}, resulted - {d}\n", .{ default_size, r.size });
    }

    const memory = try gc.allocate(r, mem_flags);
    try gc.dev.bindBufferMemory(bfr, memory, 0);

    return BufferData{
        .dvk_bfr = bfr,
        .dvk_mem = memory,
        .mapping = try devk.mapMemory(memory, 0, r.size, .{}),
    };
}
pub const GraphicsContext = struct {
    pub const CommandBuffer = vk.CommandBufferProxy;

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
        _ = glfw_exts0;
        const glfw_exts = c.glfwGetRequiredInstanceExtensions(&glfw_exts_count);
        try extension_names.appendSlice(allocator, @ptrCast(glfw_exts[0..glfw_exts_count]));
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
            .flags = .{ .enumerate_portability_bit_khr = true },
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

        // ---- explore area -----

        self.mem_props = self.instance.getPhysicalDeviceMemoryProperties(self.pdev);
        const mem_t_count = self.mem_props.memory_type_count;
        const mem_h_count = self.mem_props.memory_heap_count;
        std.debug.print("+++ instance info:\n", .{});
        std.debug.print("+++ memory types ({d}), memory heaps ({d})\n", .{ mem_t_count, mem_h_count });

        const default_memory_flags = vk.MemoryPropertyFlags{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        };
        const usage = vk.BufferUsageFlags{
            .transfer_src_bit = true,
        };
        const test_buffer = try createBuffer(&self, default_memory_flags, 4, usage);
        std.debug.print("+++ test buffor created\n", .{});
        self.dev.destroyBuffer(test_buffer.dvk_bfr, null);
        self.dev.freeMemory(test_buffer.dvk_mem, null);

        return self;
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

    const queue_count: u32 = if (candidate.queues.graphics_family == candidate.queues.present_family)
        1
    else
        2;

    return try instance.createDevice(candidate.pdev, &.{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
    }, null);
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

fn debugUtilsMessengerCallback(severity: vk.DebugUtilsMessageSeverityFlagsEXT, msg_type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(.c) vk.Bool32 {
    const severity_str = if (severity.verbose_bit_ext) "verbose" else if (severity.info_bit_ext) "info" else if (severity.warning_bit_ext) "warning" else if (severity.error_bit_ext) "error" else "unknown";

    const type_str = if (msg_type.general_bit_ext) "general" else if (msg_type.validation_bit_ext) "validation" else if (msg_type.performance_bit_ext) "performance" else if (msg_type.device_address_binding_bit_ext) "device addr" else "unknown";

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

    if (try allocateQueues(instance, pdev, allocator, surface)) |allocation| {
        const props = instance.getPhysicalDeviceProperties(pdev);
        return DeviceCandidate{
            .pdev = pdev,
            .props = props,
            .queues = allocation,
        };
    }

    return null;
}

fn allocateQueues(instance: Instance, pdev: vk.PhysicalDevice, allocator: Allocator, surface: vk.SurfaceKHR) !?QueueAllocation {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);

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
