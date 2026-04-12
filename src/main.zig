const std = @import("std");

const glfw = @import("third_party/glfw.zig");
const vk = @import("third_party/vk.zig");

const sht = @import("shaders/types.zig");
const shu = @import("shaders/utils.zig");
const gftx = @import("graphics_context.zig");

const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Swapchain = @import("swapchain.zig").Swapchain;
const addons = @import("addons.zig");
const dset = @import("dset.zig");

const helpers = @import("helpers.zig");
const vertex = @import("vertex.zig");
const m = @import("math.zig");
const t = @import("types.zig");
const phx = @import("phys.zig");
const imgs = @import("imgs.zig");
const utils = @import("utils.zig");
const prefils = @import("prefills.zig");
const oklab = @import("oklab.zig");

const InertiaVec2 = phx.InertiaPack(m.vec3);
const Vertex = vertex.Vertex;

const BufforingVert = Buffering(Vertex);
const Allocator = std.mem.Allocator;

const motion = @import("motion.zig");
const frame = @import("frame.zig");

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

    if (x.down(shader_reset.key)) {
        shader_reset_trigger.activated = true;
    }

    if (x.down(uniform_shift.key)) {
        uniform_shift_trigger.activated = true;
    }
    if (x.down(slide_l.key)) {
        slide_l_trig.activated = true;
    }
    if (x.down(slide_r.key)) {
        slide_r_trig.activated = true;
    }
    if (x.down(ok_vis.key)) {
        ok_vis_trigger.activated = true;
    }

    glass_input.reciveInput(&x);
    plr_input.reciveInput(&x);
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

var glass_input: motion.HoldsAxis = undefined;
var plr_input: motion.HoldsAxis = undefined;
var ok_vis: motion.KeyAction = .{ .key = glfw.KeyY, .action = glfw.KeyDown };
var ok_vis_trigger: motion.Trigger = .{};
var shader_reset: motion.KeyAction = .{ .key = glfw.KeyQ, .action = glfw.KeyDown };
var shader_reset_trigger: motion.Trigger = .{};
var uniform_shift: motion.KeyAction = .{ .key = glfw.KeyE, .action = glfw.KeyDown };
var uniform_shift_trigger: motion.Trigger = .{};
var slide_l: motion.KeyAction = .{ .key = glfw.KeyV, .action = glfw.KeyDown };
var slide_r: motion.KeyAction = .{ .key = glfw.KeyB, .action = glfw.KeyDown };
var slide_l_trig: motion.Trigger = .{};
var slide_r_trig: motion.Trigger = .{};

