const std = @import("std");

const glfw = @import("third_party/glfw.zig");
const vk = @import("third_party/vk.zig");
const sht = @import("shaders/types.zig");
const gftx = @import("graphics_context.zig");

const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Swapchain = @import("swapchain.zig").Swapchain;
const addons = @import("addons.zig");

const baked = @import("baked.zig");

const helpers = @import("helpers.zig");
const vertex = @import("vertex.zig");
const m = @import("math.zig");
const t = @import("types.zig");
const phx = @import("phys.zig");
const imgs = @import("imgs.zig");
const utils = @import("utils.zig");
const prefils = @import("prefills.zig");

const InertiaVec2 = phx.InertiaPack(m.vec3);
const Vertex = vertex.Vertex;

const BufforingVert = Buffering(Vertex);
const Allocator = std.mem.Allocator;

const motion = @import("motion.zig");

const vert_spv align(@alignOf(u32)) = @embedFile("vertex_shader").*;
const frag_spv align(@alignOf(u32)) = @embedFile("fragment_shader").*;

const app_name = "vulkan-zig triangle example";
const future_app_name = "oct_calculator";

// Taki buferek może posłużyć np. do wysłania trójkątów na gpu
fn Buffering(Base: type) type {
    return struct {
        const Self = @This();

        pub fn memSize(based_on: []const Base) usize {
            std.debug.assert(based_on.len >= 1);

            const unit_size = @sizeOf(@TypeOf(based_on[0]));
            return unit_size * based_on.len;
        }
    };
}

var glass_input: motion.HoldsAxis = undefined;
var plr_input: motion.HoldsAxis = undefined;

const KeyAction = motion.KeyAction;
fn key_callback(win: ?*glfw.Window, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = scancode;
    _ = mods;
    const x: KeyAction = .{
        .action = action,
        .key = key,
    };
    if (x.down(glfw.KeyEscape)) {
        std.debug.print("exititng\n", .{});
        glfw.setWindowShouldClose(win, true);
    }
    if (x.down(glfw.KeySpace)) {
        if (time_glob) |hey| {
            hey.time_passage = !hey.time_passage;
        }
    }

    glass_input.passKeyAction(&x);
    plr_input.passKeyAction(&x);
}

fn windowExtext(window: *c_long) vk.Extent2D {
    var resolution_extent: vk.Extent2D = undefined;
    resolution_extent.width, resolution_extent.height = blk: {
        var w: c_int = undefined;
        var h: c_int = undefined;
        glfw.getFramebufferSize(window, &w, &h);
        break :blk .{ @intCast(w), @intCast(h) };
    };
    return resolution_extent;
}

const EasyAcces = struct {
    alloc: std.mem.Allocator,
    window: *c_long,
    vkctx: *const GraphicsContext,
};

var time_glob: ?*addons.Timeline = null;
const BasicErrs = error{
    NoCtx,
};

const proto = @import("proto.zig");

pub fn main() !void {
    glass_input = try motion.HoldsAxis.init(&.{
        glfw.KeyJ, glfw.KeyK, //
        glfw.KeyH, glfw.KeyL,
    });
    plr_input = try motion.HoldsAxis.init(&.{
        glfw.KeyA, glfw.KeyD, //
        glfw.KeyS, glfw.KeyW,
        glfw.KeyF, glfw.KeyR,
    });

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
    // resolution_extent.width, resolution_extent.height = blk: {
    //     var w: c_int = undefined;
    //     var h: c_int = undefined;
    //     glfw.getFramebufferSize(window, &w, &h);
    //     break :blk .{ @intCast(w), @intCast(h) };
    // };
    resolution_extent = windowExtext(window);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const vkctx = try GraphicsContext.init(allocator, app_name, window);
    defer vkctx.deinit();

    std.log.debug("Using device: {s}", .{vkctx.deviceName()});
    const access = EasyAcces{
        .window = window,
        .vkctx = &vkctx,
        .alloc = allocator,
    };
    try deeper(access);
}

fn playerPos(p: *t.Player) m.vec3 {
    return m.orbit_r(p.phi, p.r) + m.vec3{ 0, p.h, 0 };
}

