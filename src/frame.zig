const gm = @import("graphics_context.zig");
const vk = @import("vulkan-zig");
const sht = @import("shaders/types.zig");
const vtx = @import("vertex.zig");
const m = @import("math.zig");
const v = @import("vertex.zig");
const addons = @import("addons.zig");

pub const FrameState = struct {
    alt_proj: bool,
    model_idx: u8,
    ok_slices_num: u8,
    layer_instance_offset: u16,
    layer_instance_num: u16,
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
    command_bfr: vk.CommandBuffer,

    pub fn push(self: *const CmdHelper, layout: vk.PipelineLayout, push_blob: *const gm.PushConstant.PCBlob) void {
        self.gc.dev.cmdPushConstants(
            self.command_bfr,
            layout,
            .{ .fragment_bit = true, .vertex_bit = true },
            0,
            @sizeOf(@TypeOf(push_blob.*)),
            push_blob,
        );
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

    const UBODyn = Dynamic(sht.GroupData);
    const instace_sz = @sizeOf(sht.PerInstance);
    _ = instace_sz;
    {
        const cmd_helper = CmdHelper{
            .gc = gc,
            .command_bfr = cbufr,
        };
        try gc.dev.beginCommandBuffer(cbufr, &.{});

        gc.dev.cmdSetViewport(cbufr, 0, viewport);
        gc.dev.cmdSetScissor(cbufr, 0, scissor);

        // oscilationg ring
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

            const ubo_dynamic_offset: []const u32 = &.{
                if (state.alt_proj) UBODyn.offset(1) else UBODyn.offset(0),
            };
            const all_sets: []const vk.DescriptorSet = &[_]vk.DescriptorSet{
                draw.uniform_dsets.items[rec.id],
                draw.storage_dsets.items[rec.id],
                draw.texture_dset,
            };

            gc.dev.cmdBindPipeline(cbufr, .graphics, draw.pipeline[0]);
            gc.dev.cmdBindDescriptorSets(
                cbufr,
                .graphics,
                draw.pipeline_layout,
                0,
                all_sets,
                ubo_dynamic_offset,
            );
            const geopush = gm.PushConstant.PCBlob{
                .model = m.mat_translate(.{ 0, 0, 0 }).mat,
            };
            cmd_helper.push(draw.pipeline_layout, &geopush);
            gc.dev.cmdDraw(
                cbufr,
                models.sizes[state.model_idx],
                draw.instance_count,
                models.offsets[state.model_idx],
                0,
            );

            if (state.layer_instance_num > 0) {
                const cube_index = 1;
                const layerpush = gm.PushConstant.PCBlob{
                    .model = m.mat_translate(.{ 0, 1, 0 }).mat,
                    .inst_base = state.layer_instance_offset,
                };
                cmd_helper.push(draw.pipeline_layout, &layerpush);
                gc.dev.cmdDraw(
                    cbufr,
                    models.sizes[cube_index],
                    state.layer_instance_num,
                    models.offsets[cube_index],
                    0,
                );
            }

            if (state.alt_proj) {
                gc.dev.cmdBindPipeline(cbufr, .graphics, draw.pipeline[1]);
                gc.dev.cmdBindDescriptorSets(
                    cbufr,
                    .graphics,
                    draw.pipeline_layout,
                    0,
                    all_sets,
                    ubo_dynamic_offset,
                );
                const bilbo_idx = 4;
                const first_ok_instance = sht.GridSize.g64.total;
                const okpush = gm.PushConstant.PCBlob{
                    .model = m.mat_translate(.{ 0, 3, 0 }).mat,
                    .inst_base = first_ok_instance,
                    .tex_base = 32,
                };
                cmd_helper.push(draw.pipeline_layout, &okpush);
                gc.dev.cmdDraw(
                    cbufr,
                    models.sizes[bilbo_idx],
                    state.ok_slices_num,
                    models.offsets[bilbo_idx],
                    0,
                );
                const first_glyph_instance = first_ok_instance + state.ok_slices_num;
                const glyphpush = gm.PushConstant.PCBlob{
                    .model = m.mat_translate(.{ 0, 6, 0 }).mat,
                    .inst_base = first_glyph_instance,
                    .tex_base = 32 + state.ok_slices_num,
                };
                cmd_helper.push(draw.pipeline_layout, &glyphpush);
                gc.dev.cmdDraw(
                    cbufr,
                    models.sizes[bilbo_idx],
                    state.ok_slices_num,
                    models.offsets[bilbo_idx],
                    0,
                );
            }

            // TODO: render text here xD
            // but how?! meaby use https://github.com/Chlumsky/msdf-atlas-gen as offline step?
            // but i need to build that. Cmake project will be problematic
            // maybe https://github.com/nothings/stb/blob/master/stb_truetype.h as a lighter_alternative

        }
        try gc.dev.endCommandBuffer(cbufr);
    }
}
