const std = @import("std");
const tt = @import("stbtt");

const files = @import("files.zig");

const Sizing = struct {
    w: c_int = 0,
    h: c_int = 0,
    x_off: c_int = 0,
    y_off: c_int = 0,
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
    s: *Sizing,
) [*c]u8 {
    //TODO: more understancing of scale for fonts are needed
    const scale: f32 = tt.stbtt_ScaleForPixelHeight(font_info, 48);
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

pub fn fonts_demo(init: std.process.Init) !void {
    const fontfile = "fs/roboto.ttf";
    const file_content = files.fileRead(init.io, init.gpa, fontfile) catch {
        return std.debug.print("!!! FD | file ({s}) failed to read\n", .{fontfile});
    };
    defer init.gpa.free(file_content);
    std.debug.print("+++ FD | file ({s}) readed ({d}B)\n", .{ fontfile, file_content.len });

    var font_obj: tt.stbtt_fontinfo = undefined;
    if (tt.stbtt_InitFont(&font_obj, file_content.ptr, 0) == 0) {
        return std.debug.print("!!! FD | font init failed {s}\n", .{fontfile});
    }

    var s0: Sizing = .{};
    const bitmap = getGlyphSDF(&font_obj, @intCast('a'), 5, 128, 5.0, &s0);
    defer tt.stbtt_FreeSDF(bitmap, null);
    if (bitmap == null) {
        return std.debug.print("!!! FD | sdf gen failed\n", .{});
    }
    std.debug.print("+++ FD | sdf bitmap generated {d}x{d}\n", .{ s0.w, s0.h });

    var s1: Sizing = .{};
    const bitmap1 = getCodepointBitmap(&font_obj, @intCast('a'), &s1);
    std.debug.print("+++ FD | codepoint bitmap generated {d}x{d}\n", .{ s1.w, s1.h });

    const stderr = std.Io.File.stderr();
    var tmp: [1024]u8 = undefined;

    var w = stderr.writer(init.io, tmp[0..]);
    const iowriter: *std.Io.Writer = &w.interface;

    const asciis: []const u8 = " .:ioVM@";

    const wusize: usize = @intCast(s1.w);
    for (0..@intCast(s1.h)) |jj| {
        try iowriter.print("+++ FD | ", .{});
        for (0..wusize) |i| {
            const val = bitmap1[jj * wusize + i] >> 5;
            const symbol = asciis[val .. val + 1];
            try iowriter.print("{s}{s}", .{ symbol, symbol });
        }
        try iowriter.print("\n", .{});
    }
    try iowriter.flush();
}