fn deeper(access: EasyAcces) !void {
    const grid = sht.GridSize.g64;
    const deeper_allocator = std.heap.page_allocator;
    var img = try proto.serdesLoad(deeper_allocator);
    defer img.deinit(deeper_allocator);

    var glass = proto.LookingGlass.init(&img, grid);

    var swapchain_len: u8 = undefined;
    // const gc = access.vkctx.?.*;
    const gc = access.vkctx;
    const window = access.window;
    const allocator = access.alloc;

    var resolution_extent = windowExtext(window);

    var swapchain = try Swapchain.init(gc, allocator, resolution_extent);
    defer swapchain.deinit();

    swapchain_len = @intCast(swapchain.swap_images.len);
    std.debug.print("+++ Serial frames {}\n", .{swapchain_len});

    // texture image
    const pool_cmd = try gc.dev.createCommandPool(&.{
        .queue_family_index = gc.graphics_queue.family,
    }, null);
    defer gc.dev.destroyCommandPool(pool_cmd, null);

    const cmd_ctx = gftx.PoolInCtx{
        .gc = gc,
        .pool = pool_cmd,
    };

    // fn theDeepest()

    var uniform_dset = try addons.DescriptorPrep.init(
        allocator,
        gc,
        swapchain_len,
        gftx.baked.uniform_frag_vert,
        .{
            .location = 0,
            .size = @sizeOf(sht.GroupData),
        },
        null,
    );
    defer uniform_dset.deinit(allocator);

    var storage_dset = try addons.DescriptorPrep.init(
        allocator,
        gc,
        swapchain_len,
        gftx.baked.storage_frag_vert,
        .{
            .location = 0,
            .size = @sizeOf(sht.PerInstance) * @as(u32, grid.total),
        },
        null,
    );
    defer storage_dset.deinit(allocator);

    const spacing = 0.1;
    const size = 0.025;
    var m_img = try proto.serdesLoad(allocator);
    defer m_img.deinit(allocator);
    try prefils.storagePrefil(storage_dset, grid, spacing);

    var image = try imgs.vulkanTexture(cmd_ctx.gc, cmd_ctx.pool);
    defer image.deinit();
    var texture_dset = try addons.DescriptorPrep.init(
        allocator,
        gc,
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

    const render_pass = try createRenderPass(gc, swapchain);
    defer gc.dev.destroyRenderPass(render_pass, null);

    const pipeline = try createPipeline(gc, pipeline_layout, render_pass);
    defer gc.dev.destroyPipeline(pipeline, null);

    var framebuffers = try createFramebuffers(
        gc,
        allocator,
        render_pass,
        swapchain,
    );
    defer destroyFramebuffers(gc, allocator, framebuffers);

    var param = vertex.RingParams.default;

    param.len = 32;
    param.flat = false;
    var shape: vertex.TriangleArray = try vertex.Utils.Ring(allocator, param);
    defer shape.deinit(allocator);

    param.len = 5;
    param.flat = true;
    var next_shape: vertex.TriangleArray = try vertex.Utils.Ring(allocator, param);
    defer next_shape.deinit(allocator);

    const rotmat = m.rotMatY(0.125);
    for (0..next_shape.items.len) |i| {
        const vert = m.vec3u{ .arr = next_shape.items[i].pos };
        const newpos = m.vec3u{ .vec = m.matXvec3(rotmat, vert.vec) };
        next_shape.items[i].pos = newpos.arr;
    }

    var next_next_shape: vertex.TriangleArray = try vertex.Utils.Blocky(allocator);
    defer next_next_shape.deinit(allocator);

    std.debug.print("+++ vert count {d}\n", .{next_next_shape.items.len});

    const as_slice: []const Vertex = next_next_shape.items;
    const mem_size = @sizeOf(Vertex) * as_slice.len;

    const vert_buffering = try gftx.createBuffer(
        gc,
        gftx.baked.memory_gpu,
        gftx.baked.usage_vert_dst,
        mem_size,
    );
    defer vert_buffering.deinit(gc);

    const buffer = vert_buffering.dvk_bfr;
    try uploadVertices(gc, pool_cmd, buffer, as_slice);

    const draw_instanced_attempt: ShaderRelated = .{
        .instance_count = grid.total,
        .pipeline_layout = pipeline_layout,
        .uniform_dsets = uniform_dset.d_set_arr,
        .storage_dsets = storage_dset.d_set_arr,
        .texture_dset = texture_dset.d_set_arr.items[0],
    };

    var cmdbufs = try createCommandBuffers(
        gc,
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
    defer destroyCommandBuffers(gc, pool_cmd, allocator, cmdbufs);

    _ = glfw.setKeyCallback(window, key_callback);

    var timeline = addons.Timeline.init();
    var timeline1 = addons.Timeline.init();
    time_glob = &timeline;
    var perf_stats = addons.PerfStats.init();
    var state: Swapchain.PresentState = .optimal;

    timeline1.arm(std.time.us_per_s / 2);
    var r_lim = utils.Caped.init(1, 5);
    var high_lim = utils.Caped.init(0, 3);

    var plr = t.Player{
        .phi = 0,
        .r = r_lim.cap(1.74),
        .h = high_lim.cap(1.74),
    };

    const speed: f32 = 1;
    const IVec3 = phx.InertiaPack(m.vec3);
    var inertia = IVec3.Inertia.init(.{ plr.phi, 0, 0 });
    inertia.phx = IVec3.InertiaCfg.default();

    while (!glfw.windowShouldClose(window)) {
        const img_idx = swapchain.image_index;
        const win_size = windowExtext(window);
        // input_continue();
        glass_input.input_continue();
        plr_input.input_continue();

        // Don't present or resize swapchain while the window is minimized
        perf_stats.messure();
        timeline.update();
        timeline1.update();

        if (timeline1.triggerd()) {
            // std.debug.print("+++ interval info:D\n", .{});
        }

        const td = timeline.deltaS();

        const phi_delt: f32 = switch (plr_input.axes[0]) {
            motion.Axis.positive => 1,
            motion.Axis.negative => -1,
            else => 0,
        };

        const phi_a = plr.phi + (-phi_delt) * td * std.math.tau * speed;
        inertia.in(.{ phi_a, 0, 0 });
        inertia.simulate(timeline1.delta_ms);
        plr.phi = inertia.out()[0];
        plr.phi = phi_a;

        utils.PlayerUpdate(&plr, &plr_input, td);

        if (glass.update(&glass_input)) {
            try glass.updateStorage(storage_dset);
        }

        //minimalized
        if (!addons.visible(win_size)) {
            glfw.pollEvents();
            continue;
        }
        try prefils.perFrameUniformFill(
            uniform_dset,
            @intCast(img_idx),
            timeline.total_s,
            playerPos(&plr),
            size,
        );

        const cmdbuf = cmdbufs[img_idx];

        if (state == .suboptimal or addons.extentDiffer(resolution_extent, win_size)) {
            // std.debug.assert(false); //cuz it will throw error due to bad depth_img resolution
            resolution_extent = win_size;
            std.debug.print("+++ a\n", .{});
            // try gc.dev.deviceWaitIdle();
            try swapchain.recreate(resolution_extent);

            std.debug.print("+++ b\n", .{});
            destroyFramebuffers(gc, allocator, framebuffers);
            framebuffers = try createFramebuffers(
                gc,
                allocator,
                render_pass,
                swapchain,
            );

            std.debug.print("+++ c\n", .{});
            destroyCommandBuffers(gc, pool_cmd, allocator, cmdbufs);
            cmdbufs = try createCommandBuffers(
                gc,
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

// przykład przesyłania danych na gpu, też jest potrze kolejka dla tej operacji
fn uploadVertices(gc: *const GraphicsContext, pool: vk.CommandPool, buffer: vk.Buffer, vert_slice: []const Vertex) !void {
    const buff_size = BufforingVert.memSize(vert_slice);

    var buffer_ = try gftx.createBuffer(
        gc, //
        gftx.baked.memory_cpu,
        gftx.baked.usage_src,
        buff_size,
    );
    defer buffer_.deinit(gc);

    const gpu_vertices: [*]Vertex = @ptrCast(@alignCast(buffer_.mapping));
    //does one @memcpy operation is more effective then #storagePrefill
    @memcpy(gpu_vertices, vert_slice);

    try copyBuffer(gc, pool, buffer, buffer_.dvk_bfr, buff_size);
}

// Z tego co rozumiem to... nie tego jeszcze nie rozumiem xD
// No to już ci mówię:D to nie jest aż takie skomplikowane
// kopiujemy tutaj po prostu dane pomiędzy dwoma bufferami
// aleeee...
// Kopiowanie jest po prostu rodzaje komendy, którą najpierw
// musimy nagrać, a potem wysłać do kolejki na gpu
// (a same kolejki są jakby wątkami gpu)
// dane między bufferami
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

    const clear_arr: []const vk.ClearValue = &.{
        vk.ClearValue{
            .color = .{ .float_32 = .{ 0.05, 0, 0, 1 } },
        },
        vk.ClearValue{
            .depth_stencil = .{ .depth = 1.0, .stencil = 0 },
        },
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

        // oscilationg ring
        gc.dev.cmdBeginRenderPass(cmdbuf, &.{
            .render_pass = render_pass,
            .framebuffer = framebuffer,
            .render_area = render_area,
            .clear_value_count = @intCast(clear_arr.len),
            .p_clear_values = clear_arr.ptr,
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

            // czyli co jakbym tutaj miał więcej modeli większej ilości instancji, bo bym je po prostu mógł,
            // tutaj rysować jakby końca świata miało nie być xD
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
        const att_arr: []const vk.ImageView = &.{
            swapchain.swap_images[i].view,
            swapchain.depth_image.dvk_img_view,
        };

        fb.* = try gc.dev.createFramebuffer(&.{
            .render_pass = render_pass,
            .attachment_count = @intCast(att_arr.len),
            .p_attachments = att_arr.ptr,
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

fn createRenderPass(gc: *const GraphicsContext, swapchain: Swapchain) !vk.RenderPass {
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
    const depth_attachment = vk.AttachmentDescription{
        .format = swapchain.depth_image.vk_format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .dont_care,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .depth_stencil_attachment_optimal,
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };
    const depth_attachment_ref = vk.AttachmentReference{
        .attachment = 1,
        .layout = .depth_stencil_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment_ref),
        .p_depth_stencil_attachment = &depth_attachment_ref,
    };

    const subpass_dependency = vk.SubpassDependency{
        .dst_subpass = 0,
        .src_subpass = vk.SUBPASS_EXTERNAL,
        .src_stage_mask = .{
            .color_attachment_output_bit = true,
            .late_fragment_tests_bit = true,
        },
        .src_access_mask = .{
            .depth_stencil_attachment_write_bit = true,
        },
        .dst_stage_mask = .{
            .color_attachment_output_bit = true,
            .early_fragment_tests_bit = true,
        },
        .dst_access_mask = .{
            .color_attachment_write_bit = true,
            .depth_stencil_attachment_write_bit = true,
        },
    };

    const att_arr: []const vk.AttachmentDescription = &.{ color_attachment, depth_attachment };

    const rpmvci: vk.RenderPassMultiviewCreateInfo = .{
        .subpass_count = 1,
    };
    _ = rpmvci;

    const render_pass_create_info: vk.RenderPassCreateInfo = .{
        .attachment_count = @intCast(att_arr.len),
        .p_attachments = att_arr.ptr,
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
        .p_dependencies = @ptrCast(&subpass_dependency),
        // here we will pass multiview config
        .p_next = null,
    };

    return try gc.dev.createRenderPass(&render_pass_create_info, null);
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
        .cull_mode = .{ .back_bit = false },
        .front_face = .clockwise, // couse we assume Y axis flip
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

    const depth_stencil_state = vk.PipelineDepthStencilStateCreateInfo{
        .depth_test_enable = .true,
        .depth_write_enable = .true,
        .depth_compare_op = .less,
        .depth_bounds_test_enable = .false,
        .min_depth_bounds = 0.0,
        .max_depth_bounds = 1.0,
        .stencil_test_enable = .false,
        .front = undefined,
        .back = undefined,
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
        .p_depth_stencil_state = &depth_stencil_state,
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

test "do it even testing" {
    try std.testing.expect(true);
}
