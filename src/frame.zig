const gftx = @import("graphics_context.zig");
const vk = @import("third_party/vk.zig");
const sht = @import("shaders/types.zig");
const vtx = @import("vertex.zig");
const m = @import("math.zig");
const v = @import("vertex.zig");

pub const FrameState = struct {
    alt_proj: bool,
    model_idx: u8,
};

pub fn recordCommandBuffers(
    rec: *const gftx.FrameRecorder,
    models: *const v.VertIndex,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    framebuffers: []const vk.Framebuffer,
    draw: *const gftx.DrawInfo,
    state: *const FrameState,
) !void {
    const gm = rec.gm;
    const m_clears: []const vk.ClearValue = &.{
        vk.ClearValue{
            .color = .{ .float_32 = .{ 0.05, 0, 0, 1 } },
        },
        vk.ClearValue{
            .depth_stencil = .{ .depth = 1.0, .stencil = 0 },
        },
    };

    try rec.clear(gm);
    try rec.begin(gm);
    const cbufr: vk.CommandBuffer = rec.cmds.*;

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };
    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };
    const render_area = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    {
        try gm.dev.beginCommandBuffer(cbufr, &.{});

        gm.dev.cmdSetViewport(cbufr, 0, 1, @ptrCast(&viewport));
        gm.dev.cmdSetScissor(cbufr, 0, 1, @ptrCast(&scissor));

        // oscilationg ring
        gm.dev.cmdBeginRenderPass(cbufr, &.{
            .render_pass = render_pass,
            .framebuffer = framebuffers[rec.id],
            .render_area = render_area,
            .clear_value_count = m.uinty(m_clears.len),
            .p_clear_values = m_clears.ptr,
        }, .@"inline");
        {
            defer gm.dev.cmdEndRenderPass(cbufr);
            const vert_offset = models.offsets[state.model_idx];
            const offset = [_]vk.DeviceSize{vert_offset * @sizeOf(v.Vertex)};
            gm.dev.cmdBindPipeline(cbufr, .graphics, draw.pipeline[1]);
            gm.dev.cmdBindVertexBuffers(
                cbufr,
                0,
                1,
                @ptrCast(&models.vkBuffer),
                &offset,
            );
            const all_sets: []const vk.DescriptorSet = &[_]vk.DescriptorSet{
                draw.uniform_dsets.items[rec.id],
                draw.storage_dsets.items[rec.id],
                draw.texture_dset,
            };

            const uniform_offset: u32 = if (state.alt_proj) @sizeOf(sht.GroupData) else 0;
            const dynamic_off: []const u32 = &.{uniform_offset};

            gm.dev.cmdBindDescriptorSets(
                cbufr,
                .graphics,
                draw.pipeline_layout,
                0,
                @intCast(all_sets.len),
                all_sets.ptr,
                @intCast(dynamic_off.len),
                dynamic_off.ptr,
            );
            gm.dev.cmdDraw(
                cbufr,
                models.sizes[state.model_idx],
                draw.instance_count,
                0,
                0,
            );
        }
        try gm.dev.endCommandBuffer(cbufr);
    }
}
