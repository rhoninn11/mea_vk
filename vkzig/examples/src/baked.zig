const vk = @import("third_party/vk.zig");

// ----------

const pixel_size = 4;
const img_side = 64;
const field_side = 4;

pub const rgb_tex = blk: {
    const spot_num = img_side * img_side;
    var lut: [spot_num * pixel_size]u8 = undefined;
    const pixel_a: [pixel_size]u8 = .{ 255, 0, 0, 255 };
    const pixel_b: [pixel_size]u8 = .{ 0, 255, 0, 255 };
    @setEvalBranchQuota(spot_num);
    for (0..spot_num) |i| {
        const at = i * pixel_size;
        var pixel: [pixel_size]u8 = pixel_b;
        if (@mod(i, field_side * 2) < field_side) {
            pixel = pixel_a;
        }

        @memcpy(lut[at .. at + 4], &pixel);
    }
    break :blk lut;
};
