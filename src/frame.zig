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

    uv_mult: m.vec2,
    uv_offset: m.vec2,

    cursor_tex: u16,

    pub fn aspectScale(self: *const Navig) m.vec3 {
        const w, const h = self.scann_sz;
        const hscale = h / w;
        return .{ 1, hscale, 1 };
    }

    pub fn scanPlacement(self: *const Navig) m.mat4 {
        const x, const y, _ = self.aspectScale();
        _, const hs = self.screan;

        const mult = (hs / y);
        const scale: m.vec3 = .{ x * mult, y * mult, 1 };
        return m.matScale(scale).mat;
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

    pub fn drawInsances(self: *const CmdHelper, mdl_idx: u16, num: u32) void {
        self.gc.dev.cmdDraw(
            self.command,
            self.models.sizes[mdl_idx],
            num,
            self.models.offsets[mdl_idx],
            0,
        );
    }

    // TODO: use known PipeIndex
    pub fn use(self: *const CmdHelper, ptype: pipe.PipeType) void {
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
    rec: *const gm.FrameRecorder,
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
        const BILBORD_IDX = 4;
        const HEX_IDX = 5;
        const GUI_BILBO_IDX = 6;
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
                };

                hl_cmds.push(&geopush);
                hl_cmds.drawInsances(state.model_idx, draw.instance_count);
            } // scann slice

            if (state.layer_group.num > 0) {
                const cube_index = 1;
                const layerpush = gm.PushConstant.PCBlob{
                    .model = m.matTrans(.{ 0, 0, 0 }).mat,
                    .inst_base = state.layer_group.base,
                    .mode = 1,
                };
                hl_cmds.push(&layerpush);
                hl_cmds.drawInsances(cube_index, state.layer_group.num);
            } // layer markers

            // Ok shows with alt proj
            if (state.alt_proj) {
                // const inst_ok_begin = sht.GridSize.g64.total;
                const tex_ok_begin = 32;

                const okpush = gm.PushConstant.PCBlob{
                    .model = m.matTrans(.{ 0, -3, 0 }).mat,
                    .inst_base = state.ok_group.base,
                    .tex_base = tex_ok_begin,
                };
                hl_cmds.useDSprite();
                hl_cmds.push(&okpush);
                hl_cmds.drawInsances(BILBORD_IDX, state.ok_group.num);
            }

            hl_cmds.dynUboDsets(all_sets, 2); // GUI
            {
                const cursor = state.nav.cursor;
                const guipush = gm.PushConstant.PCBlob{
                    .model = m.matXmat(
                        m.matTrans(.{ cursor[m.X], cursor[m.Y], 0 }).mat,
                        m.matScale(.{ 25, 25, 1 }).mat,
                    ).mat,
                    .inst_base = 0,
                    .tex_base = state.nav.cursor_tex,
                    .mode = 3,
                };
                hl_cmds.useTriangles();
                hl_cmds.push(&guipush);
                hl_cmds.drawInsances(HEX_IDX, 1);
            } // <<< cursor >>>

            {
                hl_cmds.useSprite();
                const scann_mat = state.nav.scanPlacement();
                var scan_push = gm.PushConstant.PCBlob{
                    .model = scann_mat,
                    .tex_base = 2,
                    .mode = 2,
                    .scale2D = state.nav.uv_mult,
                    .point2D = state.nav.uv_offset,
                };
                hl_cmds.push(&scan_push);
                hl_cmds.drawInsances(GUI_BILBO_IDX, 1);

                var closer = m.matTrans(.{ 0, 0, -0.1 });
                scan_push.model = m.matXmat(closer.mat, scann_mat).mat;
                scan_push.tex_base = 3;
                hl_cmds.push(&scan_push);
                hl_cmds.drawInsances(GUI_BILBO_IDX, 1);

                closer = m.matTrans(.{ 0, 0, -0.05 });
                const delta_store = m.matXmat(closer.mat, scann_mat).mat;
                // delta_store[0][3] = 0.5;
                var scan_push_sdf = gm.PushConstant.PCBlob{
                    .model = delta_store,
                    .tex_base = 5,
                    .mode = 4,
                    .scale2D = state.nav.uv_mult,
                    .point2D = state.nav.uv_offset,
                };
                hl_cmds.push(&scan_push_sdf);
                hl_cmds.drawInsances(GUI_BILBO_IDX, 1);
            } // <<< scann_layers >>>

            {
                hl_cmds.useSdf();
                const letter_push = gm.PushConstant.PCBlob{
                    .model = m.matTrans(.{ 0, -32, 0 }).mat,
                    .inst_base = state.char_group.base,
                    .tex_base = 4,
                    .mode = 1,
                };
                hl_cmds.push(&letter_push);
                hl_cmds.drawInsances(GUI_BILBO_IDX, state.char_group.num);
            }
            // <<< font_rending >>>
        }
        try gc.dev.endCommandBuffer(cbufr);
    }
}
