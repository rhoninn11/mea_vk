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
    size: sht.GridSize,
    img: *meagen.Image,

    pub fn init(from: *meagen.Image, gsz: sht.GridSize) LookingGlass {
        std.debug.assert(from.info.?.img_type == meagen.ImgType.DUO);
        return LookingGlass{
            .pos = .{ 0, 0 },
            .size = gsz,
            .img = from,
        };
    }

    pub fn update(self: *LookingGlass, input: *const motion.HoldsAxis) bool {
        const src_size = self.img.info.?;

        const max_x = @as(i32, @intCast(src_size.width)) - @as(i32, @intCast(self.size.col_num)) - 1;
        const max_y = @as(i32, @intCast(src_size.height)) - @as(i32, @intCast(self.size.row_num)) - 1;

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
            return true;
        }
        return false;
    }

    pub fn pixval(self: *LookingGlass, i: usize) u16 {
        const x = @mod(i, @as(usize, @intCast(self.size.col_num)));
        const y = i / @as(usize, @intCast(self.size.col_num));
        std.debug.assert(y < self.size.row_num);

        const img_x = @as(usize, @intCast(self.pos[0])) + x;
        const img_y = @as(usize, @intCast(self.pos[1])) + y;

        const info = self.img.info.?;
        const idx = info.width * img_y + img_x;

        const Conversion = extern union {
            two: [2]u8,
            one: u16,
        };

        var elo: Conversion = undefined;
        elo.two[0] = self.img.pixels[idx * 2];
        elo.two[1] = self.img.pixels[idx * 2 + 1];

        return elo.one;
    }
    pub fn updateStorage(self: *LookingGlass, storage_dset: addon.DescriptorPrep, instance_num: u32) !void {
        const lim_num = 8096;
        std.debug.assert(instance_num <= lim_num);
        const stack_size = lim_num * @sizeOf(sht.PerInstance);
        var stack_mem: [stack_size]u8 = undefined;

        var provider: std.heap.FixedBufferAllocator = .init(&stack_mem);
        const local_a = provider.allocator();

        var scratchpad = try local_a.alloc(sht.PerInstance, instance_num);
        for (storage_dset.buff_arr.items) |possible_buffer| {
            const storage = possible_buffer.?;
            const mapping: [*]sht.PerInstance = @ptrCast(@alignCast(storage.mapping.?));
            @memcpy(scratchpad, mapping);
            for (0..instance_num) |i| {
                var prev_one: sht.PerInstance = scratchpad[i];
                const h = @as(f32, @floatFromInt(self.pixval(i)));
                const level = h / (256 * 256);
                prev_one.depth_ctrl[0] = 1;
                prev_one.depth_ctrl[1] = level * 4;

                scratchpad[i] = prev_one;
            }
            @memcpy(mapping, scratchpad);
        }
    }
};
