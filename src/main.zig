const std = @import("std");
const tt = @import("stbtt");

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
const prefils = @import("refills.zig");
const oklab = @import("oklab.zig");

const InertiaVec2 = phx.InertiaPack(m.vec3);
const Vertex = vertex.Vertex;

const Allocator = std.mem.Allocator;

const motion = @import("motion.zig");
const frame = @import("frame.zig");

const pipe = @import("pipe.zig");

const app_name = "oct_anotator";
const future_app_name = "oct_calculator";

var time_glob: ?*addons.Timeline = null;
const BasicErrs = error{
    NoCtx,
};

const sdl_wrap = @import("sdl_wrap2.zig");
const sdl = @import("sdl3");

const input = @import("input.zig");
const host = @import("host.zig");
const EasyAcces = host.EasyAcces;

const proto = @import("proto.zig");

pub fn main(init: std.process.Init) !void {
    var chunk4k: [4096]u8 = undefined;
    const cwd = std.Io.Dir.cwd();

    const font_ttf = "fs/roboto.ttf";
    var font_obj: tt.stbtt_fontinfo = undefined;
    var font_data: ?[]const u8 = null;
    var font_ok = false;
    font_read: {
        const ttf_file = cwd.openFile(init.io, font_ttf, .{}) catch {
            std.debug.print("!!! failed to open {s}\n", .{font_ttf});
            break :font_read;
        };
        defer ttf_file.close(init.io);

        var rFile = ttf_file.reader(init.io, chunk4k[0..]);
        const fSize = try rFile.getSize();
        std.debug.print("+++ ttf file size is: {d}\n", .{fSize});
        const ioreader: *std.Io.Reader = &rFile.interface;
        font_data = try ioreader.readAlloc(init.gpa, try rFile.getSize());

        // ioreader.p
        if (tt.stbtt_InitFont(&font_obj, font_data.?.ptr, 0) == 0) {
            std.debug.print("!!! font init failed {s}\n", .{font_ttf});
            break :font_read;
        }
        font_ok = true;
    }
    defer {
        if (font_data) |ttf_slice| init.gpa.free(ttf_slice);
    }

    try host.sdlHost(init, deeper);
}

const OK_SWEEP: u8 = 128;
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

fn deeper(access: EasyAcces) host.OnHostErrors!void {
    theDeepest(access) catch |err| {
        std.debug.print("passenger error, converting to one of MainErrors src {}\n", .{err});
        return host.OnHostErrors.passengerError;
    };
}

