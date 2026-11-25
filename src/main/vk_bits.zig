const std = @import("std");
pub const vk = @import("../main.zig").vk_portal;

const swch = @import("../swapchain.zig");
const gm = @import("../graphics_context.zig");

pub fn mainCommandQueue(gc: *const gm.GraphicsContext) !vk.CommandPool {
    const pool_cinfo: vk.CommandPoolCreateInfo = .{
        .queue_family_index = gc.graphics_queue.family,
        .flags = .{
            .reset_command_buffer = true,
            // .transient_bit = true,
        },
    };
    return gc.dev_api.createCommandPool(&pool_cinfo, null);
}

pub fn createFramebuffers(
    gc: *const gm.GraphicsContext,
    allocator: std.mem.Allocator,
    render_pass: vk.RenderPass,
    swapchain: swch.Swapchain,
) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swap_images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |fb| gc.dev_api.destroyFramebuffer(fb, null);

    for (framebuffers) |*fb| {
        const att_arr: []const vk.ImageView = &.{
            swapchain.swap_images[i].view,
            swapchain.depth_images[i].dvk_img_view,
        };

        fb.* = try gc.dev_api.createFramebuffer(&.{
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

pub fn destroyFramebuffers(
    gc: *const gm.GraphicsContext,
    allocator: std.mem.Allocator,
    framebuffers: []const vk.Framebuffer,
) void {
    for (framebuffers) |fb| gc.dev_api.destroyFramebuffer(fb, null);
    allocator.free(framebuffers);
}
