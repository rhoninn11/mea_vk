const std = @import("std");
const m = @import("../math.zig");

const sht = @import("../shaders/types.zig");
const shu = @import("../shaders/utils.zig");
const meagen = @import("../gen/meagen.pb.zig");
const p = @import("proto.zig");

pub inline fn sawtooth(x: f32) f32 {
    const x_p = (x + std.math.tau * 0.25);
    const x_pp = x_p / (std.math.tau);
    return 2 * (x_pp - @floor(x_pp)) - 1;
}

pub fn wave(phase: f32, frac: f32) f32 {
    const ya = @sin(phase);
    const yb = sawtooth(phase);
    return m.lerp1(ya, yb, frac);
}

const uHdr = p.uHdr;
const info = p.info;

const ridge_freq = 0.2;
pub fn ridgesHdr(alloc: std.mem.Allocator, g: sht.GridSize, frac: f32) !meagen.Image {
    var pixels = try alloc.alloc(u8, g.total * @sizeOf(u16));
    const freq: f32 = ridge_freq;

    const y_span = g.h;
    const x_span = g.w;

    const scaledown = 16.0;
    const offset = 8;
    const max = 3;

    for (0..y_span) |yy| {
        const yf = m.floaty(yy) / scaledown;
        for (0..x_span) |x| {
            const xf = m.floaty(x) / scaledown;

            const calc_point = m.vec2{ yf, xf };

            const phase = calc_point[0] * m.tau * freq;
            const y_loc = wave(phase, frac) + offset;

            const pnt_ridge = m.vec2{ calc_point[0], y_loc };

            const distance = m.len2(calc_point - pnt_ridge);
            const norm = (max - @min(max, distance)) / max;

            const hdrval: uHdr = .{ .hdr = @as(u16, @intFromFloat(norm * norm * 60000)) };
            const gdx = shu.gridI(g, x, yy);

            pixels[gdx * 2] = hdrval.byte[0];
            pixels[gdx * 2 + 1] = hdrval.byte[1];
        }
    }

    return meagen.Image{
        .info = info(g, meagen.ImgType.HDR),
        .pixels = pixels,
    };
}

pub fn ridgesMono(alloc: std.mem.Allocator, g: sht.GridSize, frac: f32) !meagen.Image {
    var pixels = try alloc.alloc(u8, g.total * @sizeOf(u8));
    errdefer alloc.free(pixels);
    @memset(pixels, 0);

    const freq: f32 = ridge_freq;

    const y_span = g.h;
    const x_span = g.w;

    const scaledown = 16.0;
    const offset = 8;
    const max: f32 = 3;

    for (0..y_span) |yy| {
        const yf = m.floaty(yy) / scaledown;
        var max_dist: f32 = 0;
        var max_x: usize = 0;
        for (0..x_span) |x| {
            const xf = m.floaty(x) / scaledown;

            const calc_point = m.vec2{ yf, xf };

            const phase = calc_point[0] * m.tau * freq;
            const y_loc = wave(phase, frac) + offset;

            const pnt_ridge = m.vec2{ calc_point[0], y_loc };

            const distance = m.len2(calc_point - pnt_ridge);
            const norm = (max - @min(max, distance)) / max;
            if (max_dist >= norm) continue;

            max_dist = norm;
            max_x = x;
        }
        if (max_dist > 0.1) { //some non zero
            const gdx = shu.gridI(g, max_x, yy);
            pixels[gdx] = 1 + @as(u8, @intCast(yy % 2));
        }
    }

    return meagen.Image{
        .info = info(g, meagen.ImgType.MONO),
        .pixels = pixels,
    };
}

pub fn xyTrygHdr(alloc: std.mem.Allocator, g: sht.GridSize, f_mult: f32) !meagen.Image {
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
            const x_phase = m.floaty(x) * f_mult / 16;
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
        .info = info(g, meagen.ImgType.HDR),
        .pixels = pixels,
    };
}

pub fn genLayers(gpa: std.mem.Allocator, _info: *const meagen.ImgInfo) !meagen.Image {
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
