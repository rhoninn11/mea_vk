const std = @import("std");

const glfw = @import("third_party/glfw.zig");
const vk = @import("third_party/vk.zig");
const gftx = @import("graphics_context.zig");

const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Swapchain = @import("swapchain.zig").Swapchain;
const addons = @import("addons.zig");

const baked = @import("baked.zig");

const helpers = @import("helpers.zig");
const vertex = @import("vertex.zig");

const Vertex = vertex.Vertex;

const BufforingVert = Buffering(Vertex);
const Allocator = std.mem.Allocator;

const vert_spv align(@alignOf(u32)) = @embedFile("vertex_shader").*;
const frag_spv align(@alignOf(u32)) = @embedFile("fragment_shader").*;

const app_name = "vulkan-zig triangle example";
const future_app_name = "oct_calculator";

fn Buffering(Base: type) type {
    return struct {
        pub fn memSize(based_on: []const Base) usize {
            std.debug.assert(based_on.len >= 1);

            const unit_size = @sizeOf(@TypeOf(based_on[0]));
            return unit_size * based_on.len;
        }

        pub fn easyBuffer(dev: *const vk.DeviceProxy, based_on: []const Base, staging: bool) !vk.Buffer {
            const buff_size = memSize(based_on);

            if (staging) {
                return dev.createBuffer(&.{
                    .size = buff_size,
                    .usage = .{ .transfer_src_bit = true },
                    .sharing_mode = .exclusive,
                }, null);
            }

            return dev.createBuffer(&.{
                .size = buff_size,
                .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
                .sharing_mode = .exclusive,
            }, null);
        }
    };
}

fn key_callback(win: ?*glfw.Window, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = scancode;
    _ = mods;
    if (action == glfw.Press and key == glfw.KeyEscape) {
        std.debug.print("key down\n", .{});
        glfw.setWindowShouldClose(win, true);
    }
}

const EasyAcces = struct {
    window: ?*c_long,
    vkctx: ?*const GraphicsContext = null,
};

