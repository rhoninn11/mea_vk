const vk = @import("third_party/vk.zig");
const gm = @import("graphics_context.zig");
const GraphicsContext = gm.GraphicsContext;

const t = @import("types.zig");
const swpchn = @import("swapchain.zig");

// Checkboard texture spawned in memory
const pixel_size = 4;
const field_x_side = 16;
const field_y_side = 4;

const m_img_side = 64;
const m_rgb_tex = blk: {
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

pub fn vulkanTexture(pic: *const gm.PoolInCtx) !gm.RGBImage {
    var test_img = try gm.RGBImage.init(pic.gc, 64, 64);

    const buff_size = test_img.dvk_size;
    const src_buff = try gm.createBuffer(
        pic.gc,
        gm.baked.memory_cpu,
        gm.baked.usage_src,
        buff_size,
    );
    defer src_buff.deinit(pic.gc);

    const src_data = m_rgb_tex;
    const src_mapping: [*]u8 = @ptrCast(@alignCast(src_buff.mapping));
    @memcpy(src_mapping[0..src_data.len], src_data[0..src_data.len]);

    const dst_layout: vk.ImageLayout = .transfer_dst_optimal;
    const shader_read_layout: vk.ImageLayout = .shader_read_only_optimal;

    try imgLTrans(pic, .{
        .old_layout = .undefined,
        .new_layout = dst_layout,
        .image = test_img.dvk_img,
        .format = test_img.vk_format,
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
        .format = test_img.vk_format,
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
        one_shot.cbfr,
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
    const devk = cmd_ctx.gc.dev;

    const one_shot = try gm.OneShotCommanded.init(cmd_ctx);

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
    devk.cmdCopyBufferToImage(
        one_shot.cbfr,
        cfg.buffer,
        cfg.image,
        cfg.layout,
        1,
        @ptrCast(&bfr_img_cpy),
    );

    try one_shot.resolve();
}
