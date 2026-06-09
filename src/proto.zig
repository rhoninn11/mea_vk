const std = @import("std");
const utils = @import("utils.zig");
const meagen = @import("gen/meagen.pb.zig");
const addon = @import("addons.zig");
const dset = @import("dset.zig");
const motion = @import("motion.zig");
const sht = @import("shaders/types.zig");
const shu = @import("shaders/utils.zig");

const m = @import("math.zig");
const input = @import("input.zig");
const files = @import("files.zig");

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

pub inline fn trygZero1(val: f32) f32 {
    return (val + 1) * 0.5;
}

pub inline fn tryg2u16f(val: f32) f32 {
    return ((val + 1) * 0.5 * ((1 << 16) - 3) + 1);
}

pub fn xyTrygHdr(alloc: std.mem.Allocator, g: sht.GridSize) !meagen.Image {
    var pixels = try alloc.alloc(u8, g.total * @sizeOf(u16));
    const fy: f32 = 1;
    const f1y: f32 = 0.12;
    const fx: f32 = 1;
    for (0..g.h) |y| {
        const y_phase = m.floaty(y) / 16; // give him some samples per cycle
        const y_sin = @sin(y_phase * std.math.tau * fy);
        const y_ufit = tryg2u16f(y_sin);

        const yl = trygZero1(@sin(y_phase * std.math.tau * f1y));
        // _ = yl_sin;

        for (0..g.w) |xx| {
            const x_phase = m.floaty(xx) / 16;
            const x_sin = @sin(x_phase * std.math.tau * fx);
            const x_ufit = tryg2u16f(x_sin);

            const combined = x_ufit * 0.5 + y_ufit * 0.5 * yl;
            const hdrval: uHdr = .{ .hdr = @as(u16, @intFromFloat(combined)) };

            const gdx = shu.gridI(g, xx, y);
            pixels[gdx * 2] = hdrval.byte[0];
            pixels[gdx * 2 + 1] = hdrval.byte[1];
        }
    }

    return meagen.Image{
        .info = info(g, meagen.ImgType.DUO),
        .pixels = pixels,
    };
}

pub fn findSedes(io: std.Io, here: []const u8) ![]const u8 {
    const serdes_dir = try std.Io.Dir.cwd().openDir(
        io,
        here,
        .{ .iterate = true },
    );
    defer serdes_dir.close(io);

    var iterator = serdes_dir.iterate();

    while (try iterator.next(io)) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".serdes")) {
            return entry.name;
        }
    }
    return error.NoSerdes;
}

pub const DualImageData = struct {
    raw_data: meagen.Image,
    layer_data: meagen.Image,

    pub fn initDummy(
        gpa: std.mem.Allocator,
        raw: meagen.Image,
    ) !DualImageData {
        const raw_info = raw.info.?;
        var layer_img = meagen.Image{
            .info = raw_info,
        };

        layer_img.info.?.img_type = .MONO;
        const fresh_data = try gpa.alloc(u8, raw_info.width * raw_info.height);
        @memset(fresh_data, 0);
        const y_dim = raw_info.height;
        const x_dim = raw_info.width;

        var up: u32 = 0;
        if (y_dim % x_dim != 0) up = 1;
        const slope: u32 = y_dim / x_dim + up;

        std.debug.print("+++++ w {d}, h {d}, slope is {d}\n", .{ raw_info.width, raw_info.height, slope });
        for (0..y_dim) |yy| {
            // std.debug.print("+++ debug {d}\n", .{yy});
            const idx = yy * x_dim + (yy / slope);
            fresh_data[idx] = 1;
        }
        layer_img.pixels = fresh_data;

        return .{
            .raw_data = raw,
            .layer_data = layer_img,
        };
    }

    pub fn deinit(self: *DualImageData, gpa: std.mem.Allocator) void {
        self.raw_data.deinit(gpa);
        self.layer_data.deinit(gpa);
    }
};

pub fn serdesLoadBackup(io: std.Io, gpa: std.mem.Allocator) !DualImageData {
    var raw_img = serdesLoad(io, gpa) catch |err| {
        std.debug.print("!!! synth data | {s}\n", .{@errorName(err)});
        var raw_synth = try xyTrygHdr(gpa, shu.xyGrid(256, 880));
        errdefer raw_synth.deinit(gpa);

        return DualImageData.initDummy(gpa, raw_synth);
    };
    errdefer raw_img.deinit(gpa);

    return DualImageData.initDummy(gpa, raw_img);
}

