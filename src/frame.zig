const gftx = @import("graphics_context.zig");
const vk = @import("third_party/vk.zig");
const sht = @import("shaders/types.zig");
const vtx = @import("vertex.zig");
const m = @import("math.zig");

pub fn recordCommandBuffers(
    rec: *const gftx.FrameRecorder,
    buffer: vk.Buffer,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    framebuffers: []const vk.Framebuffer,
    ojejoje: []const vtx.Vertex,
    draw: *const gftx.DrawInfo,
    alt: bool,
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
            const offset = [_]vk.DeviceSize{0};
            gm.dev.cmdBindPipeline(cbufr, .graphics, draw.pipeline);
            gm.dev.cmdBindVertexBuffers(
                cbufr,
                0,
                1,
                @ptrCast(&buffer),
                &offset,
            );
            const all_sets: []const vk.DescriptorSet = &[_]vk.DescriptorSet{
                draw.uniform_dsets.items[rec.id],
                draw.storage_dsets.items[rec.id],
                draw.texture_dset,
            };

            const uniform_offset: u32 = if (alt) @sizeOf(sht.GroupData) else 0;
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
                @intCast(ojejoje.len),
                draw.instance_count,
                0,
                0,
            );
        }
        try gm.dev.endCommandBuffer(cbufr);
    }
}

// a tutaj odbywa się taka jakby prekompilacja renderingu ?...
fn prevImple(
    pic: *const gftx.PoolInCtx,
    rec: *const gftx.FrameRecorder,
    cmdbufs: []vk.CommandBuffer,
    buffer: vk.Buffer,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    framebuffers: []const vk.Framebuffer,
    ojejoje: []const vtx.Vertex,
    draw: *const gftx.DrawInfo,
    alt: bool,
    frame_: u8,
) !void {
    _ = frame_;
    _ = rec;
    const gc = pic.gc;
    try gc.dev.allocateCommandBuffers(&.{
        .command_pool = pic.pool,
        .level = .primary,
        .command_buffer_count = @intCast(cmdbufs.len),
    }, cmdbufs.ptr);

    const clear_arr: []const vk.ClearValue = &.{
        vk.ClearValue{
            .color = .{ .float_32 = .{ 0.05, 0, 0, 1 } },
        },
        vk.ClearValue{
            .depth_stencil = .{ .depth = 1.0, .stencil = 0 },
        },
    };

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

    for (cmdbufs, 0..) |cmdbuf, i| {
        try gc.dev.beginCommandBuffer(cmdbuf, &.{});

        gc.dev.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(&viewport));
        gc.dev.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(&scissor));

        // oscilationg ring
        gc.dev.cmdBeginRenderPass(cmdbuf, &.{
            .render_pass = render_pass,
            .framebuffer = framebuffers[i],
            .render_area = render_area,
            .clear_value_count = m.uinty(clear_arr.len),
            .p_clear_values = clear_arr.ptr,
        }, .@"inline");
        {
            defer gc.dev.cmdEndRenderPass(cmdbuf);
            const offset = [_]vk.DeviceSize{0};
            gc.dev.cmdBindPipeline(cmdbuf, .graphics, draw.pipeline);
            gc.dev.cmdBindVertexBuffers(
                cmdbuf,
                0,
                1,
                @ptrCast(&buffer),
                &offset,
            );
            const all_sets: []const vk.DescriptorSet = &[_]vk.DescriptorSet{
                draw.uniform_dsets.items[i],
                draw.storage_dsets.items[i],
                draw.texture_dset,
            };

            const uniform_offset: u32 = if (alt) @sizeOf(sht.GroupData) else 0;
            const dynamic_off: []const u32 = &.{uniform_offset};

            gc.dev.cmdBindDescriptorSets(
                cmdbuf,
                .graphics,
                draw.pipeline_layout,
                0,
                @intCast(all_sets.len),
                all_sets.ptr,
                @intCast(dynamic_off.len),
                dynamic_off.ptr,
            );
            gc.dev.cmdDraw(
                cmdbuf,
                @intCast(ojejoje.len),
                draw.instance_count,
                0,
                0,
            );
        }
        try gc.dev.endCommandBuffer(cmdbuf);
    }
}
