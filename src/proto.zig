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

inline fn info(g: sht.GridSize, t: meagen.ImgType) meagen.ImgInfo {
    return meagen.ImgInfo{
        .width = g.w,
        .height = g.h,
        .img_type = t,
    };
}

pub fn spawnMonoImg(alloc: std.mem.Allocator, g: sht.GridSize) !meagen.Image {
    var rng = try utils.DefaultRng();
    var pixels = try alloc.alloc(u8, g.total);

    for (0..g.h) |y| {
        for (0..g.w) |xx| {
            const gdx = shu.gridI(g, xx, y);
            const randval = rng.int(u8);
            pixels[gdx] = randval;
        }
    }

    return meagen.Image{
        .info = info(g, meagen.ImgType.MONO),
        .pixels = pixels,
    };
}

const uHdr = extern union {
    byte: [2]u8,
    hdr: u16,
};

pub fn spawHdr(alloc: std.mem.Allocator, g: sht.GridSize) !meagen.Image {
    var pixels = try alloc.alloc(u8, g.total * @sizeOf(u16));
    for (0..g.h) |y| {
        const phaseval_y = @as(f32, @floatFromInt(y)) / (std.math.tau * 1);
        const sinval_y = @sin(phaseval_y);
        const fitting_y = ((sinval_y + 1) * 0.5 * ((1 << 16) - 3) + 1);

        for (0..g.w) |xx| {
            const phaseval_x = @as(f32, @floatFromInt(xx)) / (std.math.tau * 1);
            const sinval_x = @sin(phaseval_x);
            const fitting_x = ((sinval_x + 1) * 0.5 * ((1 << 16) - 3) + 1);
            const combined = fitting_x * 0.5 + fitting_y * 0.5;

            const gdx = shu.gridI(g, xx, y);
            const hdrval: uHdr = .{ .hdr = @as(u16, @intFromFloat(combined)) };
            pixels[gdx * 2] = hdrval.byte[0];
            pixels[gdx * 2 + 1] = hdrval.byte[1];
        }
    }

    return meagen.Image{
        .info = info(g, meagen.ImgType.DUO),
        .pixels = pixels,
    };
}

pub fn serdesLoad(alloc: std.mem.Allocator) !meagen.Image {
    const filename = "fs/serdes/proto_0.serdes";
    const file = std.fs.cwd().openFile(filename, .{
        .mode = .read_only,
    }) catch {
        std.debug.print("!+- theres no file named {s}\n", .{filename});
        return try spawHdr(alloc, shu.xyGrid(256, 880));
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

        const max_x = @as(i32, @intCast(src_size.width)) - @as(i32, @intCast(self.size.w)) - 1;
        const max_y = @as(i32, @intCast(src_size.height)) - @as(i32, @intCast(self.size.h)) - 1;

        const x_axis = input.axes[1];
        self.pos[0] = switch (x_axis) {
            motion.Axis.positive => if (self.pos[0] < max_x) self.pos[0] + 1 else max_x,
            motion.Axis.negative => if (self.pos[0] > 0) self.pos[0] - 1 else 0,
            else => self.pos[0],
        };

        const y_axis = input.axes[0];
        self.pos[1] = switch (y_axis) {
            motion.Axis.positive => if (self.pos[1] < max_y) self.pos[1] + 1 else max_y,
            motion.Axis.negative => if (self.pos[1] > 0) self.pos[1] - 1 else 0,
            else => self.pos[1],
        };

        if (x_axis != motion.Axis.none or y_axis != motion.Axis.none) {
            // std.debug.print("new position at x:{} y:{}\n", .{ self.pos[0], self.pos[1] });
            return true;
        }
        return false;
    }

    pub fn pixval(self: *LookingGlass, i: usize) u16 {
        const x = @mod(i, @as(usize, @intCast(self.size.w)));
        const y = i / @as(usize, @intCast(self.size.w));
        std.debug.assert(y < self.size.h);

        const img_x = @as(usize, @intCast(self.pos[0])) + x;
        const img_y = @as(usize, @intCast(self.pos[1])) + y;

        const _info = self.img.info.?;

        const idx = _info.width * img_y + img_x;

        var elo: uHdr = undefined;
        elo.byte[0] = self.img.pixels[idx * 2];
        elo.byte[1] = self.img.pixels[idx * 2 + 1];

        return elo.hdr;
    }
    pub fn updateStorage(self: *LookingGlass, storage_dset: addon.DescriptorPrep) !void {
        const total = self.size.total;
        const lim_num = 8096;
        std.debug.assert(total <= lim_num);
        const stack_size = lim_num * @sizeOf(sht.PerInstance);
        var stack_mem: [stack_size]u8 = undefined;

        var provider: std.heap.FixedBufferAllocator = .init(&stack_mem);
        const local_a = provider.allocator();

        var scratchpad = try local_a.alloc(sht.PerInstance, total);
        var max_val: f32 = 1000000;
        var min_val: f32 = -1000000;
        for (storage_dset.buff_arr.items) |possible_buffer| {
            const storage = possible_buffer.?;
            const mapping: [*]sht.PerInstance = @ptrCast(@alignCast(storage.mapping.?));
            @memcpy(scratchpad, mapping);
            for (0..total) |i| {
                var prev_one: sht.PerInstance = scratchpad[i];
                const h = @as(f32, @floatFromInt(self.pixval(i)));

                const level = h / (256 * 256);
                if (h > max_val) max_val = h;
                if (h < min_val) min_val = h;
                prev_one.depth_ctrl[0] = 1;
                prev_one.depth_ctrl[1] = level * 1;

                scratchpad[i] = prev_one;
            }
            @memcpy(mapping, scratchpad);
        }
        // std.debug.print("+++ min: {} max: {}\n", .{ min_val, max_val });
    }
};
