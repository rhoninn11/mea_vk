const std = @import("std");
const sht = @import("shaders/types.zig");
const m = @import("math.zig");
const vk = @import("vulkan-zig");
const sdlh = @import("sdlh.zig");

pub const DbgMonitor = struct {
    linecount: u8 = 0,
    enabled: bool = false,

    pub fn clearPrev(self: *DbgMonitor, iowriter: *std.Io.Writer) !void {
        if (self.linecount != 0) for (0..self.linecount) |_| {
            try iowriter.print("\x1b[2K", .{}); // wyczyść linię
            try iowriter.print("\x1b[1A", .{}); // w górę
        };
    }
    pub const DbgVals = struct {
        phi: f32,
        inst_num: u16,
        observer_pos: m.vec3,
        win_size: vk.Extent2D,
    };
    pub fn update(
        self: *DbgMonitor,
        io: std.Io,
        current: *const DbgVals,
    ) !void {
        if (!self.enabled) return;

        var buffer: [1024]u8 = undefined;
        const stdout: std.Io.File = .stderr();
        var w = stdout.writer(io, &buffer);

        //const pointer to interface was the right way on windows
        const iowriter: *std.Io.Writer = &w.interface;

        try self.clearPrev(iowriter);

        var lines: u8 = 9;
        try iowriter.print("---------------\n", .{});
        try iowriter.print("--- {s: <12}: \x1b[31m{d}\x1b[0m\n", .{ "phi", current.phi });
        try iowriter.print("--- {s: <12}: \x1b[32m{d}\x1b[0m\n", .{ "inst_num", current.inst_num });
        try iowriter.print("--- {s: <12}: \x1b[33m{}\x1b[0m\n", .{ "observer", current.observer_pos });
        try iowriter.print("--- {s: <12}: \x1b[33m{}\x1b[0m\n", .{ "window w", current.win_size.width });
        try iowriter.print("--- {s: <12}: \x1b[33m{}\x1b[0m\n", .{ "window h", current.win_size.height });
        try iowriter.print("---------------\n", .{});
        lines += try sdlh.pointerInfo("---", iowriter);
        try iowriter.print("---------------\n", .{});
        lines += try sdlh.getEvCounter().info("--- ", iowriter);
        try iowriter.print("---------------\n", .{});
        try iowriter.flush();

        self.linecount = lines;
    }
};

pub const PerfStats = struct {
    t0: i64,
    frame_num: u32,

    pub fn init(io: std.Io) PerfStats {
        std.debug.print("--- empty line ---\n", .{});
        const ts = std.Io.Timestamp.now(io, .real);
        const now_ms = std.Io.Timestamp.toMilliseconds(ts);
        return PerfStats{
            .t0 = now_ms,
            .frame_num = 0,
        };
    }

    pub fn messure(s: *PerfStats, io: std.Io) void {
        const ts = std.Io.Timestamp.now(io, .real);
        const now_ms = std.Io.Timestamp.toMilliseconds(ts);
        const delta = now_ms - s.t0;

        const messure_interval = 1000.0;
        const update_interval = 500;
        const update_interval_i: u32 = @intFromFloat(update_interval);

        const scale: f32 = messure_interval / update_interval;
        if (delta > update_interval_i) {
            // std.debug.print("\x1B[A\x1B[2K", .{});
            var fps: f32 = @floatFromInt(s.frame_num);
            fps *= scale;

            if (fps > 9000) {
                // std.debug.print("+++ omg is over 9000 {d}\n", .{fps});
            }
            // std.debug.print("+++ rendering hit {d} fps\n", .{fps});
            s.t0 += update_interval_i;
            s.frame_num = 0;
        }

        s.frame_num += 1;
    }
};

pub fn ppmRGBADebug(io: std.Io, data: []u8, g: sht.GridSize) !void {
    const f = try std.Io.Dir.cwd().createFile(io, "fs/debug.ppm", .{});
    defer f.close(io);

    var tmp_bfr: [4096]u8 = undefined;

    var wr = f.writer(io, tmp_bfr[0..]);
    const iowriter = &wr.interface;

    try iowriter.print("P6\n{} {}\n255\n", .{ g.w, g.h });

    const pix_num = data.len / 4;
    for (0..pix_num) |i| {
        const pix = data[i * 4 .. i * 4 + 3];
        try iowriter.writeAll(pix);
    }

    try iowriter.flush();
}

pub fn ppmU8Debug(io: std.Io, data: []u8, g: sht.GridSize) !void {
    const f = try std.Io.Dir.cwd().createFile(io, "fs/debug.ppm", .{});
    defer f.close(io);

    var tmp_bfr: [4096]u8 = undefined;

    var wr = f.writer(io, tmp_bfr[0..]);
    const iowriter = &wr.interface;

    try iowriter.print("P6\n{} {}\n255\n", .{ g.w, g.h });

    const pix_num = data.len;
    for (0..pix_num) |i| {
        const val = data[i];
        const pix: []const u8 = &.{ val, val, val };
        try iowriter.writeAll(pix);
    }

    try iowriter.flush();
}