pub fn main() !void {
    oklab.demo();

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
    var resolution_extent = vk.Extent2D{ .width = 1600, .height = 900 };
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

var frame_state: frame.FrameState = .{
    .alt_proj = false,
    .model_idx = 0,
};

fn deeper(access: EasyAcces) !void {
    // const grid = sht.GridSize.g64;
    const grid = shu.xyGrid(128, 32);
    const deeper_allocator = std.heap.page_allocator;
    var img = try proto.serdesLoad(deeper_allocator);
    defer img.deinit(deeper_allocator);

    var glass = proto.LookingGlass.init(&img, grid);
    const ok_understanding = oklab.OkUnderstanding{ .size = grid };

    var swapchain_len: u8 = undefined;
    // const gc = access.vkctx.?.*;
    const gc = access.vkctx;
    const window = access.window;
    const allocator = access.alloc;

    var resolution_extent = windowExtext(window);

    var swapchain = try Swapchain.init(gc, allocator, resolution_extent);
    defer swapchain.deinit() catch std.debug.print("... well swapchaing deinit failed\n", .{});

    swapchain_len = @intCast(swapchain.swap_images.len);
    std.debug.print("+++ Serial frames {}\n", .{swapchain_len});

    // texture image
    const pool_cinfo: vk.CommandPoolCreateInfo = .{
        .queue_family_index = gc.graphics_queue.family,
        .flags = .{
            .reset_command_buffer_bit = true,
            // .transient_bit = true,
        },
    };
    const pool_cmd = try gc.dev.createCommandPool(&pool_cinfo, null);
    defer gc.dev.destroyCommandPool(pool_cmd, null);

    const pic = gftx.PoolInCtx{
        .gc = gc,
        .pool = pool_cmd,
    };

    // fn theDeepest()

    var uniform_dset = try dset.DescriptorPrep.init(
        allocator,
        gc,
        swapchain_len,
        gftx.baked.uniform_frag_vert_dyn,
        .{
            .set_binding = 0,
            .size = @sizeOf(sht.GroupData),
            .num = 2,
        },
        null,
    );
    defer uniform_dset.deinit(allocator);

    var storage_dset = try dset.DescriptorPrep.init(
        allocator,
        gc,
        swapchain_len,
        gftx.baked.storage_frag_vert,
        .{
            .set_binding = 0,
            .size = @sizeOf(sht.PerInstance) * @as(u32, grid.total),
        },
        null,
    );
    defer storage_dset.deinit(allocator);

    const spacing = 0.1;
    const size = 0.04;
    try prefils.storagePrefil(storage_dset, grid, spacing);

    var demo_rgb = try imgs.vulkanTexture(&pic, imgs.demo_tex_rgb[0..]);
    var demo_r = try imgs.vulkanTexture(&pic, imgs.demo_tex_r[0..]);
    defer demo_rgb.deinit();
    defer demo_r.deinit();
    var texture_dset = try dset.DescriptorPrep.init(
        allocator,
        gc,
        1,
        gftx.baked.texture_frag,
        .{
            .set_binding = 0,
            .size = @as(u32, @intCast(demo_rgb.dvk_size)),
        },
        16,
    );
    defer texture_dset.deinit(allocator);
    texture_dset.updateTexture(0, demo_rgb, 0);
    texture_dset.updateTexture(0, demo_r, 1);

    // render pass
    const render_pass = try createRenderPass(gc, swapchain);
    defer gc.dev.destroyRenderPass(render_pass, null);

    // pipeline
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

    const pipeline = try createPipeline(gc, pipeline_layout, render_pass);
    defer gc.dev.destroyPipeline(pipeline, null);

    // framebuffers
    var framebuffers = try createFramebuffers(
        gc,
        allocator,
        render_pass,
        swapchain,
    );
    defer destroyFramebuffers(gc, allocator, framebuffers);

    // geometry
    var param = vertex.RingParams.default;
    var verts: vertex.TriangleArray = try .initCapacity(allocator, 1024);
    defer verts.deinit(allocator);

    param.len = 32;
    param.flat = false;
    var models: vertex.VertIndex = .{ .offsets = undefined };
    var shape: vertex.TriangleArray = try vertex.Utils.Ring(allocator, param);
    try verts.appendSlice(allocator, shape.items);
    models.register(shape.items);
    shape.deinit(allocator);

    param.len = 5;
    param.flat = true;
    shape = try vertex.Utils.Ringy(allocator);
    try verts.appendSlice(allocator, shape.items);
    models.register(shape.items);
    shape.deinit(allocator);

    shape = try vertex.Utils.Blocky(allocator);
    try verts.appendSlice(allocator, shape.items);
    models.register(shape.items);
    shape.deinit(allocator);

    std.debug.print("+++ vert count {d}\n", .{verts.items.len});

    const as_slice: []const Vertex = verts.items;
    const mem_size = @sizeOf(Vertex) * as_slice.len;

    const vert_buffer = try gftx.createBuffer(
        gc,
        gftx.baked.memory_gpu,
        gftx.baked.usage_vert_dst,
        mem_size,
    );
    defer vert_buffer.deinit(gc);
    models.vkBuffer = vert_buffer.dvk_bfr;

    try uploadVertices(&pic, models.vkBuffer, as_slice);

    const draw_instanced_attempt: gftx.DrawInfo = .{
        .instance_count = grid.total,
        .pipeline = pipeline,
        .pipeline_layout = pipeline_layout,
        .uniform_dsets = uniform_dset.d_set_arr,
        .storage_dsets = storage_dset.d_set_arr,
        .texture_dset = texture_dset.d_set_arr.items[0],
    };

    const frame_pools_config: vk.CommandPoolCreateInfo = .{
        .queue_family_index = gc.graphics_queue.family,
        .flags = .{
            .transient_bit = true,
        },
    };

    const inflight_slots = 8;
    std.debug.assert(swapchain_len < inflight_slots);
    var inflight_stack: [1024]u8 = undefined;
    var loc_stack: std.heap.FixedBufferAllocator = .init(inflight_stack[0..1024]);
    const cmdbufs: []vk.CommandBuffer = try loc_stack.allocator().alloc(vk.CommandBuffer, swapchain_len);
    const pools: []vk.CommandPool = try loc_stack.allocator().alloc(vk.CommandPool, swapchain_len);
    const recorders: []gftx.FrameRecorder = try loc_stack.allocator().alloc(gftx.FrameRecorder, swapchain_len);

    var created: u8 = 0;
    for (0..swapchain_len) |i| {
        pools[i] = try gc.dev.createCommandPool(&frame_pools_config, null);
        created += 1;
    }
    defer for (0..created) |i| {
        gc.dev.destroyCommandPool(pools[i], null);
    };

    for (0..swapchain_len) |i| {
        recorders[i] = gftx.FrameRecorder{
            .id = @intCast(i),
            .gm = pic.gc,
            .pool = pools[i],
            .cmds = &cmdbufs[i],
        };
        try frame.recordCommandBuffers(
            &recorders[i],
            &models,
            swapchain.extent,
            render_pass,
            framebuffers,
            &draw_instanced_attempt,
            &frame_state,
        );
    }

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
        glass_input.update();
        plr_input.update();

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
            try glass.updateStorage(storage_dset, true);
        }
        if (shader_reset_trigger.fired()) {
            try glass.updateStorage(storage_dset, false);
        }
        if (uniform_shift_trigger.fired()) {
            frame_state.alt_proj = !frame_state.alt_proj;
        }
        if (ok_vis_trigger.fired()) {
            try ok_understanding.updateStorage(storage_dset);
            std.debug.print("+++ jakaś wiadowmość\n", .{});
        }

        if (slide_r_trig.fired()) {
            const last = frame_state.model_idx == models.head - 1;
            frame_state.model_idx = if (last) 0 else frame_state.model_idx + 1;
        }

        if (slide_l_trig.fired()) {
            const first = frame_state.model_idx == 0;
            frame_state.model_idx = if (first) models.head - 1 else frame_state.model_idx - 1;
        }

        //minimalized
        if (!addons.visible(win_size)) {
            glfw.pollEvents();
            continue;
        }
        try swapchain.currentWaitG();
        try frame.recordCommandBuffers(
            &recorders[img_idx],
            &models,
            swapchain.extent,
            render_pass,
            framebuffers,
            &draw_instanced_attempt,
            &frame_state,
        );
        try prefils.perFrameUniformFill(
            uniform_dset,
            @intCast(img_idx),
            timeline.total_s,
            playerPos(&plr),
            size,
        );

        if (state == .suboptimal or addons.extentDiffer(resolution_extent, win_size)) {
            // std.debug.assert(false); //cuz it will throw error due to bad depth_img resolution
            resolution_extent = win_size;
            std.debug.print("+++ a\n", .{});
            try gc.dev.deviceWaitIdle();
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
            for (recorders) |*recorder| {
                try frame.recordCommandBuffers(
                    recorder,
                    &models,
                    swapchain.extent,
                    render_pass,
                    framebuffers,
                    &draw_instanced_attempt,
                    &frame_state,
                );
            }
        }
        const cmdbuf = cmdbufs[swapchain.image_index];
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
fn uploadVertices(pic: *const gftx.PoolInCtx, buffer: vk.Buffer, vert_slice: []const Vertex) !void {
    const buff_size = BufforingVert.memSize(vert_slice);

    var buffer_ = try gftx.createBuffer(
        pic.gc, //
        gftx.baked.memory_cpu,
        gftx.baked.usage_src,
        buff_size,
    );
    defer buffer_.deinit(pic.gc);

    const gpu_vertices: [*]Vertex = @ptrCast(@alignCast(buffer_.mapping));
    //does one @memcpy operation is more effective then #storagePrefill
    @memcpy(gpu_vertices, vert_slice);

    try copyBuffer(pic, buffer, buffer_.dvk_bfr, buff_size);
}

fn copyBuffer(pic: *const gftx.PoolInCtx, dst: vk.Buffer, src: vk.Buffer, size: vk.DeviceSize) !void {
    const vkdev = pic.gc.dev;
    const one_shot = try gftx.OneShotCommanded.init(pic);
    const region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
    vkdev.cmdCopyBuffer(one_shot.cmds, src, dst, 1, @ptrCast(&region));
    try one_shot.resolve();
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
