const sht = @import("types.zig");

pub fn gridI(grid: sht.GridSize, x: usize, y: usize) usize {
    const cols = @as(usize, @intCast(grid.col_num));
    const x_ = if (x >= cols) cols - 1 else x;

    const rows = @as(usize, @intCast(grid.row_num));
    const y_ = if (y >= rows) rows - 1 else y;

    return cols * y_ + x_;
}
