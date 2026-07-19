const std = @import("std");
const tt = @import("stbtt");

const glfw = @import("third_party/glfw.zig");
const vk = @import("vulkan-zig");

const sht = @import("shaders/types.zig");
const shu = @import("shaders/utils.zig");
const gm = @import("graphics_context.zig");

const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Swapchain = @import("swapchain.zig").Swapchain;
const a = @import("addons.zig");
const d = @import("debug.zig");
const dset = @import("dset.zig");

const vertex = @import("vertex.zig");

const m = @import("math.zig");
const t = @import("types.zig");
const u = @import("utils.zig");
const phys = @import("phys.zig");
const imgs = @import("imgs.zig");
const refils = @import("refills.zig");
const oklab = @import("oklab.zig");

const oct = @import("oct");
const well = oct.f32_arr_3d_t;

const InertiaVec2 = phys.InertiaPack(m.vec3);
const Vertex = vertex.Vertex;

const Allocator = std.mem.Allocator;

const motion = @import("motion.zig");
const frame = @import("frame.zig");

const pipe = @import("pipe.zig");

const app_name = "oct_anotator";
const future_app_name = "oct_calculator";

var time_glob: ?*a.Timeline = null;
const BasicErrs = error{
    NoCtx,
};

const sdlh = @import("sdlh.zig");

const input = @import("input.zig");
const host = @import("host.zig");
const EasyAcces = host.EasyAcces;

const proto = @import("proto.zig");
const fonts = @import("fonts.zig");

pub fn main(init: std.process.Init) !void {
    try host.sdlHost(init, deeper);
}

const OK_SWEEP: u8 = 128;
const OK_TEX_BASE: u8 = 32;
const OK_INST_BASE: u16 = sht.GridSize.g64.total;
const CHAR_INST_BASE: u16 = 4608;
const LYR_INST_BASE = 6144;

var navig = a.Navig.default;

