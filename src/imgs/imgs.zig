const std = @import("std");
const vk = @import("vulkan-zig");

const t = @import("../types.zig");
const m = @import("../math.zig");
const swpchn = @import("../swapchain.zig");
const sht = @import("../shaders/types.zig");
const shut = @import("../shaders/utils.zig");

const gm = @import("../graphics_context.zig");
const GraphicsContext = gm.GraphicsContext;

const root = @import("root.zig");
const memory = @import("memory.zig");
pub const demo_tex_size = root.demo_tex_r;
// Checkboard texture spawned in memory
pub const demo_tex_rgb = root.demo_tex_rgb;
// Just red
pub const demo_tex_r = root.demo_tex_r;

pub const LinearImageAllocator = memory.LinearImageAllocator;
pub fn imgMemTypeInfer(gc: *const GraphicsContext, flags: vk.MemoryPropertyFlags) !u32 {
    return memory.imgMemTypeInfer(gc, flags);
}

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
