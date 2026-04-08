const vk = @import("third_party/vk.zig");
const gm = @import("graphics_context.zig");
const GraphicsContext = gm.GraphicsContext;

const t = @import("types.zig");
const m = @import("math.zig");
const swpchn = @import("swapchain.zig");

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

pub const DepthImage = struct {
    const Self = @This();
    vk_format: vk.Format,
    dvk_img: vk.Image,
    dvk_mem: vk.DeviceMemory,
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

    pub fn init(gc: *const GraphicsContext, extent: vk.Extent2D) !Self {
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

        const mem_req = devk.getImageMemoryRequirements(d_img);
        const vk_mem = try gc.allocate(
            mem_req,
            gm.baked.memory_gpu,
        );
        errdefer devk.freeMemory(vk_mem, null);

        try devk.bindImageMemory(d_img, vk_mem, 0);

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
            .dvk_mem = vk_mem,
            .dvk_img = d_img,
            .vk_format = depth_format,
        };
    }
    pub fn deinit(self: Self, gc: *const GraphicsContext) void {
        const devk = gc.dev;
        devk.destroyImageView(self.dvk_img_view, null);
        devk.destroyImage(self.dvk_img, null);
        devk.freeMemory(self.dvk_mem, null);
    }
};

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

pub fn vulkanTexture(pic: *const gm.PoolInCtx, pixdata: []const u8) !gm.RGBImage {
    var test_img = try gm.RGBImage.init(pic.gc, 64, 64);

    const buff_size = test_img.dvk_size;
    const src_buff = try gm.createBuffer(
        pic.gc,
        gm.baked.memory_cpu,
        gm.baked.usage_src,
        buff_size,
    );
    defer src_buff.deinit(pic.gc);
    const mapping: [*]u8 = @ptrCast(@alignCast(src_buff.mapping));
    @memcpy(mapping, pixdata);

    const dst_layout: vk.ImageLayout = .transfer_dst_optimal;
    const shader_read_layout: vk.ImageLayout = .shader_read_only_optimal;

    try imgLTrans(pic, .{
        .old_layout = .undefined,
        .new_layout = dst_layout,
        .image = test_img.dvk_img,
        .flags = gm.baked.undefined_to_transfered,
    });

    try bfr2ImgCopy(pic, .{
        .buffer = src_buff.dvk_bfr,
        .image = test_img.dvk_img,
        .layout = dst_layout,
    });

    try imgLTrans(pic, .{
        .old_layout = dst_layout,
        .new_layout = shader_read_layout,
        .image = test_img.dvk_img,
        .flags = gm.baked.transfered_to_fragment_readed,
    });

    try test_img.createImageView(pic.gc);
    try test_img.createSampler(pic.gc);

    return test_img;
}

pub fn imgLTrans(cmd_ctx: *const gm.PoolInCtx, cfg: t.ImgLTranConfig) !void {
    const devk = cmd_ctx.gc.dev;
    const family_ignored: u32 = 0;
    // const zero_mask: u32 = 0;

    const one_shot = try gm.OneShotCommanded.init(cmd_ctx);

    const img_lyr_barriers: []const vk.ImageMemoryBarrier = &.{
        vk.ImageMemoryBarrier{
            .s_type = .image_memory_barrier,
            .old_layout = cfg.old_layout,
            .new_layout = cfg.new_layout,
            .src_queue_family_index = family_ignored,
            .dst_queue_family_index = family_ignored,
            .image = cfg.image,
            .subresource_range = gm.baked.color_img_subrng,
            .src_access_mask = cfg.flags.accesses.src,
            .dst_access_mask = cfg.flags.accesses.dst,
        },
    };
    devk.cmdPipelineBarrier(
        one_shot.cmds,
        cfg.flags.stages.src,
        cfg.flags.stages.dst,
        .{},
        0,
        null,
        0,
        null,
        @intCast(img_lyr_barriers.len),
        img_lyr_barriers.ptr,
    );

    try one_shot.resolve();
}

const BfrToImgCpyCfg = struct {
    image: vk.Image,
    buffer: vk.Buffer,
    layout: vk.ImageLayout,
};

pub fn bfr2ImgCopy(cmd_ctx: *const gm.PoolInCtx, cfg: BfrToImgCpyCfg) !void {
    const bfr_img_cpy: vk.BufferImageCopy = .{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_extent = .{
            .width = m_img_side,
            .height = m_img_side,
            .depth = 1,
        },
        .image_subresource = gm.baked.color_bfr2img_sublyr,
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
    };

    const one_shot = try gm.OneShotCommanded.init(cmd_ctx);
    cmd_ctx.gc.dev.cmdCopyBufferToImage(
        one_shot.cmds,
        cfg.buffer,
        cfg.image,
        cfg.layout,
        1,
        @ptrCast(&bfr_img_cpy),
    );

    try one_shot.resolve();
}