var state: frame.FrameState = .{
    .def_persp = true,
    .alt_proj = true,
    .alt_shader = false,
    .ok_tex_base = OK_TEX_BASE,
    .model_idx = 0,
    .ok_group = .{ .base = OK_INST_BASE, .num = OK_SWEEP },
    .char_group = .{ .base = CHAR_INST_BASE, .num = 0 },
    .layer_group = .{ .base = LYR_INST_BASE, .num = 0 },
    .nav = &navig,
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
    const pages = std.heap.page_allocator;
    // font
    var a_font: fonts.FontRendering = try fonts.FontRendering.init(access.io, pages, "fs/roboto.ttf");
    defer a_font.deinit(pages);

    var abc = try fonts.Alphabet.init(
        access.io,
        access.gpa,
        &a_font,
        "fs/font.serdes",
    );
    defer abc.deinit(access.gpa);

    // vol data
    var dual_img = try proto.serdesLoadBackup(access.io, pages);
    defer dual_img.deinit(pages);

    const grid = sht.GridSize.g64;
    var glass = proto.LookingGlass.init(&dual_img, grid);

    var looking_vol = try glass.sampleVolData(access.gpa);
    defer looking_vol.deinit(access.gpa);
    var looking_lyr = try glass.sampleLayers(access.gpa);
    defer looking_lyr.deinit(access.gpa);

    navig.scann_sz = looking_vol.size;
    navig.scann_aspect = navig.aspectScale();

    //vk related
    var swapchain_len: u8 = undefined;

    const gpa = access.gpa;
    const gc = access.gm;
    var window = access.host;

    var resolution_extent = try window.winExtent();

    var swapchain = try Swapchain.init(gc, gpa, resolution_extent);
    defer swapchain.deinit() catch std.debug.print("... well swapchaing deinit failed\n", .{});

    swapchain_len = @intCast(swapchain.swap_images.len);
    std.debug.print("+++ Serial frames {}\n", .{swapchain_len});

    const general_cpool = try gpCommandQueue(gc);
    defer gc.dev.destroyCommandPool(general_cpool, null);
    const pic = gm.PoolInCtx{ .gc = gc, .pool = general_cpool };

    //descriptor sets
    {
        const _64kb = 1 << 16;
        var stack_dset: [_64kb]u8 = undefined;
        var stalloc: std.heap.FixedBufferAllocator = .init(stack_dset[0..]);
        const dsa = stalloc.allocator();
        _ = dsa;
    }

    var desets_arena: std.heap.ArenaAllocator = .init(gpa);
    defer desets_arena.deinit();
    const aa = desets_arena.allocator();

    const hl_dset = dset.HLDSetPrep{
        .gc = gc,
        .gpa = aa,
    };

    const _8k = 1 << 13;
    std.debug.assert(grid.total * 2 == _8k);

    const ATLAS_MAX = 256;
    const instpool_num = grid.total * 2;

    const storage_b_sz = @sizeOf(sht.SmolInst) * instpool_num;
    _ = storage_b_sz;
    const lazy_opt: dset.ShadyGroup.Options = .{
        .swapchain_lan = swapchain_len,
        .atlas_size = ATLAS_MAX,
        .ubo_size = @sizeOf(sht.GroupData),
        .storag_size = @sizeOf(sht.PerInstance) * instpool_num,
    };
    var lazy_shady: dset.ShadyGroup = try .init(&hl_dset, lazy_opt);
    defer lazy_shady.drop(&hl_dset);

    // rendering & pipelines
    const render_pass = try pipe.createRenderPass(
        gc,
        swapchain.surface_format.format,
        swapchain.depth_image.vk_format,
    );
    defer gc.dev.destroyRenderPass(render_pass, null);

    const desc_sets = lazy_shady.layout();
    const push_const_ranges = gm.PushConstant.Ranges();
    const pipeline_layout = try gc.dev.createPipelineLayout(&.{
        .flags = .{},
        .p_set_layouts = &desc_sets,
        .set_layout_count = desc_sets.len,
        .p_push_constant_ranges = push_const_ranges.ptr,
        .push_constant_range_count = @intCast(push_const_ranges.len),
    }, null);
    defer gc.dev.destroyPipelineLayout(pipeline_layout, null);

    var framebuffers = try createFramebuffers(
        gc,
        gpa,
        render_pass,
        swapchain,
    );
    defer destroyFramebuffers(gc, gpa, framebuffers);

    // pipelines
    const pipe_mod: pipe.Moduler = .{
        .gc = gc,
        .layout = pipeline_layout,
    };

    var num: u8 = 0;
    const all_brush = std.enums.values(pipe.EBrush);
    var pipelines: [all_brush.len]vk.Pipeline = undefined;
    for (0.., all_brush) |i, pencil| {
        pipelines[i] = try pipe_mod.createPipeline(render_pass, pencil);
        num += 1;
    }
    defer for (0..num) |i| {
        pipe_mod.destroyPipelin(pipelines[i]);
    };

    var repo = try vertex.repoSpawn(gpa, &pic);
    defer repo.deinit(gc);
    std.debug.print("+++ total verts {d}\n", .{repo.total});

    const draw_instanced_attempt: gm.DrawInfo = .{
        .instance_count = grid.total, // TODO: something like "InstanceMapping"...
        .pipeline = pipelines,
        .pipeline_layout = pipeline_layout,
        .uniform_dsets = lazy_shady.uniforms.d_set_arr,
        .storage_dsets = lazy_shady.storage.d_set_arr,
        .texture_dset = lazy_shady.omnitex.d_set_arr.items[0],
        .models = &repo,
    };

    // grid saved
    const spacing = 0.1;
    const size = 0.04;
    try refils.gridPrefil(lazy_shady.storage, grid, spacing);

    // textures
    const g64 = sht.GridSize.g64;

    var all_imgs: imgs.ManyImages = try .init(access.gpa);
    defer all_imgs.deinit();

    const basic_idx = 0;
    const basic_tex_set: [4]anyerror!imgs.VkImage = .{
        imgs.vulkanTexture(&pic, g64, &imgs.demo_tex_rgb, .default),
        imgs.vulkanTexture(&pic, g64, &imgs.demo_tex_r, .default),
        imgs.vulkanTexture(&pic, looking_vol.grid, looking_vol.pix, .nearest),
        imgs.vulkanTexture(&pic, looking_lyr.grid, looking_lyr.pix, .nearest),
    };
    {
        inline for (0.., basic_tex_set) |i, risky_rgba| {
            const rgba = try risky_rgba;
            try all_imgs.append(&rgba);
            lazy_shady.omnitex.updateTexture(0, &rgba, basic_idx + i);
        }
    }

    const g_abc = fonts.font_g;
    try d.ppmU8Debug(access.io, abc.char_atlas, g_abc);

    var char_atlas = try imgs.U8Image.init(access.gm, g_abc);
    try imgs.texPrep(&pic, g_abc, abc.char_atlas, &char_atlas, .default);

    // const sdf_atlas = try imgs.vulkanTexture(&pic, g_abc, abc.char_atlas, false);
    lazy_shady.omnitex.updateTexture(0, &char_atlas, 4);
    try all_imgs.append(&char_atlas);

    {
        var mono = try imgs.U16Image.init(pic.gc, glass.img_sz);
        errdefer mono.deinit();
        try imgs.texPrep(&pic, glass.img_sz, glass.scan_raw.pixels, &mono, .nearest);
        lazy_shady.omnitex.updateTexture(0, &mono, 5);
        try all_imgs.append(&mono);
    }

    const L_delt: f32 = 1.0 / @as(f32, @floatFromInt(OK_SWEEP - 1));
    var ok_atlas_idx: u8 = OK_TEX_BASE;
    var L: f32 = 0.0;

    const tex_grid_ok = sht.GridSize.g128;
    for (0..OK_SWEEP) |i| {
        std.debug.assert(ok_atlas_idx < ATLAS_MAX);
        const pixels = switch (i) {
            0 => try oklab.sampleInfernoAlt(gpa, &tex_grid_ok),
            else => try oklab.OkUnderstanding.sampleSpace(gpa, L, &tex_grid_ok),
        };
        defer gpa.free(pixels);

        const rgba = try imgs.vulkanTexture(&pic, tex_grid_ok, pixels, .nearest);
        lazy_shady.omnitex.updateTexture(0, &rgba, ok_atlas_idx);
        try all_imgs.append(&rgba);

        ok_atlas_idx += 1;
        L += L_delt;
    }

    // For frame recording
    const inflight_slots = 8;
    std.debug.assert(swapchain_len < inflight_slots);

    // recorders
    var slot: u8 = 0;
    var inflight_stack: [1024]u8 = undefined;
    var loc_stack: std.heap.FixedBufferAllocator = .init(inflight_stack[0..1024]);
    const cmdbufs: []vk.CommandBuffer = try loc_stack.allocator().alloc(vk.CommandBuffer, swapchain_len);
    const pools: []vk.CommandPool = try loc_stack.allocator().alloc(vk.CommandPool, swapchain_len);
    const recorders: []gm.FrameRecorder = try loc_stack.allocator().alloc(gm.FrameRecorder, swapchain_len);
    const frame_cmd_pool_cfg: vk.CommandPoolCreateInfo = .{
        .queue_family_index = gc.graphics_queue.family,
        .flags = .{ .transient_bit = true },
    };

    for (0..swapchain_len) |_| {
        pools[slot] = try gc.dev.createCommandPool(&frame_cmd_pool_cfg, null);
        recorders[slot] = gm.FrameRecorder{
            .id = @intCast(slot),
            .gm = pic.gc,
            .pool = pools[slot],
            .cmds = &cmdbufs[slot],
        };
        slot += 1;
    }
    defer for (0..slot) |i| gc.dev.destroyCommandPool(pools[i], null);

    // Related to scene
    var timeline = a.Timeline.init(access.io);
    var timeline1 = a.Timeline.init(access.io);
    time_glob = &timeline;
    var perf_stats = a.PerfStats.init(access.io);
    var vk_state: Swapchain.PresentState = .optimal;

    const s_interval = std.time.us_per_s;
    timeline1.arm(s_interval * 0.5);

    var orbital: u.CappedPlayer = .default;
    orbital.inertia.phx = .default;

    const IVec3 = phys.InertiaPack(m.vec3);
    var inertia = IVec3.Inertia.init(.{ orbital.phi_raw, 0, 0 });
    inertia.phx = .default;

    var dbgmonit = d.DbgMonitor{};

    //state
    var ok_phi: f32 = 0;
    var glyph_phi: f32 = 0;
    var tracker_phi: f32 = 0;
    var ok_slider: u.Slider = .initMid(0, OK_SWEEP - 1);

    sdlh.wheel.up = .{ .a = &ok_slider, .f = u.Slider.incX5 };
    sdlh.wheel.down = .{ .a = &ok_slider, .f = u.Slider.decX5 };
    var smooth_scale: u.Smooth = .{};

    var last_mouse_pos: m.ivec2 = .{ 0, 0 };
    var panner = proto.Panner.init(&glass);

    // main loop
    var text_stack: [1024 + 512]u8 = undefined;
    while (!window.shoudClose()) {
        var fba: std.heap.FixedBufferAllocator = .init(text_stack[0..]);
        const txta = fba.allocator();

        access.host.pollEvents();
        const win_size = try access.host.winExtent();

        if (!a.visible(win_size)) {
            try access.io.sleep(.fromMilliseconds(50), .real);
            continue;
        }
        // navig.pos = input.

        const win_f2 = m.vkextAsV2(win_size);
        const coords: a.Coords = .init(win_size);
        const cursor_f2 = sdlh.peekPointer();
        navig.cursor = cursor_f2;
        navig.cursor_tex = OK_TEX_BASE + ok_slider.curr;

        const interact = coords.update(cursor_f2);
        navig.screan = win_f2;

        const img_idx = swapchain.image_index;

        input.updateAxes();

        perf_stats.messure(access.io);
        timeline.update(access.io);
        timeline1.update(access.io);

        const td = timeline.deltaS();
        const td1 = timeline1.deltaS();
        ok_phi += td1 * 0.1;
        glyph_phi += td1 * 0.13;
        tracker_phi += td1 * 3;

        if (input.exit_trig.fired()) window.closeWindow();
        if (input.time_stop_trig.fired()) timeline1.passageToggle();

        if (input.shader_reset_trigger.fired()) state.alt_shader = true;

        const refresh_cond = glass.update(&input.glass_input, td);
        if (refresh_cond) state.alt_shader = false;

        // orbit control
        panner.update(&input.pan_input, last_mouse_pos);
        orbital.update(td, &input.plr_input);

        smooth_scale.update(td, ok_slider.frac());

        const zoom_scale = smooth_scale.out() * 0.95 + 0.05;
        const scann_scale = m.splat2d(zoom_scale) * m.vec2{ 1, shu.gridAspect(glass.img_sz) };

        const glass_frac = glass.frac();
        const xoff, const yoff = glass_frac;
        const scann_xoff = switch (xoff + scann_scale[0] > 1) {
            true => 1.0 - scann_scale[0],
            false => xoff,
        };
        const scann_yoff = switch (yoff + scann_scale[1] > 1) {
            true => 1.0 - scann_scale[1],
            false => yoff,
        };

        // navig.uv_map.mult = @splat(scan_scale);
        navig.uv_map.mult = scann_scale;
        navig.uv_map.offset = .{ scann_xoff, scann_yoff };

        const dbg_data = d.DbgMonitor.DbgVals{
            .phi = orbital.p.phi,
            .inst_num = state.layer_group.num,
            .observer_pos = orbital.pos(),
            .win_size = win_size,
        };

        try dbgmonit.update(access.io, &dbg_data);

        if (input.alt_projection_trigger.fired()) {
            state.alt_proj = !state.alt_proj;
        }

        if (input.slide_r_trig.fired()) {
            state.model_idx = a.wrapUp(state.model_idx, repo.head);
        }

        if (input.slide_l_trig.fired()) {
            state.model_idx = a.wrapDown(state.model_idx, repo.head);
        }

        if (input.dbg_trig.fired()) {
            dbgmonit.enabled = a.toggle(dbgmonit.enabled);
        }

        if (input.inverse_tirg.fired()) {
            glass.inverse = a.toggle(glass.inverse);
        }

        if (input.persp_switch.fired()) {
            state.def_persp = a.toggle(state.def_persp);
        }

        var dyn_text: std.ArrayList(u8) = try .initCapacity(txta, 1024);
        const px, const py = glass.pos;
        try dyn_text.print(txta, "looking_glass pos x:{d:>6}|y:{d:>6}\n", .{ px, py });
        if (interact.hit) {
            // const x, const y = interact.at;
            const scale_frac = navig.uv_map.mult * interact.at;
            const s_x, const s_y = scale_frac;
            const mlt_x, const mlt_y = scale_frac + navig.uv_map.offset;

            const p_x_s = s_x * m.floaty(glass.img_sz.w);
            const p_y_s = s_y * m.floaty(glass.img_sz.h);
            const p_x = mlt_x * m.floaty(glass.img_sz.w);
            const p_y = mlt_y * m.floaty(glass.img_sz.h);

            last_mouse_pos = m.ivec2{
                @intCast(m.uinty(p_x_s)),
                @intCast(m.uinty(p_y_s)),
            };

            const pd = panner.pan_delta_total_prev;

            try dyn_text.print(txta, "{s:<16} | x:{d:>6} y:{d:>6}\n", .{ "pixel pos", m.uinty(p_x), m.uinty(p_y) });
            try dyn_text.print(txta, "{s:<16} | x:{d:>6} y:{d:>6}\n", .{ "pan delta", pd[0], pd[1] });
            // try dyn_text.print(txta, "{s:<16} | x:{d:>6.2} y:{d:>6.2}\n", .{ "cursor at", x, y });
        } else {
            _ = input.sample_tirg.fired();
        }

        //minimalized
        try swapchain.waitCurrentFrame();
        const storage_mapping = lazy_shady.storage.buff_arr.items[img_idx].?.mapping.?;
        const uniform_mapping = lazy_shady.uniforms.buff_arr.items[img_idx].?.mapping.?;
        const instances: [*]sht.PerInstance = @ptrCast(@alignCast(storage_mapping));
        const uniforms: [*]sht.GroupData = @ptrCast(@alignCast(uniform_mapping));

        const virt_ray: t.Ray = switch (state.def_persp) {
            true => t.Ray{ .at = orbital.pos(), .to = m.zero3() },
            false => a.testTracer(tracker_phi),
        };

        {
            try refils.unifomRefil(
                uniforms,
                timeline1.total_s,
                size,
                win_size,
                virt_ray,
            );

            // PLAIN INSTANCES MAP:
            // cubes 0-4095
            // ok slices 4096-4223
            // glyphs 4224-4247
            // text 4608-?
            // layers 6144-?

            if (state.alt_shader) {
                try glass.bakeScann(instances, false);
            } else {
                try glass.bakeScann(instances, true);
                const lnum = try glass.bakeRidges(
                    instances,
                    state.layer_group.base,
                    false,
                );
                state.layer_group.num = lnum;
            }

            try oklab.OkUnderstanding.labSpliced(
                instances,
                state.ok_group.base,
                state.ok_group.num,
                ok_phi,
            );

            state.char_group.num = try abc.BlitText(
                instances,
                state.char_group.base,
                dyn_text.items,
            );
        }

        try frame.recordFrame(
            &recorders[img_idx],
            swapchain.extent,
            render_pass,
            framebuffers,
            &draw_instanced_attempt,
            &state,
        );
        if (vk_state == .suboptimal or a.extentDiffer(resolution_extent, win_size)) {
            resolution_extent = win_size;
            try gc.dev.deviceWaitIdle();
            swapchain.recreate(resolution_extent) catch |err| {
                std.debug.print("!!! hit error at recreate |> {s}\n", .{@errorName(err)});
                std.debug.print("!!! prev win_size w:{d} h:{d}\n", .{ win_size.width, win_size.height });
                try access.io.sleep(std.Io.Duration.fromMilliseconds(2000), .real);

                access.host.pollEvents();
                const new_win_size = try access.host.winExtent();
                std.debug.print("!!! new win_size w:{d} h:{d}\n", .{ new_win_size.width, new_win_size.height });
                return;
            };

            destroyFramebuffers(gc, gpa, framebuffers);
            framebuffers = try createFramebuffers(
                gc,
                gpa,
                render_pass,
                swapchain,
            );

            // TODO: do need to record all?
            for (recorders) |*recorder| {
                try frame.recordFrame(
                    recorder,
                    swapchain.extent,
                    render_pass,
                    framebuffers,
                    &draw_instanced_attempt,
                    &state,
                );
            }
        }

        const cmdbuf = cmdbufs[swapchain.image_index];
        vk_state = swapchain.present(cmdbuf) catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => |narrow| {
                std.debug.print("+++ some other presentation error {s}\n", .{@errorName(narrow)});
                return narrow;
            },
        };
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

test "do it even testing" {
    try std.testing.expect(true);
}