pub fn main() !void {
    var swapchain_len: u8 = undefined;
    vertex.probing();

    std.debug.print("+++ vertex info: {d}\n", .{Vertex.s_fields_num});
    try glfw.init();
    defer glfw.terminate();

    if (!glfw.vulkanSupported()) {
        std.log.err("GLFW could not find libvulkan", .{});
        return error.NoVulkan;
    }

    // czym się różni vk.Rect2D od vk.Extend2D?
    var resolution_extent = vk.Extent2D{ .width = 800, .height = 600 };
    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);
    const window = try glfw.createWindow(
        @intCast(resolution_extent.width),
        @intCast(resolution_extent.height),
        app_name,
        null,
        null,
    );
    defer glfw.destroyWindow(window);

    // According to the GLFW docs:
    //
    // > Window systems put limits on window sizes. Very large or very small window dimensions
    // > may be overridden by the window system on creation. Check the actual size after creation.
    // -- https://www.glfw.org/docs/3.3/group__window.html#ga3555a418df92ad53f917597fe2f64aeb
    //
    // This happens in practice, for example, when using Wayland with a scaling factor that is not a
    // divisor of the initial window size (see https://github.com/Snektron/vulkan-zig/pull/192).
    // To fix it, just fetch the actual size here, after the windowing system has had the time to
    // update the window.
    resolution_extent.width, resolution_extent.height = blk: {
        var w: c_int = undefined;
        var h: c_int = undefined;
        glfw.getFramebufferSize(window, &w, &h);
        break :blk .{ @intCast(w), @intCast(h) };
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const gc = try GraphicsContext.init(allocator, app_name, window);
    defer gc.deinit();

    std.log.debug("Using device: {s}", .{gc.deviceName()});
    const access = EasyAcces{
        .window = window,
        .vkctx = &gc,
    };
    _ = access;

    const for_depth_attachment = try gftx.DepthImage.init(&gc, resolution_extent);
    defer for_depth_attachment.deinit(&gc);

    var swapchain = try Swapchain.init(&gc, allocator, resolution_extent);
    defer swapchain.deinit();

    swapchain_len = @intCast(swapchain.swap_images.len);
    std.debug.print("+++ {d} buffered video frames\n", .{swapchain_len});

    // texture image
    const pool_cmd = try gc.dev.createCommandPool(&.{
        .queue_family_index = gc.graphics_queue.family,
    }, null);
    defer gc.dev.destroyCommandPool(pool_cmd, null);

    var image = try first_texture(&gc, pool_cmd);
    defer image.deinit();

    // ||| added uniform, storage and texture
    const GroupData = struct {
        osc_scale: [2]f32 = undefined,
        scale_2d: [2]f32 = undefined,
        not_used_4d_0: [4]f32 = undefined,
        termoral: [4]f32 = undefined,
        not_used_4d_1: [4]f32 = undefined,
    };

    const PerInstance = struct {
        offset_2d: [2]f32 = undefined,
        other_offsets: [2]f32 = undefined,
        new_usage: [4]f32 = undefined,
        empty_rest: [8]f32 = undefined,
    };

    var uniform_dset = try addons.DescriptorPrep.init(
        allocator,
        &gc,
        swapchain_len,
        gftx.baked.uniform_frag_vert,
        .{
            .location = 0,
            .size = @sizeOf(GroupData),
        },
        null,
    );
    defer uniform_dset.deinit(allocator);

    const instance_num = 64;
    var storage_dset = try addons.DescriptorPrep.init(
        allocator,
        &gc,
        swapchain_len,
        gftx.baked.storage_frag_vert,
        .{
            .location = 0,
            .size = @sizeOf(PerInstance) * instance_num,
        },
        null,
    );
    defer storage_dset.deinit(allocator);

    var texture_dset = try addons.DescriptorPrep.init(
        allocator,
        &gc,
        swapchain_len,
        gftx.baked.texture_frag,
        .{
            .location = 0,
            .size = @as(u32, @intCast(image.dvk_size)),
        },
        image,
    );
    defer texture_dset.deinit(allocator);

    // ||| quest to add uniform data for vertex rendering

    const dsets = [_]vk.DescriptorSetLayout{
        uniform_dset._d_set_layout.?,
        storage_dset._d_set_layout.?,
        texture_dset._d_set_layout.?,
    };

    const pipeline_layout = try gc.dev.createPipelineLayout(&.{
        .flags = .{},
        .p_set_layouts = &dsets,
        .set_layout_count = dsets.len,
        .p_push_constant_ranges = undefined,
        .push_constant_range_count = 0,
    }, null);
    defer gc.dev.destroyPipelineLayout(pipeline_layout, null);

    const render_pass = try createRenderPass(&gc, swapchain, for_depth_attachment);
    defer gc.dev.destroyRenderPass(render_pass, null);

    const pipeline = try createPipeline(&gc, pipeline_layout, render_pass);
    defer gc.dev.destroyPipeline(pipeline, null);

    var framebuffers = try createFramebuffers(&gc, allocator, render_pass, swapchain);
    defer destroyFramebuffers(&gc, allocator, framebuffers);

    var shape = try Vertex.Ring(allocator, 32);
    defer shape.deinit(allocator);

    const as_slice: []const Vertex = shape.items;

    const buffer = try BufforingVert.easyBuffer(&gc.dev, as_slice, false);
    defer gc.dev.destroyBuffer(buffer, null);

    const mem_reqs = gc.dev.getBufferMemoryRequirements(buffer);
    const memory = try gc.allocate(mem_reqs, .{ .device_local_bit = true });
    defer gc.dev.freeMemory(memory, null);
    try gc.dev.bindBufferMemory(buffer, memory, 0);

    try uploadVertices(&gc, pool_cmd, buffer, as_slice);

    const draw_instanced_attempt: ShaderRelated = .{
        .instance_count = instance_num,
        .pipeline_layout = pipeline_layout,
        .uniform_dsets = uniform_dset.d_set_arr,
        .storage_dsets = storage_dset.d_set_arr,
        .texture_dset = texture_dset.d_set_arr.items[0],
    };

    var cmdbufs = try createCommandBuffers(
        &gc,
        pool_cmd,
        allocator,
        buffer,
        swapchain.extent,
        render_pass,
        pipeline,
        framebuffers,
        as_slice,
        &draw_instanced_attempt,
    );
    defer destroyCommandBuffers(&gc, pool_cmd, allocator, cmdbufs);

    _ = glfw.setKeyCallback(window, key_callback);

    var timeline = addons.Timeline.init();
    var perf_stats = addons.PerfStats.init();
    var state: Swapchain.PresentState = .optimal;

    const spatial_base = -0.75;
    const spatial_delta = 0.2;
    const along = 1 / @as(f32, @floatFromInt(instance_num - 1));
    const phase_delta = along * std.math.tau;
    const spread_base = -0.2;
    const spread_delta = along * 0.2;

    const seed: u64 = @intCast(std.time.timestamp()); // more random
    // const seed: u64 = 42; // deterministic?
    var rng = std.Random.DefaultPrng.init(seed);
    var rnd_gen = rng.random();

    // const hmm = rnd_gen.float(f32);
    var storage_baker: std.ArrayList(f32) = .empty;
    var storage_baker2: std.ArrayList(f32) = .empty;
    try storage_baker.resize(allocator, instance_num);
    try storage_baker2.resize(allocator, instance_num);

    for (0..instance_num) |i| {
        //random
        storage_baker.items[i] = rnd_gen.float(f32);
        //progression
        const progress = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(instance_num - 1));
        storage_baker2.items[i] = progress;
        //constant wins
        storage_baker.items[i] = -0.125;
    }

    {
        defer storage_baker.deinit(allocator);
        defer storage_baker2.deinit(allocator);
        for (storage_dset.buff_arr.items) |possible_buffer| {
            const storage = possible_buffer.?;
            const storagePtr: *[instance_num]PerInstance = @ptrCast(@alignCast(storage.mapping.?));
            for (0..instance_num) |i| {
                const xi = @mod(i, 8);
                const yi = i / 8;
                const i_f: f32 = @floatFromInt(i);
                const x_f: f32 = @floatFromInt(xi);
                const y_f: f32 = @floatFromInt(yi);

                const x_center: f32 = (@as(f32, 8) - 1) / 2;
                const y_center: f32 = (@as(f32, 8) - 1) / 2;

                const x_d = (x_center - x_f) / 3.5;
                const y_d = (y_center - y_f) / 3.5;

                const dist = std.math.sqrt(x_d * x_d + y_d * y_d);

                var fresh_one: PerInstance = undefined;
                fresh_one.offset_2d[0] = spatial_base + x_f * spatial_delta;
                fresh_one.offset_2d[1] = spatial_base + y_f * spatial_delta;
                fresh_one.other_offsets[0] = i_f * phase_delta;
                fresh_one.other_offsets[1] = spread_base + i_f * spread_delta;
                fresh_one.new_usage[0] = storage_baker.items[i]; //offset on ring
                fresh_one.new_usage[1] = dist;
                fresh_one.new_usage[2] = x_f;
                fresh_one.new_usage[3] = x_d;
                storagePtr.*[i] = fresh_one;
            }
        }
        // const hey = storage_dset.buff_arr.items[0].?.mapping.?;
        // const storagePtr: *[instance_num]PerInstance = @ptrCast(@alignCast(hey));
        // for (0..instance_num) |i| {
        //     std.debug.print("i: {d} x_f: {d}, x_d: {d}\n", .{ i, storagePtr[i].new_usage[2], storagePtr[i].new_usage[3] });
        // }
    }

    while (!glfw.windowShouldClose(window)) {
        var w: c_int = undefined;
        var h: c_int = undefined;
        glfw.getFramebufferSize(window, &w, &h);

        // Don't present or resize swapchain while the window is minimized
        perf_stats.messure();
        timeline.update();
        if (w == 0 or h == 0) {
            glfw.pollEvents();
            continue;
        }

        const particle_scale = 0.1;

        const this_frame_uniform = uniform_dset.buff_arr.items[swapchain.image_index].?;
        const as_group_data: *GroupData = @ptrCast(@alignCast(this_frame_uniform.mapping.?));

        as_group_data.*.osc_scale = .{ 0.1, 0.1 };
        as_group_data.*.scale_2d = .{ particle_scale, particle_scale };
        as_group_data.*.termoral = .{ timeline.total_s, 0, 1, 2 };

        // typedPtr.*.data_2d[4] = 0.05 + std.math.sin(timeline.total_s * 4) * 0.05;

        const cmdbuf = cmdbufs[swapchain.image_index];
        // std.debug.print("+++ img_idx {d}\n", .{swapchain.image_index});

        if (state == .suboptimal or resolution_extent.width != @as(u32, @intCast(w)) or resolution_extent.height != @as(u32, @intCast(h))) {
            std.debug.print("??? after resize?\n", .{});
            resolution_extent.width = @intCast(w);
            resolution_extent.height = @intCast(h);
            try swapchain.recreate(resolution_extent);

            destroyFramebuffers(&gc, allocator, framebuffers);
            framebuffers = try createFramebuffers(&gc, allocator, render_pass, swapchain);

            destroyCommandBuffers(&gc, pool_cmd, allocator, cmdbufs);
            cmdbufs = try createCommandBuffers(
                &gc,
                pool_cmd,
                allocator,
                buffer,
                swapchain.extent,
                render_pass,
                pipeline,
                framebuffers,
                as_slice,
                &draw_instanced_attempt,
            );
        }
        state = swapchain.present(cmdbuf) catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => |narrow| return narrow,
        };

        glfw.pollEvents();
    }

    try swapchain.waitForAllFences();
    try gc.dev.deviceWaitIdle();
}

