const std = @import("std");
const utils = @import("utils.zig");
const meagen = @import("gen/meagen.pb.zig");
const addon = @import("addons.zig");
const motion = @import("motion.zig");
const sht = @import("shaders/types.zig");
const shu = @import("shaders/utils.zig");

const Errorset = error{
    constrained,
};

pub fn spawnMonoImg(alloc: std.mem.Allocator, grid_ext: sht.GridSize) !meagen.Image {
    const grid: sht.GridSize = .default;

    if (!std.meta.eql(grid_ext, grid)) {
        return Errorset.constrained;
    }

    const info: meagen.ImgInfo = .{
        .width = grid.col_num,
        .height = grid.row_num,
        .img_type = meagen.ImgType.MONO,
    };
    var pixels = try alloc.alloc(u8, grid.total);
    var pixels16u = try alloc.alloc(u16, grid.total);
    defer alloc.free(pixels16u);

    var rng = try utils.DefaultRng();
    for (0..info.height) |y| {
        for (0..info.width) |x| {
            const gdx = shu.gridI(grid, x, y);
            if (x > 16) {
                pixels[gdx] = @intCast(x * 8);
                var base: u16 = @intCast(x * 24);
                base += @as(u16, @intCast(rng.int(u8)));
                pixels16u[gdx] = base;
            } else {
                pixels[gdx] = 0;
            }
        }
    }

    std.debug.print("+++ proto image sample generated {d}x{d}\n", .{ grid.col_num, grid.row_num });
    return meagen.Image{
        .info = info,
        .pixels = pixels,
    };
}

pub fn serdesLoad(alloc: std.mem.Allocator) !meagen.Image {
    const filename = "fs/serdes/proto_53.serdes";
    const file = std.fs.cwd().openFile(filename, .{ .mode = .read_only }) catch {
        std.debug.print("!+- theres no file named {s}\n", .{filename});
        return spawnMonoImg(alloc, sht.GridSize.default);
    };
    defer file.close();

    var file_buffer: [8096]u8 = undefined;
    var rader = file.reader(&file_buffer);

    return meagen.Image.decode(&rader.interface, alloc);
}

pub const LookingGlass = struct {
    pos: @Vector(2, i32),
    size: @Vector(2, i32),
    data: *meagen.Image,

    pub fn init(from: *meagen.Image, gsz: sht.GridSize) LookingGlass {
        return LookingGlass{
            .pos = .{ 0, 0 },
            .size = .{ @intCast(gsz.col_num), @intCast(gsz.row_num) },
            .data = from,
        };
    }

    pub fn update(self: *LookingGlass, input: *const motion.HoldsAxis) void {
        const src_size = self.data.info.?;

        const max_x = @as(i32, @intCast(src_size.width)) - self.size[0] - 1;
        const max_y = @as(i32, @intCast(src_size.height)) - self.size[1] - 1;

        const x_axis = input.axes[0];
        self.pos[0] = switch (x_axis) {
            motion.Axis.positive => if (self.pos[0] < max_x) self.pos[0] + 1 else max_x,
            motion.Axis.negative => if (self.pos[0] > 0) self.pos[0] - 1 else 0,
            else => self.pos[0],
        };

        const y_axis = input.axes[1];
        self.pos[1] = switch (y_axis) {
            motion.Axis.positive => if (self.pos[1] < max_y) self.pos[1] + 1 else max_y,
            motion.Axis.negative => if (self.pos[1] > 0) self.pos[1] - 1 else 0,
            else => self.pos[1],
        };

        if (x_axis != motion.Axis.none or y_axis != motion.Axis.none) {
            std.debug.print("new position at x:{} y:{}\n", .{ self.pos[0], self.pos[1] });
        }
    }
};
