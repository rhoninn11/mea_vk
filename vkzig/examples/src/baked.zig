const vk = @import("third_party/vk.zig");

// ----------

const pixel_size = 4;
const field_x_side = 16;
const field_y_side = 4;

pub const img_side = 64;
pub const rgb_tex = blk: {
    const spot_num = img_side * img_side;
    var lut: [spot_num * pixel_size]u8 = undefined;
    const colors: []const [pixel_size]u8 = &.{
        .{ 255, 255, 255, 255 },
        .{ 128, 128, 128, 255 },
    };
    @setEvalBranchQuota(spot_num);
    for (0..spot_num) |i| {
        const at = i * pixel_size;
        const row = i / img_side;
        const a = if (@mod(row, field_x_side * 2) < field_x_side) 0 else 1;
        const b = 1 - a;

        var pixel: [pixel_size]u8 = colors[a];
        if (@mod(i, field_y_side * 2) < field_y_side) {
            pixel = colors[b];
        }

        @memcpy(lut[at .. at + 4], &pixel);
    }
    break :blk lut;
};
