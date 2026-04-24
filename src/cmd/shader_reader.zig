const std = @import("std");
const bt = @import("src/build/t.zig");

fn find_glsl_files(prefix: []const u8) !bt.DersMap {
    // std.fs.cwd().openDir(prefix, .{ .iterate = true });
    var for_abs_name: [std.fs.max_path_bytes]u8 = undefined;

    const prefix_abs = try std.fs.realpath(prefix, &for_abs_name);
    const shader_dir = try std.fs.openDirAbsolute(prefix_abs, .{ .iterate = true });

    var iter = shader_dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".vert")) {
            // std.debug.print("+++ found {s}\n", .{entry.name});
        }
        if (std.mem.endsWith(u8, entry.name, ".vert")) {
            // std.debug.print("+++ found {s}\n", .{entry.name});
        }
    }
    return bt.DersMap{
        .names = &.{ "triangle", "sprite" },
        .files = &.{
            "triangle.vert",
            "triangle.frag",
            "sprite.vert",
            "sprite.frag",
        },
    };
}
pub fn main() void {
    std.debug.print("+++ nothing yet, just doodling\n", .{});
}
