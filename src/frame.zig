const std = @import("std");
const gm = @import("graphics_context.zig");
const vk = @import("vulkan-zig");
const sht = @import("shaders/types.zig");
const vtx = @import("vertex.zig");
const m = @import("math.zig");
const v = @import("vertex.zig");
const addons = @import("addons.zig");

pub const Navig = struct {
    g: sht.GridSize,
    cursor: m.vec2,
    scale: m.vec2,
    tex: u16,

    pub fn aspectScale(self: *const Navig) m.vec3 {
        const hscale = m.floaty(self.g.h) / m.floaty(self.g.w);
        return .{ 1, hscale, 1 };
    }
};

pub const FrameState = struct {
    pub const scan_preview = 6140;
    pub const scan_layer_preview = 6142;
    alt_proj: bool,
    model_idx: u8,
    ok_slices_num: u8,
    layer_instance_offset: u16,
    layer_instance_num: u16,
    letters_inst_offset: u16,
    letters_inst_num: u16,
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

    pub fn useTriangles(self: *const CmdHelper) void {
        self.gc.dev.cmdBindPipeline(self.command, .graphics, self.draw.pipeline[0]);
    }
    pub fn useSprite(self: *const CmdHelper) void {
        self.gc.dev.cmdBindPipeline(self.command, .graphics, self.draw.pipeline[1]);
    }
};

pub fn recordFrame(
    rec: *const gm.FrameRecorder,
    models: *const v.VertRepo,
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
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
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
        .models = models,
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
                &.{models.vbo.?.dvk_bfr},
                &.{0},
            );

            const ubo_slot: u8 = if (state.alt_proj) 1 else 0;
            const geopush = gm.PushConstant.PCBlob{
                .model = m.matTrans(.{ 0, 0, 0 }).mat,
            };

            //triangle
            hl_cmds.useTriangles();
            hl_cmds.dynUboDsets(all_sets, ubo_slot);
            hl_cmds.push(&geopush);
            hl_cmds.drawInsances(state.model_idx, draw.instance_count);

            if (state.layer_instance_num > 0) {
                const cube_index = 1;
                const layerpush = gm.PushConstant.PCBlob{
                    .model = m.matTrans(.{ 0, 0, 0 }).mat,
                    .inst_base = state.layer_instance_offset,
                    .mode = 1,
                };
                hl_cmds.push(&layerpush);
                hl_cmds.drawInsances(cube_index, state.layer_instance_num);
            }

            if (state.alt_proj) {
                const inst_ok_begin = sht.GridSize.g64.total;
                const inst_glyph_begin = sht.GridSize.g64.total + state.ok_slices_num;
                const tex_ok_begin = 32;
                const tex_glyph_begin = 32 + state.ok_slices_num;

                const okpush = gm.PushConstant.PCBlob{
                    .model = m.matTrans(.{ 0, 3, 0 }).mat,
                    .inst_base = inst_ok_begin,
                    .tex_base = tex_ok_begin,
                };
                hl_cmds.useSprite();
                hl_cmds.push(&okpush);
                hl_cmds.drawInsances(BILBORD_IDX, state.ok_slices_num);
                const glyphpush = gm.PushConstant.PCBlob{
                    .model = m.matTrans(.{ 0, 6, 0 }).mat,
                    .inst_base = inst_glyph_begin,
                    .tex_base = tex_glyph_begin,
                };
                hl_cmds.push(&glyphpush);
                hl_cmds.drawInsances(BILBORD_IDX, state.ok_slices_num);
            }

            //gui - maybe would be nice to clear depth first

            hl_cmds.dynUboDsets(all_sets, 2);
            // >>> cursor <<<
            const cursor = state.nav.cursor;
            const guipush = gm.PushConstant.PCBlob{
                .model = m.matTrans(.{ cursor[m.X], cursor[m.Y], 0 }).mat,
                .inst_base = 0,
                .tex_base = state.nav.tex,
                .mode = 3,
            };
            hl_cmds.useTriangles();
            hl_cmds.push(&guipush);
            hl_cmds.drawInsances(HEX_IDX, 1);
            // <<< cursor >>>
            const okpush = gm.PushConstant.PCBlob{
                .model = m.matXmat(
                    m.matTrans(.{ 12, -6, 0 }).mat,
                    m.matScale(.{ 9, 9, 1 }).mat,
                ).mat,
                .inst_base = 0,
                .tex_base = state.nav.tex,
                .mode = 2,
            };
            hl_cmds.useSprite();
            hl_cmds.push(&okpush);
            hl_cmds.drawInsances(HEX_IDX, 1);

            // >>> scann_layers <<<
            const scan_m_model = blk: {
                const aspect = m.matScale(state.nav.aspectScale());
                const display_here = m.matTrans(.{ 0, -6, 0 });

                break :blk m.matXmat(display_here.mat, aspect.mat);
            };

            var scan_push = gm.PushConstant.PCBlob{
                .model = scan_m_model.mat,
                .inst_base = state.letters_inst_offset,
                .tex_base = 2,
                .mode = 2,
                .scale2D = .{ state.nav.scale[m.U], 1 },
            };
            hl_cmds.useSprite();
            hl_cmds.push(&scan_push);
            hl_cmds.drawInsances(BILBORD_IDX, 1);

            const closer = m.matTrans(.{ 0, 0, -0.1 });
            scan_push.model = m.matXmat(closer.mat, scan_m_model.mat).mat;
            scan_push.tex_base = 3;
            hl_cmds.push(&scan_push);
            hl_cmds.drawInsances(BILBORD_IDX, 1);
            // <<< scann_layers >>>

            // >>> font_rending <<<
            const letter_push = gm.PushConstant.PCBlob{
                .model = m.matTrans(.{ 0, 0, 0 }).mat,
                .inst_base = state.letters_inst_offset,
                .tex_base = 160,
                .mode = 1,
            };
            hl_cmds.useSprite();
            hl_cmds.push(&letter_push);
            hl_cmds.drawInsances(BILBORD_IDX, state.letters_inst_num);
            // <<< font_rending >>>
        }
        try gc.dev.endCommandBuffer(cbufr);
    }
}