fn theDeepest(access: EasyAcces) !void {
    // const grid = sht.GridSize.g64;
    const grid = sht.GridSize.g64;
    const deeper_allocator = std.heap.page_allocator;
    var img = try proto.serdesLoad(access.io, deeper_allocator);
    defer img.deinit(deeper_allocator);

    var glass = proto.LookingGlass.init(&img, grid);
    const ok_understanding = oklab.OkUnderstanding{ .grid = grid };

    var swapchain_len: u8 = undefined;

    const gpa = access.alloc;
    const gc = access.vkctx;
    var window = access.host;

    var resolution_extent = try window.extent();

    var swapchain = try Swapchain.init(gc, gpa, resolution_extent);
    defer swapchain.deinit() catch std.debug.print("... well swapchaing deinit failed\n", .{});

    swapchain_len = @intCast(swapchain.swap_images.len);
    std.debug.print("+++ Serial frames {}\n", .{swapchain_len});

    const general_cpool = try gpCommandQueue(gc);
    defer gc.dev.destroyCommandPool(general_cpool, null);
    const pic = gm.PoolInCtx{ .gc = gc, .pool = general_cpool };

    var uniform_dset = try dset.DescriptorPrep.init(
        gpa,
        gc,
        swapchain_len,
        gm.baked.uniform_frag_vert_dyn,
        .{
            .binding = 0,
            .element_size = @sizeOf(sht.GroupData),
            .num = 16,
        },
        null,
    );
    defer uniform_dset.deinit(gpa);

    var storage_dset = try dset.DescriptorPrep.init(
        gpa,
        gc,
        swapchain_len,
        gm.baked.storage_frag_vert,
        .{
            .binding = 0,
            .element_size = @sizeOf(sht.PerInstance) * @as(u32, grid.total) * 2,
        },
        null,
    );
    defer storage_dset.deinit(gpa);

    const spacing = 0.1;
    const size = 0.04;
    try prefils.storagePrefil(storage_dset, grid, spacing);

    const ATLAS_MAX = 256;
    var dset_atlas = try dset.DescriptorPrep.init(
        gpa,
        gc,
        1,
        gm.baked.texture_frag,
        .{ .binding = 0 },
        ATLAS_MAX,
    );
    defer dset_atlas.deinit(gpa);
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
    var testing = true;
    for (&ok_samples) |*sample| {
        std.debug.assert(atlas_idx < ATLAS_MAX);
        var sampled: []const u8 = undefined;
        if (testing) {
            testing = false;
            sampled = try oklab.OkUnderstanding.sampleInfernoAlt(gpa, &ok_g);
        } else {
            sampled = try oklab.OkUnderstanding.sampleSpace(gpa, L, &ok_g);
        }
        defer gpa.free(sampled);
        const ok_rgba = try imgs.vulkanTexture(&pic, ok_g, sampled);
        dset_atlas.updateTexture(0, &ok_rgba, atlas_idx);

        L += L_delt;
        atlas_idx += 1;
        sample.* = ok_rgba;
    }

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
        gpa,
        render_pass,
        swapchain,
    );
    defer destroyFramebuffers(gc, gpa, framebuffers);

    var repo = try vertex.repoSpawn(gpa, &pic);
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

    var timeline = addons.Timeline.init(access.io);
    var timeline1 = addons.Timeline.init(access.io);
    time_glob = &timeline;
    var perf_stats = addons.PerfStats.init(access.io);
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

    var okphi: f32 = 0;
    while (!window.shoudClose()) {
        const img_idx = swapchain.image_index;
        // input_continue();
        input.glass_input.update();
        input.plr_input.update();

        // Don't present or resize swapchain while the window is minimized
        perf_stats.messure(access.io);
        timeline.update(access.io);
        timeline1.update(access.io);

        if (timeline1.triggerd()) {
            // std.debug.print("+++ interval info:D\n", .{});
        }

        if (input.exit_trig.fired()) window.setShoudClose(true);
        if (input.time_stop_trig.fired()) timeline1.passageToggle();

        const td = timeline.deltaS();
        const td1 = timeline1.deltaS();
        okphi += td1 * 0.1;
        pamperek.control(&input.plr_input, td);

        try phi_val_monit.update(access.io, pamperek.p.phi);
        if (glass.update(&input.glass_input)) {
            try glass.updateStorage(storage_dset, true);
        }
        if (input.shader_reset_trigger.fired()) {
            try glass.updateStorage(storage_dset, false);
        }
        if (input.uniform_shift_trigger.fired()) {
            frame_state.alt_proj = !frame_state.alt_proj;
        }
        if (input.ok_vis_trigger.fired()) {
            try ok_understanding.labAtInfinitum(storage_dset);
        }

        if (input.slide_r_trig.fired()) {
            const last = frame_state.model_idx == repo.head - 1;
            frame_state.model_idx = if (last) 0 else frame_state.model_idx + 1;
        }

        if (input.slide_l_trig.fired()) {
            const first = frame_state.model_idx == 0;
            frame_state.model_idx = if (first) repo.head - 1 else frame_state.model_idx - 1;
        }

        //minimalized
        const win_size = try window.extent();
        if (!addons.visible(win_size)) {
            access.host.pollEvents();
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
            timeline1.total_s,
            pamperek.pos(),
            size,
            win_size,
        );
        try oklab.OkUnderstanding.labSpliced(
            storage_dset,
            OK_SWEEP,
            okphi,
        );

        if (state == .suboptimal or addons.extentDiffer(resolution_extent, win_size)) {
            // std.debug.assert(false); //cuz it will throw error due to bad depth_img resolution
            resolution_extent = win_size;
            try gc.dev.deviceWaitIdle();
            try swapchain.recreate(resolution_extent);

            destroyFramebuffers(gc, gpa, framebuffers);
            framebuffers = try createFramebuffers(
                gc,
                gpa,
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

        access.host.pollEvents();
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