const ImgLTranConfig = struct {
    image: vk.Image,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    format: ?vk.Format = null,
    flags: gftx.LTransRelated,
};

fn imgLTrans(gc: *const GraphicsContext, pool: vk.CommandPool, cfg: ImgLTranConfig) !void {
    const devk = gc.dev;
    const family_ignored: u32 = 0;
    // const zero_mask: u32 = 0;

    const step: vk.CommandBuffer = try gftx.beginSingleCmd(gc, pool);

    const il_barriers: []const vk.ImageMemoryBarrier = &.{
        vk.ImageMemoryBarrier{
            .s_type = .image_memory_barrier,
            .old_layout = cfg.old_layout,
            .new_layout = cfg.new_layout,
            .src_queue_family_index = family_ignored,
            .dst_queue_family_index = family_ignored,
            .image = cfg.image,
            .subresource_range = gftx.baked.color_img_subrng,
            .src_access_mask = cfg.flags.accesses.src,
            .dst_access_mask = cfg.flags.accesses.dst,
        },
    };
    devk.cmdPipelineBarrier(
        step,
        cfg.flags.stages.src,
        cfg.flags.stages.dst,
        .{},
        0,
        null,
        0,
        null,
        @intCast(il_barriers.len),
        il_barriers.ptr,
    );

    try gftx.endSingleCmd(gc, step);
}

