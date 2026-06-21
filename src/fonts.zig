const std = @import("std");
const tt = @import("stbtt");

const hmm = @import("oct");

const files = @import("files.zig");
const sht = @import("shaders/types.zig");
const dset = @import("dset.zig");
const m = @import("math.zig");

// TODO: ok, now i know what is this sizing for, so i can name it better
// tylko jaką nazwę tutaj dać?
pub const GlyphSz = struct {
    w: c_int = 0,
    h: c_int = 0,
    x_off: c_int = 0,
    y_off: c_int = 0,

    pub fn gSize(self: *const GlyphSz) sht.GridSize {
        return sht.GridSize{
            .h = @intCast(self.h),
            .w = @intCast(self.w),
            .total = @intCast(self.w * self.h),
        };
    }

    pub inline fn empty(self: *const GlyphSz) bool {
        return self.w == 0 or self.h == 0;
    }
};

pub fn getGlyphSDF(
    font_info: [*c]const tt.stbtt_fontinfo,
    glyph: c_int,
    padding: c_int,
    on_edge_val: u8,
    dict_scale: f32,
    s: *GlyphSz,
) [*c]u8 {
    //TODO: more understancing of scale for fonts are needed
    const scale: f32 = tt.stbtt_ScaleForPixelHeight(font_info, 22);
    return tt.stbtt_GetGlyphSDF(
        font_info,
        scale,
        glyph,
        padding,
        on_edge_val,
        dict_scale,
        &s.w,
        &s.h,
        &s.x_off,
        &s.y_off,
    );
}
pub fn getCodepointBitmap(
    font_info: [*c]const tt.stbtt_fontinfo,
    codepoint: c_int,
    pixels: f32,
    s: *GlyphSz,
) [*c]u8 {
    //TODO: more understancing of scale for fonts are needed
    const scale: f32 = tt.stbtt_ScaleForPixelHeight(font_info, pixels);
    return tt.stbtt_GetCodepointBitmap(
        font_info,
        0,
        scale,
        codepoint,
        &s.w,
        &s.h,
        &s.x_off,
        &s.y_off,
    );
}

pub const FontRendering = struct {
    content: []u8,
    info: tt.stbtt_fontinfo,

    pub fn init(io: std.Io, gpa: std.mem.Allocator, ttffile: []const u8) !FontRendering {
        var self: FontRendering = undefined;
        self.content = files.fileRead(io, gpa, ttffile) catch {
            return error.FaileReadFailed;
        };
        errdefer gpa.free(self.content);
        std.debug.print("+++ FD | file ({s}) readed ({d}B)\n", .{ ttffile, self.content.len });

        if (tt.stbtt_InitFont(&self.info, self.content.ptr, 0) == 0) {
            return error.FontInitFailed;
        }
        return self;
    }

    pub fn deinit(self: *const FontRendering, gpa: std.mem.Allocator) void {
        gpa.free(self.content);
    }

    pub fn sampleCodepoint(self: *const FontRendering, gpa: std.mem.Allocator, codepnt: u8, glp_sz: *GlyphSz) ![]u8 {
        const bitmap = getCodepointBitmap(&self.info, @intCast(codepnt), 128, glp_sz);
        defer tt.stbtt_FreeBitmap(bitmap, null);

        // std.debug.print("+++ grid size {d}x{d}\n", .{ g.w, g.h });
        const g = glp_sz.gSize();
        const texture = try gpa.alloc(u8, g.total * 4);

        for (0..g.h) |yy| {
            for (0..g.w) |x| {
                const i = yy * g.w + x;
                const iq = i * 4;

                const val: u8 = bitmap[i];

                if (val == 0) {
                    texture[iq + m.A] = 0;
                    continue;
                }
                const pixval: []const u8 = &.{ val, val, val, 255 };
                @memmove(texture[iq .. iq + 4], pixval);
            }
        }
        return texture;
    }
};

pub fn bitmapTest(io: std.Io, font_info: [*c]tt.stbtt_fontinfo) !void {
    var size: GlyphSz = .{};
    const bitmap1 = getCodepointBitmap(&font_info, @intCast('a'), &size);
    defer tt.stbtt_FreeBitmap(bitmap1, null);

    const asciis: []const u8 = " .:ioVM@";
    var buffer: [1024]u8 = undefined;

    const iowriter = files.stdoutWriter(io, buffer[0..]);
    std.debug.print("+++ FD | codepoint bitmap generated {d}x{d}\n", .{ size.w, size.h });

    const w: usize = @intCast(size.w);
    const h: usize = @intCast(size.h);
    for (0..h) |yy| {
        try iowriter.print("+++ FD | ", .{});
        for (0..w) |x| {
            const val = bitmap1[yy * w + x] >> 5;
            const symbol = asciis[val .. val + 1];
            try iowriter.print("{s}{s}", .{ symbol, symbol });
        }
        try iowriter.print("\n", .{});
    }
    try iowriter.flush();
}

