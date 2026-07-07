const std = @import("std");
const gm = @import("graphics_context.zig");
const vk = @import("vulkan-zig");
const sht = @import("shaders/types.zig");
const vtx = @import("vertex.zig");
const m = @import("math.zig");
const v = @import("vertex.zig");
const addons = @import("addons.zig");
const pipe = @import("pipe.zig");

pub const Navig = struct {
    screan: m.vec2,
    cursor: m.vec2,

    scann_sz: m.vec2,
    scann_aspect: m.vec2 = undefined,

    uv_mult: m.vec2,
    uv_offset: m.vec2,

    cursor_tex: u16,
    pub fn aspectScale(self: *const Navig) m.vec2 {
        const w, const h = self.scann_sz;
        const hscale = h / w;
        return .{ 1, hscale };
    }

    pub fn aspectScale3(self: *const Navig) m.vec3 {
        const w, const h = self.aspectScale();
        return .{ w, h, 1 };
    }

    pub fn scanPlacement(self: *const Navig) m.mat4 {
        const x, const y, _ = self.aspectScale3();
        _, const hs = self.screan;

        const base = (hs / y);
        const mult = base * 0.90;
        const padding = base * 0.05;
        const s: m.vec3 = .{ x * mult, y * mult, 1 };

        const saled = m.matScale(s);
        const side: f32 = @max(x, y);
        const moved = m.matTrans(.{ side * padding, -y * padding, 0 });
        const combinde = m.matXmat(moved.mat, saled.mat).mat;

        return combinde;
    }
};

pub const InstGroup = struct {
    base: u16,
    num: u16,
};

pub const FrameState = struct {
    alt_proj: bool,
    alt_shader: bool,
    model_idx: u8,
    ok_tex_base: u16,
    ok_group: InstGroup,
    char_group: InstGroup,
    layer_group: InstGroup,
    nav: *const Navig,
};

fn Dynamic(t: type) type {
    const stride = @sizeOf(t);
    return struct {
        pub fn offset(slot: u32) u32 {
            return slot * stride;
        }
    };
}

const CmdHelper = struct {
    gc: *const gm.GraphicsContext,
    draw: *const gm.DrawInfo,
    command: vk.CommandBuffer,
    models: *const v.VertRepo,

    pub fn push(self: *const CmdHelper, push_blob: *const gm.PushConstant.PCBlob) void {
        self.gc.dev.cmdPushConstants(
            self.command,
            self.draw.pipeline_layout,
            .{ .fragment_bit = true, .vertex_bit = true },
            0,
            @sizeOf(@TypeOf(push_blob.*)),
            push_blob,
        );
    }
    pub fn dynUboDsets(self: *const CmdHelper, sets: []const vk.DescriptorSet, ubo_slot: u8) void {
        const UBODyn = Dynamic(sht.GroupData);
        const ubo_dynamic_offset: []const u32 = &.{UBODyn.offset(ubo_slot)};
        self.gc.dev.cmdBindDescriptorSets(
            self.command,
            .graphics,
            self.draw.pipeline_layout,
            0,
            sets,
            ubo_dynamic_offset,
        );
    }

    pub fn drawInsances(self: *const CmdHelper, mdl_idx: v.EMesh, num: u32) void {
        const idx: u8 = @intFromEnum(mdl_idx);
        self.gc.dev.cmdDraw(
            self.command,
            self.models.sizes[idx],
            num,
            self.models.offsets[idx],
            0,
        );
    }

    // TODO: use known PipeIndex
    pub fn use(self: *const CmdHelper, ptype: pipe.EBrush) void {
        _ = self;
        _ = ptype;
    }

    pub fn useTriangles(self: *const CmdHelper) void {
        self.gc.dev.cmdBindPipeline(self.command, .graphics, self.draw.pipeline[0]);
    }
    pub fn useSprite(self: *const CmdHelper) void {
        self.gc.dev.cmdBindPipeline(self.command, .graphics, self.draw.pipeline[1]);
    }
    pub fn useDSprite(self: *const CmdHelper) void {
        self.gc.dev.cmdBindPipeline(self.command, .graphics, self.draw.pipeline[2]);
    }
    pub fn useSdf(self: *const CmdHelper) void {
        self.gc.dev.cmdBindPipeline(self.command, .graphics, self.draw.pipeline[3]);
    }
};