const BfrToImgCpyCfg = struct {
    image: vk.Image,
    buffer: vk.Buffer,
    layout: vk.ImageLayout,
};

fn bfr2ImgCopy(gc: *const GraphicsContext, pool: vk.CommandPool, cfg: BfrToImgCpyCfg) !void {
    const devk = gc.dev;

    const step: vk.CommandBuffer = try gftx.beginSingleCmd(gc, pool);

    const bfr_img_cpy: vk.BufferImageCopy = .{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_extent = .{
            .width = baked.img_side,
            .height = baked.img_side,
            .depth = 1,
        },
        .image_subresource = gftx.baked.color_bfr2img_sublyr,
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
    };
    devk.cmdCopyBufferToImage(
        step,
        cfg.buffer,
        cfg.image,
        cfg.layout,
        1,
        @ptrCast(&bfr_img_cpy),
    );

    try gftx.endSingleCmd(gc, step);
}

fn first_texture(gc: *const GraphicsContext, with_pool: vk.CommandPool) !gftx.RGBImage {
    const devk = gc.dev;

    var test_img = try gftx.RGBImage.init(gc, 64, 64);

    const buff_size = test_img.dvk_size;
    const src_buff = try gftx.createBuffer(
        gc,
        gftx.baked.cpu_accesible_memory,
        buff_size,
        .{ .transfer_src_bit = true },
    );
    defer src_buff.deinit(devk);

    const src_data = baked.rgb_tex;
    const src_mapping: [*]u8 = @ptrCast(@alignCast(src_buff.mapping));
    @memcpy(src_mapping[0..src_data.len], src_data[0..src_data.len]);

    const dst_layout: vk.ImageLayout = .transfer_dst_optimal;
    const shader_read_layout: vk.ImageLayout = .shader_read_only_optimal;

    try imgLTrans(gc, with_pool, .{
        .old_layout = .undefined,
        .new_layout = dst_layout,
        .image = test_img.dvk_img,
        .format = test_img.vk_format,
        .flags = gftx.baked.undefined_to_transfered,
    });

    try bfr2ImgCopy(gc, with_pool, .{
        .buffer = src_buff.dvk_bfr,
        .image = test_img.dvk_img,
        .layout = dst_layout,
    });

    try imgLTrans(gc, with_pool, .{
        .old_layout = dst_layout,
        .new_layout = shader_read_layout,
        .image = test_img.dvk_img,
        .format = test_img.vk_format,
        .flags = gftx.baked.transfered_to_fragment_readed,
    });

    try test_img.createImageView(gc);
    try test_img.createSampler(gc);

    return test_img;
}

