const sht = @import("types.zig");
const std = @import("std");

pub fn gridI(grid: sht.GridSize, x: usize, y: usize) usize {
    const cols = @as(usize, @intCast(grid.w));
    const x_ = if (x >= cols) cols - 1 else x;

    const rows = @as(usize, @intCast(grid.h));
    const y_ = if (y >= rows) rows - 1 else y;

    return cols * y_ + x_;
}

pub fn xyGrid(x: u16, y: u16) sht.GridSize {
    return sht.GridSize{
        .total = @as(u32, x) * @as(u32, y),
        .w = x,
        .h = y,
    };
}

pub fn printGrid(g: *const sht.GridSize, prefix: []const u8) void {
    std.debug.print("{s} w({d}) h({d}) total({d})\n", .{ prefix, g.w, g.h, g.total });
}