pub fn protoImgRead(io: std.Io, gpa: std.mem.Allocator, filepath: []const u8) !meagen.Image {
    var read_buffer: [8096]u8 = undefined;

    const cwd = std.Io.Dir.cwd();
    const serdesfile = try cwd.openFile(io, filepath, .{});
    defer serdesfile.close(io);

    var rader = serdesfile.reader(io, &read_buffer);
    return meagen.Image.decode(&rader.interface, gpa);
}

pub fn fakeSeachFailed(io: std.Io, gpa: std.mem.Allocator) !void {
    const fake_prefix = "./fs/fake_serdes";
    var pairs = try files.zipSearch(io, gpa, fake_prefix, &.{ ".serdes", ".serdes.mono" });
    defer pairs.deinit(gpa);
    for (pairs.file_sets) |set| {
        std.debug.print("+++ FAKE | ", .{});
        defer std.debug.print("\n", .{});
        for (set) |path| {
            std.debug.print("{s} | ", .{path});
        }
    }
}

pub fn serdesLoad(io: std.Io, gpa: std.mem.Allocator) !meagen.Image {
    const prefix = "./fs/serdes";
    // const fake_prefix = "./fs/fake_serdes";

    _ = files.zipSearch(io, gpa, prefix, &.{ ".serdes", ".serdes.mono" }) catch |err| {
        fakeSeachFailed(io, gpa) catch |err1| {
            std.debug.print("!!! fake serdes error | {s}\n", .{@errorName(err1)});
        };

        std.debug.print("!!! serdes error | {s}\n", .{@errorName(err)});
    };

    var zip = try files.zipSearch(io, gpa, prefix, &.{".serdes"});
    defer zip.deinit(gpa);

    return protoImgRead(io, gpa, zip.file_paths[0]);
}

