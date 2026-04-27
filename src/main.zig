const std = @import("std");

const glfw = @import("third_party/glfw.zig");
const vk = @import("third_party/vk.zig");

const sht = @import("shaders/types.zig");
const shu = @import("shaders/utils.zig");
const gm = @import("graphics_context.zig");

const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Swapchain = @import("swapchain.zig").Swapchain;
const addons = @import("addons.zig");
const dset = @import("dset.zig");

const vertex = @import("vertex.zig");

const m = @import("math.zig");
const t = @import("types.zig");
const u = @import("utils.zig");
const phx = @import("phys.zig");
const imgs = @import("imgs.zig");
const prefils = @import("prefills.zig");
const oklab = @import("oklab.zig");

const InertiaVec2 = phx.InertiaPack(m.vec3);
const Vertex = vertex.Vertex;

const Allocator = std.mem.Allocator;

const motion = @import("motion.zig");
const frame = @import("frame.zig");

const pipe = @import("pipe.zig");

const app_name = "vulkan-zig triangle example";
const future_app_name = "oct_calculator";

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

    vertex.probing(false);

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

const OK_SWEEP: u8 = 32;
var frame_state: frame.FrameState = .{
    .alt_proj = false,
    .model_idx = 0,
    .ok_slices_num = OK_SWEEP,
};

pub fn gpCommandQueue(gc: *const gm.GraphicsContext) !vk.CommandPool {
    const pool_cinfo: vk.CommandPoolCreateInfo = .{
        .queue_family_index = gc.graphics_queue.family,
        .flags = .{
            .reset_command_buffer_bit = true,
            // .transient_bit = true,
        },
    };
    return gc.dev.createCommandPool(&pool_cinfo, null);
}

