const std = @import("std");
const tt = @import("stbtt");

const glfw = @import("third_party/glfw.zig");
const vk = @import("vulkan-zig");

const sht = @import("shaders/types.zig");
const shu = @import("shaders/utils.zig");
const gm = @import("graphics_context.zig");

const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const swap = @import("swapchain.zig");
const a = @import("addons.zig");
const d = @import("debug.zig");
const dset = @import("dset.zig");

const vertex = @import("vertex.zig");

const m = @import("math.zig");
const t = @import("types.zig");
const u = @import("utils.zig");

const map = @import("map.zig");
const phys = @import("phys.zig");
const imgs = @import("imgs/imgs.zig");
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

var navig = a.Navig.default;

var state: frame.FrameState = .{
    .model_idx = 0,
    .persp = .observer,
    .alt_proj = true,
    .alt_shader = false,
    .ok_tex_base = OK_TEX_BASE,
    .ok_group = .{ .base = map.instablo.get(.okg).beg, .num = OK_SWEEP },
    .char_group = .{ .base = map.instablo.get(.text).beg, .num = 0 },
    .layer_group = .{ .base = map.instablo.get(.layer).beg, .num = 0 },
    .grig_group = .{ .base = map.instablo.get(.cubes).beg, .num = 0 },
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
    var a_font: fonts.FontRendering = try fonts.FontRendering.init(access.io, pages, "fs/opensans.ttf");
    defer a_font.deinit(pages);

    var abc = try fonts.Alphabet.init(
        access.io,
        access.gpa,
        &a_font,
        "fs/opensans.serdes",
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
    var inflight_num: u8 = undefined;

    const gpa = access.gpa;
    const gc = access.gm;
    var window = access.host;

    var resolution_extent = try window.winExtent();

    const swap_ctx: swap.SwapchainContext = .{
        .gc = access.gm,
        .imga = access.imga,
    };

    var swapchain = try swap.Swapchain.init(&swap_ctx, gpa, resolution_extent);
    defer swapchain.deinit() catch std.debug.print("... well swapchaing deinit failed\n", .{});

    inflight_num = @intCast(swapchain.swap_images.len);
    std.debug.print("+++ Serial frames {}\n", .{inflight_num});

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
        .swapchain_lan = inflight_num,
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
        swapchain.depth_images[0].vk_format,
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
    state.grig_group.num = grid.total;

    const draw_instanced_attempt: gm.DrawInfo = .{
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

    {
        // 0 - 3 few, mostly test textures
        const basic_tex_set: [4]anyerror!imgs.VkImage = .{
            imgs.vulkanTexture(&pic, g64, &imgs.demo_tex_rgb, .default),
            imgs.vulkanTexture(&pic, g64, &imgs.demo_tex_r, .default),
            imgs.vulkanTexture(&pic, looking_vol.grid, looking_vol.pix, .nearest),
            imgs.vulkanTexture(&pic, looking_lyr.grid, looking_lyr.pix, .nearest),
        };
        const basic_idx = 0;
        inline for (0.., basic_tex_set) |i, risky_rgba| {
            const rgba = try risky_rgba;
            try all_imgs.append(&rgba);
            lazy_shady.omnitex.updateTexture(0, &rgba, basic_idx + i);
        }
    }
    {
        // 4 for atlas
        const gridsz_abc = fonts.font_g;
        var vki_glyph_atlas = try imgs.U8Image.init(access.gm, gridsz_abc);
        try imgs.texPrep(&pic, gridsz_abc, abc.char_atlas, &vki_glyph_atlas, .font);
        try all_imgs.append(&vki_glyph_atlas);

        lazy_shady.omnitex.updateTexture(0, &vki_glyph_atlas, 4);
        try d.ppmU8Debug(access.io, abc.char_atlas, gridsz_abc);
    }

    {
        // 5 scan data
        var mono = try imgs.U16Image.init(pic.gc, glass.img_sz);
        errdefer mono.deinit();
        try imgs.texPrep(&pic, glass.img_sz, glass.scan_raw.pixels, &mono, .nearest);
        try all_imgs.append(&mono);

        lazy_shady.omnitex.updateTexture(0, &mono, 5);
    }

    {
        // 32 gradient
        // 33 - 159 ok slices
        const tex_grid_ok = sht.GridSize.g128;
        const L_delt: f32 = 1.0 / @as(f32, @floatFromInt(OK_SWEEP - 1));
        var ok_atlas_idx: u8 = OK_TEX_BASE;
        var L: f32 = 0.0;

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
    }

    // For frame recording
    const inflight_slots = 8;
    std.debug.assert(inflight_num < inflight_slots);

    // recorders
    var slot: u8 = 0;
    var inflight_stack: [1024]u8 = undefined;
    var loc_stack: std.heap.FixedBufferAllocator = .init(inflight_stack[0..1024]);
    var loc_fba = loc_stack.allocator();
    const cmdbufs: []vk.CommandBuffer = try loc_fba.alloc(vk.CommandBuffer, inflight_num);
    const pools: []vk.CommandPool = try loc_fba.alloc(vk.CommandPool, inflight_num);
    const recorders: []gm.FrameRecorder = try loc_fba.alloc(gm.FrameRecorder, inflight_num);
    const frame_cmd_pool_cfg: vk.CommandPoolCreateInfo = .{
        .queue_family_index = gc.graphics_queue.family,
        .flags = .{ .transient_bit = true },
    };

    for (0..inflight_num) |_| {
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
    var vk_state: swap.Swapchain.PresentState = .optimal;

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
    var font_x_phi: f32 = 0;
    var ok_slider: u.Slider = .initMid(0, OK_SWEEP - 1);

    sdlh.wheel.up = .{ .a = &ok_slider, .f = u.Slider.incX5 };
    sdlh.wheel.down = .{ .a = &ok_slider, .f = u.Slider.decX5 };
    var smooth_scale: u.Smooth = .{};

    var last_mouse_pos: m.ivec2 = .{ 0, 0 };
    var panner = proto.Panner.init(&glass);

    // main loop
    const text_sz_base: fonts.TextSz = .{};
    var text_stack: [1024 + 512]u8 = undefined;
    while (!window.shoudClose()) {
        errdefer std.debug.print("!?! problem in main loop\n", .{});
        var fba: std.heap.FixedBufferAllocator = .init(text_stack[0..]);
        const txta = fba.allocator();

        access.host.pollEvents();
        const win_size = try access.host.winExtent();

        if (!a.visible(win_size)) {
            // while minimalized.
            try access.io.sleep(.fromMilliseconds(50), .real);
            continue;
        }

        const win_f2 = m.vkextAsV2(win_size);
        const cursor_f2 = sdlh.peekPointer();
        navig.cursor = cursor_f2;
        navig.cursor_tex = OK_TEX_BASE + ok_slider.curr;

        const coords: a.Coords = .init(win_size);
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
        font_x_phi += td1 * 0.67;

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

        const debug_on_console = false;
        var dbg_scratch: [2048]u8 = undefined;
        var dbg_write = std.Io.Writer.fixed(&dbg_scratch);
        try dbgmonit.update(access.io, &dbg_data, &dbg_write, debug_on_console);

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
            state.persp = switch (state.persp) {
                .orbital => .observer,
                .observer => .orbital,
            };
        }

        var dyn_text: std.ArrayList(u8) = try .initCapacity(txta, 1024 + 512);
        const px, const py = glass.pos;
        try dyn_text.print(txta, "\n\n", .{}); //young blit space
        try dyn_text.print(txta, "looking_glass pos x:{d:>6}|y:{d:>6}\n", .{ px, py });
        // try dyn_text.print(txta, "blit info x:{d:>6.2}|y:{d:>6.2}\n", .{ blit_x.w, blit_x.h });
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

        try swapchain.waitCurrentFrame();
        const storage_mapping = lazy_shady.storage.buff_arr.items[img_idx].?.mapping.?;
        const uniform_mapping = lazy_shady.uniforms.buff_arr.items[img_idx].?.mapping.?;
        const instances: [*]sht.PerInstance = @ptrCast(@alignCast(storage_mapping));
        const uniforms: [*]sht.GroupData = @ptrCast(@alignCast(uniform_mapping));

        const virt_ray: t.Ray = switch (state.persp) {
            .orbital => t.Ray{ .at = orbital.pos(), .to = m.zero3() },
            .observer => a.testTracer(tracker_phi),
        };

        {
            try refils.unifomRefil(
                uniforms,
                timeline1.total_s,
                size,
                win_size,
                virt_ray,
            );
            _ = map.instablo;

            if (state.alt_shader) {
                try glass.recoverKinecticDefault(instances);
            } else {
                try glass.bakeScannData(instances);
                try glass.bakeRidges(instances, &state.layer_group);
            }

            try oklab.OkUnderstanding.labSpliced(
                instances,
                state.ok_group,
                ok_phi,
            );

            // text content selection
            const dyna_dyna_text = switch (dbgmonit.enabled) {
                true => dbg_write.buffered(),
                false => dyn_text.items,
            };
            try fonts.TextBlitter //
                .init(&abc, &state, text_sz_base)
                .contentBlit(instances, win_f2, dyna_dyna_text);
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

            // with new resolution for all
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
            error.OutOfDateKHR => swap.Swapchain.PresentState.suboptimal,
            else => |narrow| {
                std.debug.print("+++ some other presentation error {s}\n", .{@errorName(narrow)});
                return narrow;
            },
        };
    }
    std.debug.print("Exitting\n", .{});
    try swapchain.waitForAllFences();
    try gc.dev.deviceWaitIdle();
}

fn createFramebuffers(gc: *const GraphicsContext, allocator: Allocator, render_pass: vk.RenderPass, swapchain: swap.Swapchain) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swap_images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |fb| gc.dev.destroyFramebuffer(fb, null);

    for (framebuffers) |*fb| {
        const att_arr: []const vk.ImageView = &.{
            swapchain.swap_images[i].view,
            swapchain.depth_images[i].dvk_img_view,
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
