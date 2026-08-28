const std = @import("std");
const vk = @import("vulkan-zig");
const gm = @import("graphics_context.zig");
const GraphicsContext = gm.GraphicsContext;

const t = @import("types.zig");
const m = @import("math.zig");
const swpchn = @import("swapchain.zig");
const sht = @import("shaders/types.zig");
const shut = @import("shaders/utils.zig");

// Checkboard texture spawned in memory
const pixel_size = 4;
const field_x_side = 16;
const field_y_side = 4;

const m_img_side = 64;
pub const demo_tex_size = (m_img_side * m_img_side) * pixel_size;
pub const demo_tex_rgb = blk: {
    const spot_num = m_img_side * m_img_side;
    var lut: [spot_num * pixel_size]u8 = undefined;
    const colors: []const [pixel_size]u8 = &.{
        .{ 255, 255, 255, 255 },
        .{ 128, 128, 128, 255 },
    };
    @setEvalBranchQuota(spot_num);
    for (0..spot_num) |i| {
        const at = i * pixel_size;
        const row = i / m_img_side;
        const a = if (@mod(row, field_x_side * 2) < field_x_side) 0 else 1;
        const b = 1 - a;

        var pixel: [pixel_size]u8 = colors[a];
        if (@mod(i, field_y_side * 2) < field_y_side) {
            pixel = colors[b];
        }

        @memcpy(lut[at .. at + 4], &pixel);
    }
    break :blk lut;
};
pub const demo_tex_r = blk: {
    const spot_num = m_img_side * m_img_side;
    var lut: [spot_num * pixel_size]u8 = undefined;
    const uniform_color: [pixel_size]u8 = .{ 255, 0, 0, 255 };

    @setEvalBranchQuota(spot_num);
    for (0..spot_num) |i| {
        const at = i * pixel_size;
        @memcpy(lut[at .. at + 4], &uniform_color);
    }
    break :blk lut;
};

pub fn imgMemTypeInfer(gc: *const GraphicsContext, flags: vk.MemoryPropertyFlags) !u32 {
    const img_extent: vk.Extent3D = .{ .height = 64, .width = 64, .depth = 1 };

    const Pair = struct { usage: vk.ImageUsageFlags, format: vk.Format };
    const configs: []const Pair = &.{
        Pair{
            .format = .d32_sfloat,
            .usage = .{
                .depth_stencil_attachment_bit = true,
                .transfer_src_bit = true,
            },
        },
        Pair{
            .format = .a8b8g8r8_srgb_pack32,
            .usage = .{
                .color_attachment_bit = true,
                .transfer_src_bit = true,
            },
        },
    };

    var reqs: [configs.len]vk.MemoryRequirements = undefined;

    var base: vk.ImageCreateInfo = .{
        .image_type = .@"2d",
        .format = undefined,
        .extent = img_extent,
        .tiling = .optimal,
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .usage = undefined,
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    };

    for (0.., configs) |i, config| {
        base.usage = config.usage;
        base.format = config.format;

        const img = try gc.dev.createImage(&base, null);
        defer gc.dev.destroyImage(img, null);

        reqs[i] = gc.dev.getImageMemoryRequirements(img);
    }

    const basic_type_idx = try gc.findMemoryTypeIndex(reqs[0].memory_type_bits, flags);

    for (reqs) |req| {
        const type_idx = try gc.findMemoryTypeIndex(req.memory_type_bits, flags);
        if (basic_type_idx != type_idx) {
            return error.different_images_uses_different_memory_type;
        }
    }
    return basic_type_idx;
}

pub const LinearImageAllocator = struct {
    dev_mem: vk.DeviceMemory,
    mem_idx: u32,

    // book keeping
    img_count: u32 = 0,
    beg: u64 = 0,
    end: u64 = 0,
    total: u64,

    pub fn deinit(self: *const LinearImageAllocator, gc: *const GraphicsContext) void {
        gc.dev.freeMemory(self.dev_mem, null);
    }

    pub fn init(gc: *const GraphicsContext, flags: vk.MemoryPropertyFlags) !LinearImageAllocator {
        const mem_idx = try imgMemTypeInfer(gc, flags);
        const total_size = 256 * 1024 * 1024; //256 MB
        const mem = try gc.dev.allocateMemory(&.{
            .s_type = .memory_allocate_info,

            .allocation_size = total_size,
            .memory_type_index = mem_idx,
        }, null);

        return LinearImageAllocator{
            .dev_mem = mem,
            .mem_idx = mem_idx,
            .total = total_size,
        };
    }

    pub fn imgAlloc(self: *LinearImageAllocator, gc: *const GraphicsContext, img: vk.Image) !void {
        const new_img_reqs = gc.dev.getImageMemoryRequirements(img);

        const missed_by: u64 = @mod(self.end, new_img_reqs.alignment);

        if (missed_by != 0) {
            self.end += (new_img_reqs.alignment - missed_by);
        }

        const beg_of_alloc = self.end;
        const end_of_alloc = beg_of_alloc + new_img_reqs.size;
        if (end_of_alloc > self.total) {
            return error.OutOfMemory;
        }

        std.debug.print("new img alloc at 0x{x} of bytes {d}\n", .{ beg_of_alloc, new_img_reqs.size });

        try gc.dev.bindImageMemory(img, self.dev_mem, beg_of_alloc);
        self.img_count += 1;
        self.end = end_of_alloc;
    }

    pub fn imgFree(self: *LinearImageAllocator, img: vk.Image) void {
        _ = self;
        _ = img;

        std.debug.print("yes yes we dealocating xD\n", .{});
    }
};