pub fn lettersSpliced(
    instances: [*]sht.PerInstance,
    instance_offset: u16,
    slice_num: u8,
    phi: f32,
) !void {
    const lim_num = 8096;
    std.debug.assert(slice_num <= lim_num);

    const stack_size = lim_num * @sizeOf(sht.PerInstance);
    var stack_mem: [stack_size]u8 = undefined;

    var provider: std.heap.FixedBufferAllocator = .init(&stack_mem);
    const local_a = provider.allocator();

    var scratchpad: []sht.PerInstance = try local_a.alloc(sht.PerInstance, slice_num);
    const r = 2.5;
    const denominator = m.floaty(scratchpad.len - 1);

    for (0..scratchpad.len) |i| {
        var edit: sht.PerInstance = scratchpad[i];
        const i_f: f32 = m.floaty(i);
        const progress = i_f / denominator;

        const amp = 0.2;
        const phi0 = (progress + phi) * 5;
        const r0 = r + @sin(phi0 * 4) * amp;
        const p0: m.vec3 = .{ r0 * @cos(phi0), 0, r0 * @sin(phi0) };
        edit.offset_4d = m.stack4(p0, i_f);

        const phi1 = phi0 + 0.05;
        const p1: m.vec3 = .{ r0 * @cos(phi1), 0, r0 * @sin(phi1) };

        const front: m.vec3 = m.norm(p1 - p0);
        const up: m.vec3 = .{ 0, 1, 0 };
        edit.new_usage = m.stack4(front, 0);
        edit.depth_ctrl = m.stack4(up, 0);

        scratchpad[i] = edit;
    }
    @memcpy(instances + instance_offset, scratchpad);
}

