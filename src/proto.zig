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
const oklab = @import("oklab.zig");

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

pub fn xyTrygHdr(alloc: std.mem.Allocator, g: sht.GridSize) !meagen.Image {
    var pixels = try alloc.alloc(u8, g.total * @sizeOf(u16));
    const fy: f32 = 0.6;
    const f1y: f32 = 0.12;
    const fx: f32 = 0.34;
    for (0..g.h) |yy| {
        const y_phase = m.floaty(yy) / 16; // give him some samples per cycle
        const y_sin = @sin(y_phase * std.math.tau * fy);
        const y_ufit = m.tryg2u16f(y_sin);

        const yl = m.trygZero1(@sin(y_phase * std.math.tau * f1y));
        // _ = yl_sin;

        for (0..g.w) |x| {
            const x_phase = m.floaty(x) / 16;
            const x_sin = @sin(x_phase * std.math.tau * fx);
            const x_ufit = m.tryg2u16f(x_sin);

            const combined = x_ufit * 0.5 + y_ufit * 0.5 * yl;
            const hdrval: uHdr = .{ .hdr = @as(u16, @intFromFloat(combined)) };

            const gdx = shu.gridI(g, x, yy);
            pixels[gdx * 2] = hdrval.byte[0];
            pixels[gdx * 2 + 1] = hdrval.byte[1];
        }
    }

    return meagen.Image{
        .info = info(g, meagen.ImgType.DUO),
        .pixels = pixels,
    };
}

pub const DualImageData = struct {
    raw_data: meagen.Image,
    layer_data: meagen.Image,

    pub fn initDummy(gpa: std.mem.Allocator) !DualImageData {
        var raw_synth = try xyTrygHdr(gpa, shu.xyGrid(256, 880));
        errdefer raw_synth.deinit(gpa);

        return .{
            .raw_data = raw_synth,
            .layer_data = try genLayers(gpa, &raw_synth.info.?),
        };
    }

    pub fn initProto(io: std.Io, gpa: std.mem.Allocator, pbfr_files: []const []const u8) !DualImageData {
        std.debug.assert(pbfr_files.len == 2);

        var scann = try protoImgRead(io, gpa, pbfr_files[0]);
        errdefer scann.deinit(gpa);

        const layers = try protoImgRead(io, gpa, pbfr_files[1]);
        errdefer scann.deinit(layers);

        return .{
            .raw_data = scann,
            .layer_data = layers,
        };
    }

    fn genLayers(gpa: std.mem.Allocator, _info: *const meagen.ImgInfo) !meagen.Image {
        const y_dim = _info.height;
        const x_dim = _info.width;
        var l_info = _info.*;
        l_info.img_type = .MONO;

        const fresh_data = try gpa.alloc(u8, x_dim * y_dim);
        @memset(fresh_data, 0);

        const slope: u32 = s: {
            var up: u32 = 0;
            if (y_dim % x_dim != 0) up = 1;
            break :s y_dim / x_dim + up;
        };

        for (0..y_dim) |yy| {
            const idx = yy * x_dim + (yy / slope);
            const cell = fresh_data[idx];
            fresh_data[idx] = cell | 1;
        }

        const width = 35.0;
        const cycles = 4.0;

        const y_scale = m.floaty(y_dim) / (cycles * m.tau);
        const mid = m.floaty(x_dim) / 2;
        for (0..y_dim) |yy| {
            var placed = false;
            const sin = @sin(m.floaty(yy) / y_scale);
            for (0..x_dim) |x| {
                const pos = m.floaty(x);
                const pixval = (mid - pos) / width;

                const delta = @abs(sin - pixval);
                if (delta < 0.05 and !placed) {
                    const idx = yy * x_dim + x;
                    const cell = fresh_data[idx];
                    fresh_data[idx] = cell | 2;
                    placed = true;
                }
            }
        }

        return meagen.Image{
            .info = l_info,
            .pixels = fresh_data,
        };
    }

    pub fn deinit(self: *DualImageData, gpa: std.mem.Allocator) void {
        self.raw_data.deinit(gpa);
        self.layer_data.deinit(gpa);
    }
};

