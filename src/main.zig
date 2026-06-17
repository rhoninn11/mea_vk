const std = @import("std");
const tt = @import("stbtt");

const glfw = @import("third_party/glfw.zig");
const vk = @import("vulkan-zig");

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
const refils = @import("refills.zig");
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
const last_q = sht.GridSize.g64.total + sht.GridSize.g64.total / 2;
const last_half_of_last_q = sht.GridSize.g64.total + sht.GridSize.g64.total / 2;
const first_letter_instance = 4608;
const first_layer_instance = 6144;
var navig: frame.Navig = .{
    .screan = .{ 128, 128 },
    .cursor = .{ 0, 0 },

    .scann_sz = .{ 1, 1 },

    .inner_scale = .{ 1, 1 },
    .inner_offset = .{ 0, 0 },

    .ok_tex_off = 0,
};

var frame_state: frame.FrameState = .{
    .alt_proj = false,
    .model_idx = 0,
    .ok_slices_num = OK_SWEEP,
    .layer_instance_offset = first_layer_instance,
    .layer_instance_num = 0,
    .letters_inst_offset = first_letter_instance,
    .letters_inst_num = 0,
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
    var mbfont: ?fonts.FontRendering = fonts.FontRendering.init(access.io, pages, "fs/roboto.ttf") catch null;
    defer if (mbfont) |font| font.deinit(pages);

    var mbalphabet: ?fonts.Alphabet = null;
    defer if (mbalphabet) |*alphabet| alphabet.deinit(access.gpa);

    if (mbfont) |*font| {
        mbalphabet = try fonts.Alphabet.init(access.gpa, font);
    }

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

    //vk related
    var swapchain_len: u8 = undefined;

    const gpa = access.gpa;
    const gc = access.vkctx;
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

    const ubo_sz = @sizeOf(sht.GroupData);
    const instpool_num = grid.total * 2;
    const storage_a_sz = @sizeOf(sht.PerInstance) * instpool_num;
    const storage_b_sz = @sizeOf(sht.SmolInst) * instpool_num;
    std.debug.print(
        "+++ storage_med {d: >12}B | storage_small {d: >12}B",
        .{ storage_a_sz, storage_b_sz },
    );

    var dset_uniform = try hl_dset.init(
        swapchain_len,
        gm.baked.uniform_frag_vert_dyn,
        &.{.{ .binding = 0, .element_size = ubo_sz, .num = 16 }},
        null,
    );
    defer hl_dset.deinit(&dset_uniform);

    var storage = try hl_dset.init(
        swapchain_len,
        gm.baked.storage_frag_vert,
        &.{
            .{ .binding = 0, .element_size = storage_a_sz, .num = 1 },
            // .{ .binding = 1, .element_size = storage_b_sz, .num = 1 },
        },
        null,
    );
    defer hl_dset.deinit(&storage);

    const ATLAS_MAX = 256;
    var dset_atlas = try hl_dset.init(
        1,
        gm.baked.texture_frag,
        &.{.{ .binding = 0 }},
        ATLAS_MAX,
    );
    defer hl_dset.deinit(&dset_atlas);

    const desc_sets = [_]vk.DescriptorSetLayout{
        dset_uniform._d_set_layout.?,
        storage._d_set_layout.?,
        dset_atlas._d_set_layout.?,
    };

    // rendering & pipelines
    const render_pass = try pipe.createRenderPass(
        gc,
        swapchain.surface_format.format,
        swapchain.depth_image.vk_format,
    );
    defer gc.dev.destroyRenderPass(render_pass, null);

    const push_const_ranges = gm.PushConstant.Ranges();
    const pipeline_layout = try gc.dev.createPipelineLayout(&.{
        .flags = .{},
        .p_set_layouts = &desc_sets,
        .set_layout_count = desc_sets.len,
        .p_push_constant_ranges = push_const_ranges.ptr,
        .push_constant_range_count = @intCast(push_const_ranges.len),
    }, null);
    defer gc.dev.destroyPipelineLayout(pipeline_layout, null);

    const pipe_mod: pipe.Moduler = .{
        .gc = gc,
        .layout = pipeline_layout,
    };
    const pipeline = try pipe_mod.createPipeline(render_pass, .Triangle);
    defer pipe_mod.destroyPipelin(pipeline);
    const pipeline_2nd = try pipe_mod.createPipeline(render_pass, .Sprite);
    defer pipe_mod.destroyPipelin(pipeline_2nd);
    const pipeline_3rd = try pipe_mod.createPipeline(render_pass, .SpriteWDepth);
    defer pipe_mod.destroyPipelin(pipeline_3rd);

    var repo = try vertex.repoSpawn(gpa, &pic);
    defer repo.deinit(gc);
    std.debug.print("+++ total verts {d}\n", .{repo.total});

    const draw_instanced_attempt: gm.DrawInfo = .{
        .instance_count = grid.total, // TODO: something like "InstanceMapping"...
        .pipeline = [4]vk.Pipeline{ pipeline, pipeline_2nd, pipeline_3rd, undefined },
        .pipeline_layout = pipeline_layout,
        .uniform_dsets = dset_uniform.d_set_arr,
        .storage_dsets = storage.d_set_arr,
        .texture_dset = dset_atlas.d_set_arr.items[0],
        .models = &repo,
    };

    // fill storage and textures
    const spacing = 0.1;
    const size = 0.04;
    try refils.storagePrefil(storage, grid, spacing);

    const g64 = sht.GridSize.g64;

    var all_imgs: imgs.ManyImages = try .init(access.gpa);
    defer all_imgs.deinit();

    const basic_tex_set: [4]anyerror!imgs.RGBImage = .{
        imgs.vulkanTexture(&pic, g64, &imgs.demo_tex_rgb),
        imgs.vulkanTexture(&pic, g64, &imgs.demo_tex_r),
        imgs.vulkanTexture(&pic, looking_vol.grid, looking_vol.pix),
        imgs.vulkanTexture(&pic, looking_lyr.grid, looking_lyr.pix),
    };
    {
        const base_idx = 0;
        inline for (0.., basic_tex_set) |i, risky_rgba| {
            const rgba = try risky_rgba;
            try all_imgs.appen(&rgba);
            dset_atlas.updateTexture(0, &rgba, base_idx + i);
        }
    }

    var L: f32 = 0.0;
    const ok_attlas_base: u8 = 32;
    var ok_atlas_idx: u8 = ok_attlas_base;

    const L_delt: f32 = 1.0 / @as(f32, @floatFromInt(OK_SWEEP - 1));
    const ok_g = sht.GridSize.g128;
    for (0..OK_SWEEP) |i| {
        std.debug.assert(ok_atlas_idx < ATLAS_MAX);
        const pixels = switch (i) {
            0 => try oklab.sampleInfernoAlt(gpa, &ok_g),
            else => try oklab.OkUnderstanding.sampleSpace(gpa, L, &ok_g),
        };
        defer gpa.free(pixels);

        const rgba = try imgs.vulkanTexture(&pic, ok_g, pixels);
        dset_atlas.updateTexture(0, &rgba, ok_atlas_idx);
        try all_imgs.appen(&rgba);

        ok_atlas_idx += 1;
        L += L_delt;
    }

    const glyph_count: u8 = 24;
    var glyph_atlas_idx: u8 = 160;
    if (mbalphabet) |*abc| for (0..abc.num) |i| {
        const pixels = abc.char_texd_arr[i];
        const gly_sz = abc.char_sz_arr[i];
        if (!gly_sz.empty()) {
            const rgba = try imgs.vulkanTexture(&pic, gly_sz.gSize(), pixels);
            dset_atlas.updateTexture(0, &rgba, glyph_atlas_idx);
            try all_imgs.appen(&rgba);
        }
        glyph_atlas_idx += 1;
    };

    // For frame recording
    const inflight_slots = 8;
    std.debug.assert(swapchain_len < inflight_slots);
    var inflight_stack: [1024]u8 = undefined;
    var loc_stack: std.heap.FixedBufferAllocator = .init(inflight_stack[0..1024]);
    const cmdbufs: []vk.CommandBuffer = try loc_stack.allocator().alloc(vk.CommandBuffer, swapchain_len);
    const pools: []vk.CommandPool = try loc_stack.allocator().alloc(vk.CommandPool, swapchain_len);
    const recorders: []gm.FrameRecorder = try loc_stack.allocator().alloc(gm.FrameRecorder, swapchain_len);

    var framebuffers = try createFramebuffers(
        gc,
        gpa,
        render_pass,
        swapchain,
    );
    defer destroyFramebuffers(gc, gpa, framebuffers);

    var created: u8 = 0;
    const frame_pools_config: vk.CommandPoolCreateInfo = .{
        .queue_family_index = gc.graphics_queue.family,
        .flags = .{ .transient_bit = true },
    };
    for (0..swapchain_len) |_| {
        pools[created] = try gc.dev.createCommandPool(&frame_pools_config, null);
        created += 1;
    }
    defer for (0..created) |i| {
        gc.dev.destroyCommandPool(pools[i], null);
    };

    // Related to scene
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

    var dbgmonit = u.DbgMonitor{};

    { // Frame recording
        const frame_sz = try window.winExtent();
        for (0..swapchain_len) |i| {
            const uniform_mapping = dset_uniform.buff_arr.items[i].?.mapping.?;
            const uniforms: [*]sht.GroupData = @ptrCast(@alignCast(uniform_mapping));
            recorders[i] = gm.FrameRecorder{
                .id = @intCast(i),
                .gm = pic.gc,
                .pool = pools[i],
                .cmds = &cmdbufs[i],
            };
            try refils.unifomRefil(
                uniforms,
                0.0,
                pamperek.pos(),
                size,
                frame_sz,
            );
            try frame.recordFrame(
                &recorders[i],
                swapchain.extent,
                render_pass,
                framebuffers,
                &draw_instanced_attempt,
                &frame_state,
            );
        }
    }

    //state
    var okphi: f32 = 0;
    var glyphphi: f32 = 0;
    var scanphi: f32 = 0;
    var base_shading: bool = true;
    var ok_slider: u.Slider = .init(0, OK_SWEEP - 1);

    sdlh.wheel.up = .{ .a = &ok_slider, .f = u.Slider.inc };
    sdlh.wheel.down = .{ .a = &ok_slider, .f = u.Slider.dec };

    // main loop
    var text_stack: [1024]u8 = undefined;
    while (!window.shoudClose()) {
        var fba: std.heap.FixedBufferAllocator = .init(text_stack[0..]);
        const txta = fba.allocator();

        access.host.pollEvents();
        const win_size = try access.host.winExtent();
        if (!addons.visible(win_size)) {
            try access.io.sleep(.fromMilliseconds(50), .real);
            continue;
        }
        // navig.pos = input.
        navig.cursor = sdlh.peekPointer(win_size);
        navig.ok_tex_off = ok_attlas_base + ok_slider.curr;

        const coords: addons.Coords = .init(win_size);
        const on_area = coords.pointer(navig.cursor);
        navig.screan = coords.sz_scr;

        const img_idx = swapchain.image_index;

        input.glass_input.update();
        input.plr_input.update();

        perf_stats.messure(access.io);
        timeline.update(access.io);
        timeline1.update(access.io);

        if (input.exit_trig.fired()) window.closeWindow();
        if (input.time_stop_trig.fired()) timeline1.passageToggle();

        const td = timeline.deltaS();
        const td1 = timeline1.deltaS();
        okphi += td1 * 0.1;
        glyphphi += td1 * 0.13;

        pamperek.control(&input.plr_input, td);

        scanphi += td1 * 0.67;

        const tryg_val = m.trygZero1(@sin(scanphi));
        const scan_scale = ok_slider.frac() * 0.95 + 0.05;

        navig.inner_scale = @splat(scan_scale);
        navig.inner_offset = @splat((1 - tryg_val) * 0.3);

        const dbg_data = u.DbgMonitor.DbgVals{
            .phi = pamperek.p.phi,
            .inst_num = frame_state.layer_instance_num,
            .observer_pos = pamperek.pos(),
            .win_size = win_size,
        };

        try dbgmonit.update(access.io, &dbg_data);

        if (input.alt_projection_trigger.fired()) {
            frame_state.alt_proj = !frame_state.alt_proj;
        }

        if (input.slide_r_trig.fired()) {
            const last = frame_state.model_idx == repo.head - 1;
            frame_state.model_idx = if (last) 0 else frame_state.model_idx + 1;
        }

        if (input.slide_l_trig.fired()) {
            const first = frame_state.model_idx == 0;
            frame_state.model_idx = if (first) repo.head - 1 else frame_state.model_idx - 1;
        }

        if (input.dbg_trig.fired()) {
            dbgmonit.enabled = !dbgmonit.enabled;
        }

        //minimalized
        try swapchain.waitCurrentFrame();
        const storage_mapping = storage.buff_arr.items[img_idx].?.mapping.?;
        const uniform_mapping = dset_uniform.buff_arr.items[img_idx].?.mapping.?;
        const instances: [*]sht.PerInstance = @ptrCast(@alignCast(storage_mapping));
        const uniforms: [*]sht.GroupData = @ptrCast(@alignCast(uniform_mapping));

        {
            // cubes 0-4095
            // ok slices 4096-4223
            // glyphs 4224-4247
            // text 4608-?
            // layers 6144-?

            if (glass.update(&input.glass_input)) base_shading = false;
            if (input.shader_reset_trigger.fired()) base_shading = true;

            if (base_shading) {
                try glass.updateStorage(instances, false);
            } else {
                try glass.updateStorage(instances, true);
                const first = frame_state.layer_instance_offset;
                const lnum = try glass.updateLayerStorage( //
                    instances, first, false);
                frame_state.layer_instance_num = lnum;
            }

            try refils.unifomRefil(
                uniforms,
                timeline1.total_s,
                pamperek.pos(),
                size,
                win_size,
            );

            const first_ok_instance = g64.total;
            try oklab.OkUnderstanding.labSpliced(
                instances,
                first_ok_instance,
                OK_SWEEP,
                okphi,
            );

            const first_glyph_insatnce = first_ok_instance + OK_SWEEP;
            try fonts.lettersSpliced(
                instances,
                first_glyph_insatnce,
                glyph_count,
                glyphphi,
            );

            var dyn_text: std.ArrayList(u8) = try .initCapacity(txta, 960);
            try dyn_text.print(txta, "Some sample text to blit on a screan\n", .{});
            if (on_area[m.Z] == 1.0) {
                const x, const y, _ = on_area;
                const a, const b = oklab.OkUnderstanding.abVal(.{ x, y });
                try dyn_text.print(txta, "{s:<16} | x:{d:>6.2} y:{d:>6.2}\n", .{ "cursor at", x, y });
                try dyn_text.print(txta, "{s:<16} | a:{d:>6.2} b:{d:>6.2}\n", .{ "pointing to", a, b });
                if (input.sample_tirg.fired()) {
                    std.debug.print(".{{{d:.2},{d:.2},{d:.2}}}\n", .{ ok_slider.frac(), a, b });
                }
            } else {
                _ = input.sample_tirg.fired();
            }
            if (mbalphabet) |*alphabet| {
                frame_state.letters_inst_num = try alphabet.BlitText(
                    instances,
                    frame_state.letters_inst_offset,
                    dyn_text.items,
                );
            }
        }

        try frame.recordFrame(
            &recorders[img_idx],
            swapchain.extent,
            render_pass,
            framebuffers,
            &draw_instanced_attempt,
            &frame_state,
        );
        if (state == .suboptimal or addons.extentDiffer(resolution_extent, win_size)) {
            // std.debug.assert(false); //cuz it will throw error due to bad depth_img resolution
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
                    &frame_state,
                );
            }
        }

        const cmdbuf = cmdbufs[swapchain.image_index];
        state = swapchain.present(cmdbuf) catch |err| switch (err) {
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