// przykład przesyłania danych na gpu
fn uploadVertices(gc: *const GraphicsContext, pool: vk.CommandPool, buffer: vk.Buffer, vert_slice: []const Vertex) !void {
    const buff_size = BufforingVert.memSize(vert_slice);
    const staging_buffer = try BufforingVert.easyBuffer(&gc.dev, vert_slice, true);

    defer gc.dev.destroyBuffer(staging_buffer, null);
    const mem_reqs = gc.dev.getBufferMemoryRequirements(staging_buffer);
    const staging_memory = try gc.allocate(
        mem_reqs,
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );
    defer gc.dev.freeMemory(staging_memory, null);
    try gc.dev.bindBufferMemory(staging_buffer, staging_memory, 0);

    {
        const data = try gc.dev.mapMemory(staging_memory, 0, vk.WHOLE_SIZE, .{});
        defer gc.dev.unmapMemory(staging_memory);

        const gpu_vertices: [*]Vertex = @ptrCast(@alignCast(data));
        @memcpy(gpu_vertices, vert_slice);
    }

    try copyBuffer(gc, pool, buffer, staging_buffer, buff_size);
}

// Z tego co rozumiem to... nie tego jeszcze nie rozumiem xD
fn copyBuffer(gc: *const GraphicsContext, pool: vk.CommandPool, dst: vk.Buffer, src: vk.Buffer, size: vk.DeviceSize) !void {
    var cmdbuf_handle: vk.CommandBuffer = undefined;
    try gc.dev.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf_handle));
    defer gc.dev.freeCommandBuffers(pool, 1, @ptrCast(&cmdbuf_handle));

    const cmdbuf = GraphicsContext.CommandBuffer.init(cmdbuf_handle, gc.dev.wrapper);

    try cmdbuf.beginCommandBuffer(&.{
        .flags = .{ .one_time_submit_bit = true },
    });

    const region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
    cmdbuf.copyBuffer(src, dst, 1, @ptrCast(&region));

    try cmdbuf.endCommandBuffer();

    const si = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = (&cmdbuf.handle)[0..1],
        .p_wait_dst_stage_mask = undefined,
    };
    try gc.dev.queueSubmit(gc.graphics_queue.handle, 1, @ptrCast(&si), .null_handle);
    try gc.dev.queueWaitIdle(gc.graphics_queue.handle);
}

const ShaderRelated = struct {
    instance_count: u32 = 1,
    pipeline_layout: vk.PipelineLayout,
    uniform_dsets: std.ArrayList(vk.DescriptorSet),
    storage_dsets: std.ArrayList(vk.DescriptorSet),
    texture_dset: vk.DescriptorSet,
};

// a tutaj odbywa się taka jakby prekompilacja renderingu ?...
fn createCommandBuffers(
    gc: *const GraphicsContext,
    pool: vk.CommandPool,
    allocator: Allocator,
    buffer: vk.Buffer,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    pipeline: vk.Pipeline,
    framebuffers: []vk.Framebuffer,
    ojejoje: []const Vertex,
    shader_realted: *const ShaderRelated,
) ![]vk.CommandBuffer {
    const cmdbufs = try allocator.alloc(vk.CommandBuffer, framebuffers.len);
    errdefer allocator.free(cmdbufs);

    try gc.dev.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = @intCast(cmdbufs.len),
    }, cmdbufs.ptr);
    errdefer gc.dev.freeCommandBuffers(pool, @intCast(cmdbufs.len), cmdbufs.ptr);

    const clear = vk.ClearValue{
        .color = .{ .float_32 = .{ 0.1, 0, 0, 1 } },
    };

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    for (cmdbufs, framebuffers, 0..) |cmdbuf, framebuffer, i| {
        try gc.dev.beginCommandBuffer(cmdbuf, &.{});

        gc.dev.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(&viewport));
        gc.dev.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(&scissor));

        // This needs to be a separate definition - see https://github.com/ziglang/zig/issues/7627.
        const render_area = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = extent,
        };
        gc.dev.cmdBeginRenderPass(cmdbuf, &.{
            .render_pass = render_pass,
            .framebuffer = framebuffer,
            .render_area = render_area,
            .clear_value_count = 1,
            .p_clear_values = @ptrCast(&clear),
        }, .@"inline");
        {
            defer gc.dev.cmdEndRenderPass(cmdbuf);
            const offset = [_]vk.DeviceSize{0};
            gc.dev.cmdBindPipeline(cmdbuf, .graphics, pipeline);
            gc.dev.cmdBindVertexBuffers(
                cmdbuf,
                0,
                1,
                @ptrCast(&buffer),
                &offset,
            );
            const hmm: []const vk.DescriptorSet = &[_]vk.DescriptorSet{
                shader_realted.uniform_dsets.items[i],
                shader_realted.storage_dsets.items[i],
                shader_realted.texture_dset,
            };

            gc.dev.cmdBindDescriptorSets(
                cmdbuf,
                .graphics,
                shader_realted.pipeline_layout,
                0,
                @intCast(hmm.len),
                hmm.ptr,
                0,
                null,
            );
            gc.dev.cmdDraw(
                cmdbuf,
                @intCast(ojejoje.len),
                shader_realted.instance_count,
                0,
                0,
            );
        }
        try gc.dev.endCommandBuffer(cmdbuf);
    }

    return cmdbufs;
}