fn deeper(access: EasyAcces) !void {
    // const grid = sht.GridSize.g64;
    const grid = sht.GridSize.g64;
    const deeper_allocator = std.heap.page_allocator;
    var img = try proto.serdesLoad(deeper_allocator);
    defer img.deinit(deeper_allocator);

    var glass = proto.LookingGlass.init(&img, grid);
    const ok_understanding = oklab.OkUnderstanding{ .grid = grid };

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
    const general_cpool = try gpCommandQueue(gc);
    defer gc.dev.destroyCommandPool(general_cpool, null);
    const pic = gm.PoolInCtx{ .gc = gc, .pool = general_cpool };

    // fn theDeepest()
    var uniform_dset = try dset.DescriptorPrep.init(
        allocator,
        gc,
        swapchain_len,
        gm.baked.uniform_frag_vert_dyn,
        .{
            .binding = 0,
            .element_size = @sizeOf(sht.GroupData),
            .num = 3,
        },
        null,
    );
    defer uniform_dset.deinit(allocator);

    var storage_dset = try dset.DescriptorPrep.init(
        allocator,
        gc,
        swapchain_len,
        gm.baked.storage_frag_vert,
        .{
            .binding = 0,
            .element_size = @sizeOf(sht.PerInstance) * @as(u32, grid.total) * 2,
        },
        null,
    );
    defer storage_dset.deinit(allocator);

    const spacing = 0.1;
    const size = 0.04;
    try prefils.storagePrefil(storage_dset, grid, spacing);

    const ATLAS_MAX = 64;
    var dset_atlas = try dset.DescriptorPrep.init(
        allocator,
        gc,
        1,
        gm.baked.texture_frag,
        .{ .binding = 0 },
        ATLAS_MAX,
    );
    defer dset_atlas.deinit(allocator);
    const g64 = sht.GridSize.g64;

    var demo_rgb = try imgs.vulkanTexture(&pic, g64, &imgs.demo_tex_rgb);
    var demo_r = try imgs.vulkanTexture(&pic, g64, &imgs.demo_tex_r);
    defer demo_rgb.deinit();
    defer demo_r.deinit();
    dset_atlas.updateTexture(0, &demo_rgb, 0);
    dset_atlas.updateTexture(0, &demo_r, 1);

    const L_delt: f32 = 1.0 / @as(f32, @floatFromInt(OK_SWEEP - 1));
    var L: f32 = 0.0;

    var ok_samples: [OK_SWEEP]?gm.RGBImage = undefined;
    for (&ok_samples) |*sample| sample.* = null;
    defer for (&ok_samples) |*sample| if (sample.*) |*valid| valid.deinit();

    var atlas_idx: u8 = 32;
    const ok_g = sht.GridSize.g128;
    for (&ok_samples) |*sample| {
        std.debug.assert(atlas_idx < ATLAS_MAX);
        const oksample = try oklab.OkUnderstanding.sampleSpace(allocator, L, &ok_g);
        defer allocator.free(oksample);
        const ok_rgba = try imgs.vulkanTexture(&pic, ok_g, oksample);
        dset_atlas.updateTexture(0, &ok_rgba, atlas_idx);

        L += L_delt;
        atlas_idx += 1;
        sample.* = ok_rgba;
    }
    try oklab.OkUnderstanding.labSpliced(storage_dset, OK_SWEEP);

    // render pass
    const render_pass = try createRenderPass(gc, swapchain);
    defer gc.dev.destroyRenderPass(render_pass, null);

    // pipeline
    const dsets = [_]vk.DescriptorSetLayout{
        uniform_dset._d_set_layout.?,
        storage_dset._d_set_layout.?,
        dset_atlas._d_set_layout.?,
    };
    const pipeline_layout = try gc.dev.createPipelineLayout(&.{
        .flags = .{},
        .p_set_layouts = &dsets,
        .set_layout_count = dsets.len,
        .p_push_constant_ranges = undefined,
        .push_constant_range_count = 0,
    }, null);
    defer gc.dev.destroyPipelineLayout(pipeline_layout, null);

    const pipeline = try pipe.createPipeline(gc, pipeline_layout, render_pass);
    const pipeline_2nd = try pipe.createPipelineAlt(gc, pipeline_layout, render_pass);
    defer gc.dev.destroyPipeline(pipeline, null);
    defer gc.dev.destroyPipeline(pipeline_2nd, null);

    // framebuffers
    var framebuffers = try createFramebuffers(
        gc,
        allocator,
        render_pass,
        swapchain,
    );
    defer destroyFramebuffers(gc, allocator, framebuffers);

    var repo = try vertex.repoSpawn(allocator, &pic);
    defer repo.deinit(gc);
    std.debug.print("+++ total verts {d}\n", .{repo.total});

    const draw_instanced_attempt: gm.DrawInfo = .{
        .instance_count = grid.total,
        .pipeline = [4]vk.Pipeline{ pipeline, pipeline_2nd, undefined, undefined },
        .pipeline_layout = pipeline_layout,
        .uniform_dsets = uniform_dset.d_set_arr,
        .storage_dsets = storage_dset.d_set_arr,
        .texture_dset = dset_atlas.d_set_arr.items[0],
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
    const recorders: []gm.FrameRecorder = try loc_stack.allocator().alloc(gm.FrameRecorder, swapchain_len);

    var created: u8 = 0;
    for (0..swapchain_len) |i| {
        pools[i] = try gc.dev.createCommandPool(&frame_pools_config, null);
        created += 1;
    }
    defer for (0..created) |i| {
        gc.dev.destroyCommandPool(pools[i], null);
    };

    for (0..swapchain_len) |i| {
        recorders[i] = gm.FrameRecorder{
            .id = @intCast(i),
            .gm = pic.gc,
            .pool = pools[i],
            .cmds = &cmdbufs[i],
        };
        try frame.recordFrame(
            &recorders[i],
            &repo,
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

    const s_interval = std.time.us_per_s;
    timeline1.arm(s_interval * 0.5);

    var pamperek: u.CappedPlayer = .default;
    pamperek.inertia.phx = .default;

    const IVec3 = phx.InertiaPack(m.vec3);
    var inertia = IVec3.Inertia.init(.{ pamperek.phi_raw, 0, 0 });
    inertia.phx = .default;

    var phi_val_monit = u.ValMonit{
        .name = "phi val",
        .val = 0,
    };

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
        pamperek.control(&plr_input, td);
        try phi_val_monit.update(pamperek.p.phi);

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
            try ok_understanding.labAtInfinitum(storage_dset);
        }

        if (slide_r_trig.fired()) {
            const last = frame_state.model_idx == repo.head - 1;
            frame_state.model_idx = if (last) 0 else frame_state.model_idx + 1;
        }

        if (slide_l_trig.fired()) {
            const first = frame_state.model_idx == 0;
            frame_state.model_idx = if (first) repo.head - 1 else frame_state.model_idx - 1;
        }

        //minimalized
        if (!addons.visible(win_size)) {
            glfw.pollEvents();
            continue;
        }
        try swapchain.currentWaitG();
        try frame.recordFrame(
            &recorders[img_idx],
            &repo,
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
            pamperek.pos(),
            size,
            win_size,
        );

        if (state == .suboptimal or addons.extentDiffer(resolution_extent, win_size)) {
            // std.debug.assert(false); //cuz it will throw error due to bad depth_img resolution
            resolution_extent = win_size;
            try gc.dev.deviceWaitIdle();
            try swapchain.recreate(resolution_extent);

            destroyFramebuffers(gc, allocator, framebuffers);
            framebuffers = try createFramebuffers(
                gc,
                allocator,
                render_pass,
                swapchain,
            );

            for (recorders) |*recorder| {
                try frame.recordFrame(
                    recorder,
                    &repo,
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

test "do it even testing" {
    try std.testing.expect(true);
}
