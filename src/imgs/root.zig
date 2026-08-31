const root = @import("imgs.zig");

const m_img_side = 64;

pub const demo_tex_size = (m_img_side * m_img_side) * pixel_size;
pub const demo_tex_rgb = blk: {
    const spot_num = m_img_side * m_img_side;
    var lut: [spot_num * pixel_size]u8 = undefined;
    const colors: []const [pixel_size]u8 = &.{
        .{ 255, 255, 255, 255 },
        .{ 128, 128, 128, 255 },
    };
    @setEvalBranchQuota(spot_num);
    for (0..spot_num) |i| {
        const at = i * pixel_size;
        const row = i / m_img_side;
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

pub const demo_tex_r = blk: {
    const spot_num = m_img_side * m_img_side;
    var lut: [spot_num * pixel_size]u8 = undefined;
    const uniform_color: [pixel_size]u8 = .{ 255, 0, 0, 255 };

    @setEvalBranchQuota(spot_num);
    for (0..spot_num) |i| {
        const at = i * pixel_size;
        @memcpy(lut[at .. at + 4], &uniform_color);
    }
    break :blk lut;
};

pub const pixel_size = 4;
pub const field_x_side = 16;
pub const field_y_side = 4;