fn destroyCommandBuffers(gc: *const GraphicsContext, pool: vk.CommandPool, allocator: Allocator, cmdbufs: []vk.CommandBuffer) void {
    gc.dev.freeCommandBuffers(pool, @truncate(cmdbufs.len), cmdbufs.ptr);
    allocator.free(cmdbufs);
}

fn createFramebuffers(gc: *const GraphicsContext, allocator: Allocator, render_pass: vk.RenderPass, swapchain: Swapchain) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swap_images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |fb| gc.dev.destroyFramebuffer(fb, null);

    for (framebuffers) |*fb| {
        fb.* = try gc.dev.createFramebuffer(&.{
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&swapchain.swap_images[i].view),
            .width = swapchain.extent.width,
            .height = swapchain.extent.height,
            .layers = 1,
        }, null);
        i += 1;
    }

    return framebuffers;
}

fn destroyFramebuffers(gc: *const GraphicsContext, allocator: Allocator, framebuffers: []const vk.Framebuffer) void {
    for (framebuffers) |fb| gc.dev.destroyFramebuffer(fb, null);
    allocator.free(framebuffers);
}

fn createRenderPass(gc: *const GraphicsContext, swapchain: Swapchain, _: ?gftx.DepthImage) !vk.RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .format = swapchain.surface_format.format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };
    // const depth_attachment = vk.AttachmentDescription{};

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment_ref),
    };

    return try gc.dev.createRenderPass(&.{
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_attachment),
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
    }, null);
}

// tu mamy długą fuckję, która inicjalizuej pipeline graficzny, czyli co?
// to tu powinoo się definiować tak jakby cały reder pass?
fn createPipeline(
    gc: *const GraphicsContext,
    layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
) !vk.Pipeline {
    const vert = try gc.dev.createShaderModule(&.{
        .code_size = vert_spv.len,
        .p_code = @ptrCast(&vert_spv),
    }, null);
    defer gc.dev.destroyShaderModule(vert, null);

    const frag = try gc.dev.createShaderModule(&.{
        .code_size = frag_spv.len,
        .p_code = @ptrCast(&frag_spv),
    }, null);
    defer gc.dev.destroyShaderModule(frag, null);

    const pssci = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex_bit = true },
            .module = vert,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = frag,
            .p_name = "main",
        },
    };

    const pvisci = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&Vertex.binding_description),
        .vertex_attribute_description_count = Vertex.attribute_description.len,
        .p_vertex_attribute_descriptions = &Vertex.attribute_description,
    };

    const piasci = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list,
        .primitive_restart_enable = .false,
    };

    const pvsci = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = undefined, // set in createCommandBuffers with cmdSetViewport
        .scissor_count = 1,
        .p_scissors = undefined, // set in createCommandBuffers with cmdSetScissor
    };

    const prsci = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false,
        .rasterizer_discard_enable = .false,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .clockwise,
        .depth_bias_enable = .false,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const pmsci = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = .false,
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    const pcbas = vk.PipelineColorBlendAttachmentState{
        .blend_enable = .false,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const pcbsci = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&pcbas),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
    const pdsci = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynstate.len,
        .p_dynamic_states = &dynstate,
    };

    const gpci = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &pssci,
        .p_vertex_input_state = &pvisci,
        .p_input_assembly_state = &piasci,
        .p_tessellation_state = null,
        .p_viewport_state = &pvsci,
        .p_rasterization_state = &prsci,
        .p_multisample_state = &pmsci,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &pcbsci,
        .p_dynamic_state = &pdsci,
        .layout = layout,
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try gc.dev.createGraphicsPipelines(
        .null_handle,
        1,
        @ptrCast(&gpci),
        null,
        @ptrCast(&pipeline),
    );
    return pipeline;
}
