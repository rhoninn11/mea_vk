const std = @import("std");
const tt = @import("stbtt");

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
                const indice = yy * g.w + x;

                const val: u8 = bitmap[indice];

                if (val == 0) {
                    texture[indice * 4 + 3] = 0;
                    continue;
                }
                texture[indice * 4] = val;
                texture[indice * 4 + 1] = val;
                texture[indice * 4 + 2] = val;
                texture[indice * 4 + 3] = 255;
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
    storage_dset: dset.DescriptorPrep,
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
    for (storage_dset.buff_arr.items) |possible_buffer| {
        const denominator = @as(f32, @floatFromInt(scratchpad.len - 1));
        const r = 2.5;
        for (0..scratchpad.len) |i| {
            var edit: sht.PerInstance = scratchpad[i];
            const i_f: f32 = @as(f32, @floatFromInt(i));
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

        const storage = possible_buffer.?;
        const mapping: [*]sht.PerInstance = @ptrCast(@alignCast(storage.mapping.?));

        @memcpy(mapping + instance_offset, scratchpad);
    }
}

pub const Alphabet = struct {
    const show_first_blit: bool = false;
    const CharLocMap = std.AutoHashMap(u8, u16);
    num: u16,
    char_map: CharLocMap,
    char_sz_arr: []GlyphSz,
    char_texd_arr: [][]u8,

    first: bool = true,

    pub fn deinit(self: *Alphabet, gpa: std.mem.Allocator) void {
        for (0..self.num + 1) |i| {
            gpa.free(self.char_texd_arr[i]);
        }
        gpa.free(self.char_texd_arr);
        gpa.free(self.char_sz_arr);
        self.char_map.deinit();
    }

    pub fn init(gpa: std.mem.Allocator, src: *const FontRendering) !Alphabet {
        const ascii_chars: []const u8 = //
            "abcdefghijklmnoprstuvwxyz" ++ //
            "ABCDEFGHIJKLMNOPRSTUVWXYZ" ++ //
            " _.,;:0123456789()<>{}[]+-?!";
        const ascii_len = ascii_chars.len;

        var char_map: CharLocMap = .init(gpa);
        try char_map.ensureTotalCapacity(ascii_chars.len);
        errdefer char_map.deinit();

        var how_big = try gpa.alloc(GlyphSz, ascii_len);
        errdefer gpa.free(how_big);

        var pos: u16 = 0;
        var tex_data_arr = try gpa.alloc([]u8, ascii_len);
        errdefer {
            for (0..pos) |i| gpa.free(tex_data_arr[i]);
            gpa.free(tex_data_arr);
        }

        var gly_sz: GlyphSz = undefined;
        for (0.., ascii_chars) |i, char| {
            const next_pos: u8 = @as(u8, @intCast(i));
            try char_map.put(char, next_pos);
            tex_data_arr[next_pos] = try src.sampleCodepoint(gpa, char, &gly_sz);
            how_big[next_pos] = gly_sz;
            pos = next_pos;
            // std.debug.print("+++ {c} size {d}x{d} + {d}x{d}\n", .{
            //     char,
            //     gly_sz.w,
            //     gly_sz.h,
            //     gly_sz.x_off,
            //     gly_sz.y_off,
            // });
        }

        return .{
            .char_map = char_map,
            .char_sz_arr = how_big,
            .char_texd_arr = tex_data_arr,
            .num = pos,
        };
    }

    pub fn BlitText(
        self: *Alphabet,
        storage_dset: dset.DescriptorPrep,
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

        for (storage_dset.buff_arr.items) |possible_buffer| {
            const storage = possible_buffer.?;
            const mapping: [*]sht.PerInstance = @ptrCast(@alignCast(storage.mapping.?));

            @memcpy(mapping + first_inst, scratchpad[0..inst_num]);
        }
        return inst_num;
    }

    fn blitInstances(self: *Alphabet, text: []const u8, dst: []sht.PerInstance) !u16 {
        defer self.first = false;
        var i: u16 = 0;
        for (text) |letter| {
            if (letter == '\n') continue;
            const tid = self.char_map.get(letter) orelse continue;
            const if32: f32 = m.floaty(i);

            const letter_sz = self.char_sz_arr[tid];

            const charw = letter_sz.w;
            const xfrac = m.floaty(charw) / 128;
            if (Alphabet.show_first_blit) if (self.first)
                std.debug.print("+++ char({c}) at index({d}) has w({d}), xfrac({d})\n", //
                    .{ letter, tid, charw, xfrac });

            const val = sht.PerInstance{
                .offset_2d = .{ if32 * 0.3, 0 },
                .other_offsets = .{ xfrac, @bitCast(@as(u32, tid)) },
            };
            dst[i] = val;
            i += 1;
        }
        return i;
    }
};