pub fn serdesLoadBackup(io: std.Io, gpa: std.mem.Allocator) !DualImageData {
    const raw_img = serdesLoad(io, gpa) catch |err| {
        std.debug.print("+++ dummy synthesis | {s}\n", .{@errorName(err)});
        return DualImageData.initDummy(gpa);
    };
    return raw_img;
}

pub fn protoImgRead(io: std.Io, gpa: std.mem.Allocator, filepath: []const u8) !meagen.Image {
    var read_buffer: [8096]u8 = undefined;

    const cwd = std.Io.Dir.cwd();
    const serdesfile = try cwd.openFile(io, filepath, .{});
    defer serdesfile.close(io);

    var rader = serdesfile.reader(io, &read_buffer);
    return meagen.Image.decode(&rader.interface, gpa);
}

pub fn serdesLoad(io: std.Io, gpa: std.mem.Allocator) !DualImageData {
    const prefix = "./fs/serdes";

    var zip = try files.zipSearch(io, gpa, prefix, &.{ ".serdes", ".serdes.mono" });
    defer zip.deinit(gpa);
    return try DualImageData.initProto(io, gpa, zip.file_sets[0]);
}

pub const LookingGlass = struct {
    pos: @Vector(2, i32),
    sliders: [2]utils.Slider,
    win_sz: sht.GridSize,

    img_sz: sht.GridSize,
    scan_raw: *meagen.Image,
    scan_lyr: *meagen.Image,
    inverse: bool = false,

    pub fn init(from: *DualImageData, g_sz: sht.GridSize) LookingGlass {
        std.debug.assert(from.raw_data.info.?.img_type == meagen.ImgType.DUO);
        std.debug.assert(from.layer_data.info.?.img_type == meagen.ImgType.MONO);

        const src = &from.raw_data.info.?;

        var self = LookingGlass{
            .pos = .{ 0, 0 },
            .win_sz = g_sz,
            .scan_raw = &from.raw_data,
            .scan_lyr = &from.layer_data,
            .img_sz = sht.shu.xyGrid(@intCast(src.width), @intCast(src.height)),
            .sliders = undefined,
        };

        self.sliders[m.X] = .init(0, m.u16cast(self.limX(self.scan_raw)));
        self.sliders[m.Y] = .init(0, m.u16cast(self.limY(self.scan_raw)));

        return self;
    }
    inline fn limX(self: *const @This(), img: *meagen.Image) i32 {
        const src_size = img.info.?;
        return @as(i32, @intCast(src_size.width)) - @as(i32, @intCast(self.win_sz.w)) - 1;
    }
    inline fn limY(self: *const @This(), img: *meagen.Image) i32 {
        const src_size = img.info.?;
        return @as(i32, @intCast(src_size.height)) - @as(i32, @intCast(self.win_sz.h)) - 1;
    }

    pub fn update(self: *LookingGlass, axes: *const input.DualHoldsAxis, td: f32) bool {
        const ax: [2]u8 = .{ m.X, m.Y };
        const ax_val = axes.value();

        const px_speed: f32 = 400;
        // const px_speed_boost: f32 = 800;

        const times = @max(1, m.uinty(px_speed * td));

        for (0..times) |_| {
            inline for (ax) |slot| {
                self.pos[slot] = self.sliders[slot].drive(ax_val[slot]);
            }
        }

        const is_moveing = ax_val[m.X] != motion.Axis.none or ax_val[m.Y] != motion.Axis.none;
        return is_moveing;
    }
    pub fn frac(self: *const LookingGlass) m.vec2 {
        return .{
            m.floaty(self.pos[m.X]) / m.floaty(self.img_sz.w),
            m.floaty(self.pos[m.Y]) / m.floaty(self.img_sz.h),
        };
    }

    const LookingSpot = struct { x: u16, y: u16 };

    fn lookingSpot(self: *LookingGlass, i: usize) LookingSpot {
        const x = @mod(i, @as(usize, @intCast(self.win_sz.w)));
        const y = i / @as(usize, @intCast(self.win_sz.w));
        std.debug.assert(y < self.win_sz.h);

        return LookingSpot{ .x = @intCast(x), .y = @intCast(y) };
    }

    fn lookingIdx(self: *LookingGlass, i: usize) usize {
        const spot = lookingSpot(self, i);
        const img_x = @as(usize, @intCast(self.pos[0])) + spot.x;
        const img_y = @as(usize, @intCast(self.pos[1])) + spot.y;

        const _info = self.scan_raw.info.?;
        const w = _info.width;

        return w * img_y + img_x;
    }

    inline fn hdrVal(self: *const LookingGlass, lo_idx: usize) u16 {
        var hdr_val: uHdr = undefined;
        hdr_val.byte[0] = self.scan_raw.pixels[lo_idx * 2];
        hdr_val.byte[1] = self.scan_raw.pixels[lo_idx * 2 + 1];
        return hdr_val.hdr;
    }

    inline fn stdval(self: *const LookingGlass, lo_idx: usize) u8 {
        return self.scan_lyr.pixels[lo_idx];
    }

    pub fn scanValNorm(self: *LookingGlass, i: usize) f32 {
        const U16max: f32 = 1 << 16;
        const uval = self.hdrVal(self.lookingIdx(i));
        const fval = @as(f32, @floatFromInt(uval));
        const norm = fval / U16max;

        return if (self.inverse) 1 - norm else norm;
    }

    pub fn layerVal(self: *LookingGlass, i: usize) u8 {
        return self.stdval(self.lookingIdx(i));
    }

    const TRIM_FACTOR = 0.4;
    const INST_LIM = 8096 + 4096;
    pub fn bakeScann(self: *LookingGlass, instances: [*]sht.PerInstance, enabled: bool) !void {
        const total = self.win_sz.total;

        std.debug.assert(total <= INST_LIM);
        const stack_size = INST_LIM * @sizeOf(sht.PerInstance);
        var stack_mem: [stack_size]u8 = undefined;

        var provider: std.heap.FixedBufferAllocator = .init(&stack_mem);
        const local_a = provider.allocator();

        var scratchpad = try local_a.alloc(sht.PerInstance, total);
        @memcpy(scratchpad, instances);

        for (0..total) |i| {
            var prev_one: sht.PerInstance = scratchpad[i];
            const level = self.scanValNorm(i);

            const tresholded_h = @max(0, ((level - TRIM_FACTOR) / (1 - TRIM_FACTOR)));
            // TODO: depth can be controlled by push constant mode i guess
            prev_one.depth_ctrl[0] = if (enabled) 1 else 0;
            prev_one.depth_ctrl[1] = tresholded_h;

            scratchpad[i] = prev_one;
        }

        @memcpy(instances, scratchpad);
    }

    pub fn bakeRidges(
        self: *LookingGlass,
        instances: [*]sht.PerInstance,
        first_layer_instance: u32,
        debug_info: bool,
    ) !u16 {
        const total_cells = self.win_sz.total;
        const layer_inst_total = self.win_sz.total / 2;

        const stack_size = INST_LIM * @sizeOf(sht.PerInstance);
        var stack_mem: [stack_size]u8 = undefined;

        var on_stack_alloc: std.heap.FixedBufferAllocator = .init(&stack_mem);
        const fba = on_stack_alloc.allocator();

        const src_cells_data = try fba.alloc(sht.PerInstance, total_cells);
        const scratchpad = try fba.alloc(sht.PerInstance, layer_inst_total);
        var dbg_info: std.ArrayList(u8) = try .initCapacity(fba, 4096);
        defer dbg_info.deinit(fba);

        @memcpy(src_cells_data, instances);
        var inst_idx: u16 = 0;

        for (0..total_cells) |i| {
            var src_inst: sht.PerInstance = src_cells_data[i];
            const level = self.scanValNorm(i);
            const tresholded_h = @max(0, ((level - TRIM_FACTOR) / (1 - TRIM_FACTOR)));

            const layer_val = self.layerVal(i);
            if (layer_val == 0) continue;

            const spot = self.lookingSpot(i);
            if (debug_info) try dbg_info.print(fba, "i({d}) x({d}) y({d})\n", .{ i, spot.x, spot.y });

            src_inst.depth_ctrl[1] = tresholded_h;

            scratchpad[inst_idx] = src_inst;
            inst_idx += 1;
        }

        if (debug_info) std.debug.print("+++ layer debug | \n{s}\n+++ layer debug\n", .{dbg_info.items});

        if (inst_idx > 0) {
            @memcpy(instances + first_layer_instance, scratchpad[0..inst_idx]);
        }

        return inst_idx;
    }

    // TODO: making some space
    const LookingOk = struct {
        grid: sht.GridSize,
        size: m.vec2,
        pix: []u8,

        pub fn deinit(self: *LookingOk, gpa: std.mem.Allocator) void {
            gpa.free(self.pix);
        }
    };
    pub fn sampleVolData(self: *const LookingGlass, gpa: std.mem.Allocator) !LookingOk {
        const sample_sz = sht.shu.xyGrid(1024, 16);
        const inferno = try oklab.sampleInfernoAlt(gpa, &sample_sz);
        defer gpa.free(inferno);

        const isz = self.img_sz;
        var sample = LookingOk{
            .grid = isz,
            .size = .{ isz.w, isz.h },
            .pix = try gpa.alloc(u8, isz.total * @sizeOf(u32)),
        };
        errdefer sample.deinit(sample);

        for (0..isz.h) |yy| {
            for (0..isz.w) |x| {
                const pix_idx = yy * isz.w + x;
                const pix_mem = pix_idx * 4;
                const inferno_idx = self.hdrVal(pix_idx) >> 6; // to match sample_sz
                const inferne_mem = inferno_idx * 4;
                const inferno_rgba = inferno[inferne_mem .. inferne_mem + 4];
                @memmove(sample.pix[pix_mem .. pix_mem + 4], inferno_rgba);
            }
        }
        return sample;
    }

    const colors: []const []const u8 = &.{
        &.{ 255, 0, 0, 255 },
        &.{ 0, 255, 0, 255 },
        &.{ 0, 0, 255, 255 },
        &.{ 255, 128, 0, 255 },
        &.{ 255, 0, 128, 255 },
        &.{ 255, 128, 128, 255 },
        &.{ 128, 255, 0, 255 },
        &.{ 0, 255, 128, 255 },
        &.{ 128, 255, 128, 255 },
    };
    const discard: []const u8 = &.{ 0, 0, 0, 0 };

    pub fn sampleLayers(self: *const LookingGlass, gpa: std.mem.Allocator) !LookingOk {
        const isz = self.img_sz;
        const layer_num = 8;

        var depths = try gpa.alloc(u16, layer_num * isz.h);
        defer gpa.free(depths);
        @memset(depths, 60000);

        for (0..isz.h) |yy| {
            for (0..isz.w) |x| {
                const pix_idx = yy * isz.w + x;
                const markers = self.stdval(pix_idx);

                for (0..8) |i| {
                    const marked = ((markers >> @intCast(i)) & 1) == 1;
                    if (marked) {
                        depths[yy * 8 + i] = @intCast(x);
                    }
                }
            }
        }

        var sample = LookingOk{
            .grid = isz,
            .size = .{ m.floaty(isz.w), m.floaty(isz.h) },
            .pix = try gpa.alloc(u8, isz.total * @sizeOf(u32)),
        };
        errdefer sample.deinit(sample);

        const line_depth = 4;
        for (0..isz.h) |yy| {
            for (0..isz.w) |x| {
                const pix_idx = yy * isz.w + x;
                const pix_mem = pix_idx * 4;
                const write_slot = sample.pix[pix_mem .. pix_mem + 4];

                var blanc = true;
                for (0..layer_num) |i| {
                    const depth_at = yy * layer_num + i;
                    const depth = depths[depth_at];
                    inline for (0..line_depth) |margin| {
                        if (depth + margin == x) {
                            @memmove(write_slot, colors[i]);
                            blanc = false;
                        }
                    }
                }
                if (blanc) @memmove(write_slot, discard);
            }
        }

        return sample;
    }
};
