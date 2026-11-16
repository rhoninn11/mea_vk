const sht = @import("../shaders/types.zig");
const vk = @import("vulkan-zig");

pub fn SizeOfFormat(size: sht.GridSize, format: vk.Format) vk.ImageCreateInfo {
    return vk.ImageCreateInfo{
        .image_type = .@"2d",
        .format = format,
        .extent = .{ .height = size.h, .width = size.w, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1" = true },
        .tiling = .optimal,
        .usage = .{
            .sampled = true,
            .transfer_dst = true,
        },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    };
}
