const std = @import("std");
const tt = @import("stbtt");

pub fn fonts_exp(init: std.process.Init) !void {
    var chunk4k: [4096]u8 = undefined;
    const cwd = std.Io.Dir.cwd();
    const font_ttf = "fs/roboto.ttf";
    var font_obj: tt.stbtt_fontinfo = undefined;
    var font_ok = false;

    const ttf_file = cwd.openFile(init.io, font_ttf, .{}) catch {
        std.debug.print("!!!??? failed to open {s}\n", .{font_ttf});
        return;
    };
    defer ttf_file.close(init.io);

    var rFile = ttf_file.reader(init.io, chunk4k[0..]);
    const fSize = try rFile.getSize();
    std.debug.print("+++??? ttf file size is: {d}\n", .{fSize});
    const ioreader: *std.Io.Reader = &rFile.interface;
    const font_data = try ioreader.readAlloc(init.gpa, try rFile.getSize());
    defer init.gpa.free(font_data);

    if (tt.stbtt_InitFont(&font_obj, font_data.ptr, 0) == 0) {
        std.debug.print("!!!??? font init failed {s}\n", .{font_ttf});
        return;
    }
    font_ok = true;

    const scale: f32 = tt.stbtt_ScaleForPixelHeight(&font_obj, 22);
    var w: c_int, var h: c_int, var xoff: c_int, var yoff: c_int = .{ 0, 0, 0, 0 };
    const bitmap = tt.stbtt_GetGlyphSDF(&font_obj, scale, @intCast('a'), 5, 180, 5.0, &w, &h, &xoff, &yoff);
    defer tt.stbtt_FreeSDF(bitmap, null);
    if (bitmap == null) {}

    std.debug.print("+++??? sdf bitmap generated\n", .{});
}