pub const Alphabet = struct {
    const show_first_blit: bool = false;
    const ascii_chars: []const u8 = //
        "abcdefghijklmnoprstuvwxyz" ++ //
        "ABCDEFGHIJKLMNOPRSTUVWXYZ" ++ //
        " _.,;:|0123456789()<>{}[]+-?\"!";

    const CharLocMap = std.AutoHashMap(u8, u16);
    num: u16,
    char_map: CharLocMap,
    char_sz_arr: []GlyphSz,
    char_texd_arr: [][]u8,
    char_atlas: []u8,
    char_uvd_arr: []m.vec4,

    pub fn deinit(self: *Alphabet, gpa: std.mem.Allocator) void {
        for (0..self.num) |i| {
            gpa.free(self.char_texd_arr[i]);
        }
        gpa.free(self.char_texd_arr);
        gpa.free(self.char_sz_arr);
        gpa.free(self.char_atlas);
        gpa.free(self.char_uvd_arr);
        self.char_map.deinit();
    }

    const atlas_w: u32 = 1024;
    const atlas_h: u32 = 1024;
    fn naiveAtlas(gpa: std.mem.Allocator, map: CharLocMap, sz_arr: []GlyphSz, texd_arr: [][]u8, pix_w: u8) !Alphabet {
        var max_w: u8 = 0;
        var max_h: u8 = 0;
        for (sz_arr) |*sz| {
            if (sz.w > max_w) max_w = @intCast(sz.w);
            if (sz.h > max_h) max_h = @intCast(sz.h);
        }

        const nx: u32 = atlas_w / max_w;
        const ny: u32 = atlas_h / max_h;
        const nmax = nx * ny;
        std.debug.print("+++ nx:{d} ny:{d} nmax:{d}\n", .{ nx, ny, nmax });
        std.debug.assert(nmax > sz_arr.len);

        var atlas_uv_data = try gpa.alloc(m.vec4, sz_arr.len);
        errdefer gpa.free(atlas_uv_data);

        var atlas = try gpa.alloc(u8, atlas_w * pix_w * atlas_h);
        for (0..sz_arr.len) |i| {
            const sz = sz_arr[i];
            const data = texd_arr[i];

            const x_start = (i % nx) * max_w;
            const y_start = (i / nx) * max_h;

            atlas_uv_data[i] = m.vec4{
                m.floaty(x_start) / m.floaty(atlas_w),
                m.floaty(y_start) / m.floaty(atlas_h),
                m.floaty(sz.w) / m.floaty(atlas_w),
                m.floaty(sz.h) / m.floaty(atlas_h),
            };

            const x_off = x_start * pix_w;
            const y_off = y_start * atlas_w * pix_w;

            const mem_off = y_off + x_off;

            const w = m.uinty(sz.w);
            const h = m.uinty(sz.h);
            for (0..h) |jj| {
                const src_off = jj * w * pix_w;
                const dst_off = mem_off + jj * atlas_w * pix_w;

                const tex_dst = atlas[dst_off .. dst_off + w * pix_w];
                const tex_src = data[src_off .. src_off + w * pix_w];
                @memcpy(tex_dst, tex_src);
            }
        }

        return .{
            .char_map = map,
            .char_sz_arr = sz_arr,
            .char_texd_arr = texd_arr,
            .char_atlas = atlas,
            .char_uvd_arr = atlas_uv_data,
            .num = @intCast(sz_arr.len),
        };
    }

    pub fn init(gpa: std.mem.Allocator, src: *const FontRendering) !Alphabet {
        const ascii_len = ascii_chars.len;

        var char_map: CharLocMap = .init(gpa);
        try char_map.ensureTotalCapacity(ascii_chars.len);
        errdefer char_map.deinit();

        var how_big = try gpa.alloc(GlyphSz, ascii_len);
        errdefer gpa.free(how_big);

        var count: u16 = 0;
        var tex_data_arr = try gpa.alloc([]u8, ascii_len);
        errdefer {
            for (0..count) |i| gpa.free(tex_data_arr[i]);
            gpa.free(tex_data_arr);
        }

        var gly_sz: GlyphSz = undefined;
        for (0.., ascii_chars) |i, char| {
            const idx: u8 = @as(u8, @intCast(i));
            try char_map.put(char, idx);
            tex_data_arr[idx] = try src.sampleCodepoint(gpa, char, &gly_sz);
            how_big[idx] = gly_sz;
            count += 1;
        }

        return try Alphabet.naiveAtlas(gpa, char_map, how_big, tex_data_arr, 4);
    }

    pub fn charInfo(self: *const Alphabet, gpa: std.mem.Allocator, write_to: *std.ArrayList(u8), idx: u16) !void {
        const valid_idx = if (idx >= self.num) self.num - 1 else idx;
        const char = ascii_chars[valid_idx];
        const sz = self.char_sz_arr[valid_idx];

        try write_to.print(gpa, "char: \"{c}\" | x{d} : y{d} | x{d} : y{d} |\n", //
            .{ char, sz.w, sz.h, sz.x_off, sz.y_off });
    }

    pub fn BlitText(
        self: *Alphabet,
        instances: [*]sht.PerInstance,
        first_inst: u16,
        text: []const u8,
    ) !u16 {
        const MAX_LETTERS = 256;
        std.debug.assert(text.len < MAX_LETTERS);

        const lim_num = 8096;
        const stack_size = lim_num * @sizeOf(sht.PerInstance);
        var stack_mem: [stack_size]u8 = undefined;
        var provider: std.heap.FixedBufferAllocator = .init(&stack_mem);
        const fba = provider.allocator();
        const scratchpad: []sht.PerInstance = try fba.alloc(sht.PerInstance, text.len);

        const inst_num = try self.blitInstances(text, scratchpad);
        @memcpy(instances + first_inst, scratchpad[0..inst_num]);

        return inst_num;
    }

    fn blitInstances(self: *Alphabet, text: []const u8, dst: []sht.PerInstance) !u16 {
        var inst_num: u16 = 0;
        var cursor: u16 = 0;
        var line: u8 = 0;
        const char_w: f32 = 24;
        const line_h: f32 = 42;
        for (text) |letter| {
            if (letter == '\n') {
                line += 1;
                cursor = 0;
                continue;
            }

            const tid = self.char_map.get(letter) orelse return error.charMissing;
            const gly_sz = self.char_sz_arr[tid];
            if (gly_sz.empty()) { //skips " "
                cursor += 1;
                continue;
            }

            const l_xpos: f32 = m.floaty(cursor) * char_w;
            const l_ypos: f32 = m.floaty(line) * line_h;
            const w = m.floaty(gly_sz.w) / 128;
            const h = m.floaty(gly_sz.h) / 128;
            const x_off = m.floaty(gly_sz.x_off) / 128;
            const y_off = m.floaty(gly_sz.y_off) / 128;

            const val = sht.PerInstance{
                .offset_2d = .{ l_xpos, -l_ypos }, //screan placement
                .offset_4d = .{ w, h, x_off, -y_off },
                .new_usage = self.char_uvd_arr[tid],
                .other_offsets = .{ @bitCast(@as(u32, tid)), 0 },
            };
            dst[inst_num] = val;
            inst_num += 1;
            cursor += 1;
        }
        return inst_num;
    }
};
