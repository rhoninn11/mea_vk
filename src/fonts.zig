const std = @import("std");
const tt = @import("stbtt");

const files = @import("files.zig");
const sht = @import("shaders/types.zig");

const Sizing = struct {
    w: c_int = 0,
    h: c_int = 0,
    x_off: c_int = 0,
    y_off: c_int = 0,

    pub fn gSize(self: *const Sizing) sht.GridSize {
        return sht.GridSize{
            .h = @intCast(self.h),
            .w = @intCast(self.w),
            .total = @intCast(self.w * self.h),
        };
    }
};

pub fn getGlyphSDF(
    font_info: [*c]tt.stbtt_fontinfo,
    glyph: c_int,
    padding: c_int,
    on_edge_val: u8,
    dict_scale: f32,
    s: *Sizing,
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
    font_info: [*c]tt.stbtt_fontinfo,
    codepoint: c_int,
    pixels: f32,
    s: *Sizing,
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

    pub fn sampleCodepoint(self: *FontRendering, gpa: std.mem.Allocator, codepnt: u8, g_size: *sht.GridSize) ![]u8 {
        var size: Sizing = .{};
        const bitmap = getCodepointBitmap(&self.info, @intCast(codepnt), 128, &size);
        defer tt.stbtt_FreeBitmap(bitmap, null);

        const g = size.gSize();
        const texture = try gpa.alloc(u8, g.total * 4);
        std.debug.print("+++ bitmap len {d} | texture len {d}\n", .{ g.total, texture.len });
        g_size.* = g;

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
    var size: Sizing = .{};
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

pub fn fonts_demo(init: std.process.Init) !void {
    const fontfile = "fs/roboto.ttf";
    var font = try FontRendering.init(init.io, init.gpa, fontfile);
    defer font.deinit(init.gpa);

    var sizing: Sizing = .{};
    const bitmap = getGlyphSDF(&font.info, @intCast('a'), 5, 128, 5.0, &sizing);
    defer tt.stbtt_FreeSDF(bitmap, null);
    if (bitmap == null) {
        return std.debug.print("!!! FD | sdf gen failed\n", .{});
    }
    std.debug.print("+++ FD | sdf bitmap generated {d}x{d}\n", .{ sizing.w, sizing.h });
}