pub const DepthImage = struct {
    const Self = @This();
    vk_format: vk.Format,
    dvk_img: vk.Image,
    dvk_img_view: vk.ImageView,

    fn getDepthFormat(gc: *const GraphicsContext) !vk.Format {
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

    pub fn init(gc: *const GraphicsContext, imga: *LinearImageAllocator, extent: vk.Extent2D) !Self {
        const devk = gc.dev;
        const depth_format = try Self.getDepthFormat(gc);
        _ = hasSetncilComponent(depth_format);

        std.debug.print("8888888 depth format is {s}\n", .{@tagName(depth_format)});

        const d_img_create_info: vk.ImageCreateInfo = .{
            .image_type = .@"2d",
            .format = depth_format,
            .extent = .{
                .height = extent.height,
                .width = extent.width,
                .depth = 1,
            },
            .tiling = .optimal,
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .usage = .{
                .depth_stencil_attachment_bit = true,
            },
            .sharing_mode = .exclusive,
            .initial_layout = .undefined,
        };

        const d_img = try devk.createImage(&d_img_create_info, null);
        errdefer devk.destroyImage(d_img, null);

        try imga.imgAlloc(gc, d_img);
        errdefer imga.imgFree(d_img);

        const img_viu_info: vk.ImageViewCreateInfo = .{
            .view_type = .@"2d",
            .format = depth_format,
            .subresource_range = gm.baked.depth_img_subrng,
            .image = d_img,
            .components = gm.baked.identity_mapping,
        };

        const img_viu = try gc.dev.createImageView(&img_viu_info, null);

        return Self{
            .dvk_img_view = img_viu,
            .dvk_img = d_img,
            .vk_format = depth_format,
        };
    }
    pub fn deinit(self: Self, gc: *const GraphicsContext, imga: *LinearImageAllocator) void {
        const devk = gc.dev;
        devk.destroyImageView(self.dvk_img_view, null);
        devk.destroyImage(self.dvk_img, null);
        imga.imgFree(self.dvk_img);
    }
};

pub const RGBImage = struct {
    pub fn init(gc: *const GraphicsContext, g: sht.GridSize) !VkImage {
        const format: vk.Format = .a8b8g8r8_srgb_pack32;
        return VkImage.init(gc, g, format);
    }
};

pub const U16Image = struct {
    pub fn init(gc: *const GraphicsContext, g: sht.GridSize) !VkImage {
        return VkImage.init(gc, g, .r16_unorm);
    }
};

pub const U8Image = struct {
    pub fn init(gc: *const GraphicsContext, g: sht.GridSize) !VkImage {
        return VkImage.init(gc, g, .r8_unorm);
    }
};

pub const VkImage = struct {
    const show_size_at_init = false;
    const Self = @This();

    gc: *const GraphicsContext,
    dvk_img: vk.Image,
    dvk_mem: vk.DeviceMemory,
    dvk_size: usize,
    vk_format: vk.Format,
    vk_img_view: ?vk.ImageView = null,
    vk_sampler: ?vk.Sampler = null,

    pub fn memSize(g: sht.GridSize) usize {
        return g.total * @sizeOf(u32);
    }

    pub fn deinit(self: *Self) void {
        const devk = self.gc.dev;
        if (self.vk_sampler) |_sampler| {
            devk.destroySampler(_sampler, null);
        }
        if (self.vk_img_view) |_img_view| {
            devk.destroyImageView(_img_view, null);
        }

        devk.destroyImage(self.dvk_img, null);
        devk.freeMemory(self.dvk_mem, null);
    }

    pub fn init(gc: *const GraphicsContext, g: sht.GridSize, format: vk.Format) !Self {
        const devk = gc.dev;

        const img_create_info: vk.ImageCreateInfo = .{
            .image_type = .@"2d",
            .format = format,
            .extent = .{ .height = g.h, .width = g.w, .depth = 1 },
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

        if (Self.show_size_at_init) shut.printGrid(&g, "+++ rgb_img_init");

        const vk_img = try devk.createImage(&img_create_info, null);
        errdefer devk.destroyImage(vk_img, null);

        const mem_req = devk.getImageMemoryRequirements(vk_img);
        const vk_mem = try gc.allocate(
            mem_req,
            gm.baked.memory_gpu,
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
            .subresource_range = gm.baked.color_img_subrng,
            .components = gm.baked.identity_mapping,
        };

        self.vk_img_view = try devk.createImageView(&image_view_create_info, null);
    }

    const ESamplerMode = enum(u8) {
        nearest = 0,
        font,
        default,
    };

    pub fn createSampler(self: *Self, gc: *const GraphicsContext, mode: ESamplerMode) !void {
        const props = gc.instance.getPhysicalDeviceProperties(gc.pdev);
        const filter = switch (mode) {
            .nearest => vk.Filter.nearest,
            .font => vk.Filter.linear,
            .default => vk.Filter.linear,
        };
        const sample_create_info: vk.SamplerCreateInfo = .{
            .mag_filter = filter,
            .min_filter = filter,
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
};

pub fn vulkanTexture(
    pic: *const gm.PoolInCtx,
    g64: sht.GridSize,
    pixdata: []const u8,
    mode: VkImage.ESamplerMode,
) !VkImage {
    var test_img = try gm.RGBImage.init(pic.gc, g64);
    errdefer test_img.deinit();

    try texPrep(pic, g64, pixdata, &test_img, mode);
    return test_img;
}
pub fn texPrep(
    pic: *const gm.PoolInCtx,
    g64: sht.GridSize,
    pixdata: []const u8,
    test_img: *VkImage,
    mode: VkImage.ESamplerMode,
) !void {
    const buff_size = test_img.dvk_size;
    var transport_bfr = try gm.createBuffer( //TODO: maybe one omnipresent buffor for img data copying?
        pic.gc,
        gm.baked.memory_cpu,
        gm.baked.usage_src,
        buff_size,
    );
    defer transport_bfr.deinit(pic.gc);

    const dst_layout: vk.ImageLayout = .transfer_dst_optimal;
    const shader_read_layout: vk.ImageLayout = .shader_read_only_optimal;

    const one_shot = try gm.OneShotCommanded.init(pic, 3);

    // prepare to recive transfer
    try imgLTrans(pic.gc, one_shot.cmds, .{
        .old_layout = .undefined,
        .new_layout = dst_layout,
        .image = test_img.dvk_img,
        .sync_point = gm.baked.undefined_to_transfered_2,
    });

    // transport image through a buffer
    const mapping: [*]u8 = transport_bfr.memMapping();
    @memcpy(mapping, pixdata);
    try bfr2ImgCopy(pic.gc, one_shot.cmds, .{
        .buffer = transport_bfr.dvk_bfr,
        .image = test_img.dvk_img,
        .layout = dst_layout,
        .g = g64,
    });

    try imgLTrans(pic.gc, one_shot.cmds, .{
        .old_layout = dst_layout,
        .new_layout = shader_read_layout,
        .image = test_img.dvk_img,
        .sync_point = gm.baked.transfered_to_fragment_readed_2,
    });

    try one_shot.resolve();

    try test_img.createImageView(pic.gc);
    try test_img.createSampler(pic.gc, mode);
}

pub fn imgLTrans(gc: *const gm.GraphicsContext, cmds: vk.CommandBuffer, cfg: t.ImgLTranConfig) !void {
    const family_ignored: u32 = 0;
    // const zero_mask: u32 = 0;

    const img_lyr_barriers: []const vk.ImageMemoryBarrier = &.{
        vk.ImageMemoryBarrier{
            .old_layout = cfg.old_layout,
            .new_layout = cfg.new_layout,
            .src_queue_family_index = family_ignored,
            .dst_queue_family_index = family_ignored,
            .image = cfg.image,
            .subresource_range = gm.baked.color_img_subrng,
            .src_access_mask = cfg.sync_point.src.access,
            .dst_access_mask = cfg.sync_point.dst.access,
        },
    };
    gc.dev.cmdPipelineBarrier(
        cmds,
        cfg.sync_point.src.stage,
        cfg.sync_point.dst.stage,
        .{},
        null,
        null,
        img_lyr_barriers,
    );
}

const BfrToImgCpyCfg = struct {
    g: sht.GridSize,
    image: vk.Image,
    buffer: vk.Buffer,
    layout: vk.ImageLayout,
};

pub fn bfr2ImgCopy(gc: *const gm.GraphicsContext, cmds: vk.CommandBuffer, cfg: BfrToImgCpyCfg) !void {
    const bfr_img_cpy: []const vk.BufferImageCopy = &.{
        vk.BufferImageCopy{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,

            .image_subresource = gm.baked.color_bfr2img_sublyr,
            .image_offset = .{ .x = 0, .y = 0, .z = 0 },
            .image_extent = .{
                .width = cfg.g.w,
                .height = cfg.g.h,
                .depth = 1,
            },
        },
    };

    gc.dev.cmdCopyBufferToImage(
        cmds,
        cfg.buffer,
        cfg.image,
        cfg.layout,
        bfr_img_cpy,
    );
}

pub const ManyImages = struct {
    array: std.ArrayList(VkImage),
    _gpa: std.mem.Allocator,
    pub fn init(gpa: std.mem.Allocator) !ManyImages {
        return .{
            .array = try .initCapacity(gpa, 256),
            ._gpa = gpa,
        };
    }
    pub fn deinit(self: *ManyImages) void {
        for (self.array.items) |*img| img.deinit();
        self.array.deinit(self._gpa);
    }

    pub fn append(self: *ManyImages, item: *const VkImage) !void {
        return self.array.append(self._gpa, item.*);
    }
};