pub const LookingGlass = struct {
    pos: @Vector(2, i32),
    g_sz: sht.GridSize,
    scan_raw: *meagen.Image,
    scan_lyr: *meagen.Image,

    pub fn init(from: *DualImageData, g_sz: sht.GridSize) LookingGlass {
        std.debug.assert(from.raw_data.info.?.img_type == meagen.ImgType.DUO);
        std.debug.assert(from.layer_data.info.?.img_type == meagen.ImgType.MONO);
        return LookingGlass{
            .pos = .{ 0, 0 },
            .g_sz = g_sz,
            .scan_raw = &from.raw_data,
            .scan_lyr = &from.layer_data,
        };
    }
    pub fn update(self: *LookingGlass, axes: *const input.DulaHoldsAxis) bool {
        const src_size = self.scan_raw.info.?;

        const max_x = @as(i32, @intCast(src_size.width)) - @as(i32, @intCast(self.g_sz.w)) - 1;
        const max_y = @as(i32, @intCast(src_size.height)) - @as(i32, @intCast(self.g_sz.h)) - 1;

        const x_axis = axes.value()[1];
        self.pos[0] = switch (x_axis) {
            motion.Axis.positive => if (self.pos[0] < max_x) self.pos[0] + 1 else max_x,
            motion.Axis.negative => if (self.pos[0] > 0) self.pos[0] - 1 else 0,
            else => self.pos[0],
        };

        const y_axis = axes.value()[0];
        self.pos[1] = switch (y_axis) {
            motion.Axis.positive => if (self.pos[1] < max_y) self.pos[1] + 1 else max_y,
            motion.Axis.negative => if (self.pos[1] > 0) self.pos[1] - 1 else 0,
            else => self.pos[1],
        };

        const is_moveing = x_axis != motion.Axis.none or y_axis != motion.Axis.none;
        return is_moveing;
    }

    const Spot2D = struct { x: u16, y: u16 };

    fn linear2Spot(self: *LookingGlass, i: usize) Spot2D {
        const x = @mod(i, @as(usize, @intCast(self.g_sz.w)));
        const y = i / @as(usize, @intCast(self.g_sz.w));
        std.debug.assert(y < self.g_sz.h);

        return .{ .x = @intCast(x), .y = @intCast(y) };
    }

    pub fn pixval(self: *LookingGlass, i: usize) u16 {
        const spot2d = self.linear2Spot(i);
        return pixvalXY(self, spot2d.x, spot2d.y);
    }

    pub fn pixvalXY(self: *LookingGlass, x: usize, y: usize) u16 {
        const img_x = @as(usize, @intCast(self.pos[0])) + x;
        const img_y = @as(usize, @intCast(self.pos[1])) + y;

        const _info = self.scan_raw.info.?;
        const w = _info.width;

        const idx = w * img_y + img_x;

        var hdr_val: uHdr = undefined;
        hdr_val.byte[0] = self.scan_raw.pixels[idx * 2];
        hdr_val.byte[1] = self.scan_raw.pixels[idx * 2 + 1];

        return hdr_val.hdr;
    }

    pub fn pixvalLayer(self: *LookingGlass, i: usize) u8 {
        const spot2d = self.linear2Spot(i);
        return pixvalXYLayer(self, spot2d.x, spot2d.y);
    }

    pub fn pixvalXYLayer(self: *LookingGlass, x: usize, y: usize) u8 {
        const img_x = @as(usize, @intCast(self.pos[0])) + x;
        const img_y = @as(usize, @intCast(self.pos[1])) + y;

        const _info = self.scan_lyr.info.?;

        const idx = _info.width * img_y + img_x;

        return self.scan_lyr.pixels[idx];
    }

    const U16max: f32 = 1 << 16;
    const TRIM_FACTOR = 0.4;
    const INST_LIM = 8096 + 4096;
    pub fn updateStorage(self: *LookingGlass, storage_dset: dset.DescriptorPrep, enabled: bool) !void {
        const total = self.g_sz.total;

        std.debug.assert(total <= INST_LIM);
        const stack_size = INST_LIM * @sizeOf(sht.PerInstance);
        var stack_mem: [stack_size]u8 = undefined;

        var provider: std.heap.FixedBufferAllocator = .init(&stack_mem);
        const local_a = provider.allocator();

        var scratchpad = try local_a.alloc(sht.PerInstance, total);
        const src_mapping = storage_dset.buff_arr.items[0].?.mapping.?;
        const instances: [*]sht.PerInstance = @ptrCast(@alignCast(src_mapping));
        @memcpy(scratchpad, instances);

        for (0..total) |i| {
            var prev_one: sht.PerInstance = scratchpad[i];
            const h = @as(f32, @floatFromInt(self.pixval(i)));

            const level = h / U16max;
            const tresholded_h = @max(0, ((level - TRIM_FACTOR) / (1 - TRIM_FACTOR)));
            // TODO: depth can be controlled by push constant mode i guess
            prev_one.depth_ctrl[0] = if (enabled) 1 else 0;
            prev_one.depth_ctrl[1] = tresholded_h;

            scratchpad[i] = prev_one;
        }

        for (storage_dset.buff_arr.items) |possible_buffer| {
            const storage = possible_buffer.?;
            const mapping: [*]sht.PerInstance = @ptrCast(@alignCast(storage.mapping.?));
            @memcpy(mapping, scratchpad);
        }
    }

    pub fn updateLayerStorage(
        self: *LookingGlass,
        storage_dset: dset.DescriptorPrep,
        first_layer_instance: u32,
        debug_info: bool,
    ) !u16 {
        const total_cells = self.g_sz.total;
        const layer_inst_total = self.g_sz.total / 2;

        const stack_size = INST_LIM * @sizeOf(sht.PerInstance);
        var stack_mem: [stack_size]u8 = undefined;

        var on_stack_alloc: std.heap.FixedBufferAllocator = .init(&stack_mem);
        const fba = on_stack_alloc.allocator();

        const src_cells_data = try fba.alloc(sht.PerInstance, total_cells);
        const scratchpad = try fba.alloc(sht.PerInstance, layer_inst_total);
        var dbg_info: std.ArrayList(u8) = try .initCapacity(fba, 4096);
        defer dbg_info.deinit(fba);

        const data_mapping = storage_dset.buff_arr.items[0].?.mapping.?;
        const instances: [*]sht.PerInstance = @ptrCast(@alignCast(data_mapping));
        @memcpy(src_cells_data, instances);
        var inst_idx: u16 = 0;

        for (0..total_cells) |i| {
            var src_inst: sht.PerInstance = src_cells_data[i];
            const h = @as(f32, @floatFromInt(self.pixval(i)));

            const level = h / U16max;
            const tresholded_h = @max(0, ((level - TRIM_FACTOR) / (1 - TRIM_FACTOR)));

            const layer_val = self.pixvalLayer(i);
            if (layer_val == 0) continue;

            const spot = self.linear2Spot(i);
            if (debug_info) try dbg_info.print(fba, "i({d}) x({d}) y({d})\n", .{ i, spot.x, spot.y });

            src_inst.depth_ctrl[1] = tresholded_h;

            scratchpad[inst_idx] = src_inst;
            inst_idx += 1;
        }

        if (debug_info) std.debug.print("+++ layer debug | \n{s}\n+++ layer debug\n", .{dbg_info.items});

        if (inst_idx > 0) {
            for (storage_dset.buff_arr.items) |possible_buffer| {
                const storage = possible_buffer.?;
                const storage_mapping: [*]sht.PerInstance = @ptrCast(@alignCast(storage.mapping.?));
                @memcpy(storage_mapping + first_layer_instance, scratchpad[0..inst_idx]);
            }
        }

        return inst_idx;
    }
};