pub fn recordFrame(
    rec: *gm.FrameRecorder,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    framebuffers: []const vk.Framebuffer,
    draw: *const gm.DrawInfo,
    state: *const FrameState,
) !void {
    const gc = rec.gm;
    const m_clears: []const vk.ClearValue = &.{
        vk.ClearValue{
            .color = .{ .float_32 = .{ 0.05, 0, 0, 1 } },
        },
        vk.ClearValue{
            .depth_stencil = .{ .depth = 1.0, .stencil = 0 },
        },
    };

    try rec.clear(gc);
    try rec.begin(gc);
    const cbufr: vk.CommandBuffer = rec.cmds.*;

    const viewport = &.{vk.Viewport{
        .x = 0,
        .y = 0,
        .width = m.floaty(extent.width),
        .height = m.floaty(extent.height),
        .min_depth = 0,
        .max_depth = 1,
    }};
    const scissor = &.{vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    }};
    const render_area = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };
    const hl_cmds = CmdHelper{
        .gc = gc,
        .draw = draw,
        .command = cbufr,
        .models = draw.models,
    };
    const all_sets: []const vk.DescriptorSet = &[_]vk.DescriptorSet{
        draw.uniform_dsets.items[rec.id],
        draw.storage_dsets.items[rec.id],
        draw.texture_dset,
    };

    // const instace_sz = @sizeOf(sht.PerInstance);
    // _ = instace_sz;
    {
        try gc.dev.beginCommandBuffer(cbufr, &.{});

        gc.dev.cmdSetViewport(cbufr, 0, viewport);
        gc.dev.cmdSetScissor(cbufr, 0, scissor);

        gc.dev.cmdBeginRenderPass(cbufr, &.{
            .render_pass = render_pass,
            .framebuffer = framebuffers[rec.id],
            .render_area = render_area,
            .clear_value_count = m.uinty(m_clears.len),
            .p_clear_values = m_clears.ptr,
        }, .@"inline");
        {
            defer gc.dev.cmdEndRenderPass(cbufr);
            gc.dev.cmdBindVertexBuffers(
                cbufr,
                0,
                &.{draw.models.vbo.?.dvk_bfr},
                &.{0},
            );

            const ubo_slot: u8 = if (state.alt_proj) 1 else 0;
            hl_cmds.dynUboDsets(all_sets, ubo_slot);
            hl_cmds.useTriangles();
            {
                const geopush = gm.PushConstant.PCBlob{
                    .model = m.matTrans(.{ 0, 0, 0 }).mat,
                    // triangle mode ???
                };

                hl_cmds.push(&geopush);
                const selectable: v.EMesh = std.enums.fromInt(v.EMesh, state.model_idx) orelse v.EMesh.cube;
                hl_cmds.drawInsances(selectable, draw.instance_count); // grid

                if (state.layer_group.num > 0) {
                    const layerpush = gm.PushConstant.PCBlob{
                        .model = m.matTrans(.{ 0, 0, 0 }).mat,
                        .inst_base = state.layer_group.base,
                        .mode = 1, // triangle mode
                    };
                    hl_cmds.push(&layerpush);
                    hl_cmds.drawInsances(.cube, state.layer_group.num); // layers
                }
            }

            if (state.alt_proj) {
                hl_cmds.useDSprite();

                const okpush = gm.PushConstant.PCBlob{
                    .model = m.matTrans(.{ 0, -3, 0 }).mat,
                    .inst_base = state.ok_group.base,
                    .tex_base = state.ok_tex_base,
                    // triangle mode ???
                };
                hl_cmds.push(&okpush);
                hl_cmds.drawInsances(.hexy, state.ok_group.num); // ok slices
            }

            hl_cmds.dynUboDsets(all_sets, 2); // GUI
            {
                hl_cmds.useTriangles();
                const cursor = state.nav.cursor;
                const guipush = gm.PushConstant.PCBlob{
                    .model = m.matXmat(
                        m.matTrans(.{ cursor[m.X], cursor[m.Y], 0 }).mat,
                        m.matScale(.{ 25, 25, 1 }).mat,
                    ).mat,
                    .inst_base = 0,
                    .tex_base = state.nav.cursor_tex,
                    .mode = 3, //triangle mode
                };
                hl_cmds.push(&guipush);
                hl_cmds.drawInsances(.hexy, 1); // cursor
            }

            {
                hl_cmds.useSprite();
                const scann_mat = state.nav.scanPlacement();
                var scan_push = gm.PushConstant.PCBlob{
                    .model = scann_mat,
                    .tex_base = 2,
                    .mode = 2, //sprite mode
                    .scale2D = state.nav.uv_mult,
                    .point2D = state.nav.uv_offset,
                };
                hl_cmds.push(&scan_push);
                hl_cmds.drawInsances(.quad, 1); // scann color map

                var closer = m.matTrans(.{ 0, 0, -0.1 });
                scan_push.model = m.matXmat(closer.mat, scann_mat).mat;
                scan_push.tex_base = 3;
                hl_cmds.push(&scan_push);
                hl_cmds.drawInsances(.quad, 1); // scann layers

                closer = m.matTrans(.{ 0, 0, -0.05 });
                const delta_store = m.matXmat(closer.mat, scann_mat).mat;
                // delta_store[0][3] = 0.5;
                var scan_push_sdf = gm.PushConstant.PCBlob{
                    .model = delta_store,
                    .tex_base = 5,
                    .mode = 4, // sprite mode
                    .scale2D = state.nav.uv_mult,
                    .point2D = state.nav.uv_offset,
                };
                hl_cmds.push(&scan_push_sdf);
                hl_cmds.drawInsances(.quad, 1); // scann shaded
            }

            {
                hl_cmds.useSdf();
                const letter_push = gm.PushConstant.PCBlob{
                    .model = m.matTrans(.{ 0, -32, 0 }).mat,
                    .inst_base = state.char_group.base,
                    .tex_base = 4,
                    .mode = 1, //sdf mode
                };
                hl_cmds.push(&letter_push);
                hl_cmds.drawInsances(.quad, state.char_group.num); // text
            }
        }
        try gc.dev.endCommandBuffer(cbufr);
    }
}
