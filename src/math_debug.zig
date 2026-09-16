const std = @import("std");
const math = @import("math.zig");
const rmath = @import("rmath");

const X = math.X;
const Y = math.Y;
const U = math.U;
const UP = math.UP;
const vec3 = math.vec3;
const vec4 = math.vec4;
const mat4u = math.mat4u;

pub fn prettyWrap(m4: mat4u) void {
    var somespace: [512]u8 = undefined;
    var controled = std.Io.Writer.fixed(somespace[0..]);
    prettyMat(m4, &controled, "    ") catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        return;
    };
    std.debug.print("+++ pretty result:\n{s}\n", .{controled.buffered()});
}

const AxId = enum(u8) { x, y, z, w };
const EscapeColor = std.EnumArray(AxId, []const u8);
const white = "\x1b[0m";
const ax_colors = EscapeColor.initDefault(
    white,
    .{
        .x = "\x1b[31m",
        .y = "\x1b[32m",
        .z = "\x1b[34m",
    },
);

inline fn colored(f: f32, here: *std.Io.Writer, brush: AxId) !void {
    const color = ax_colors.get(brush);
    try here.writeAll(color);
    try here.print("| {d:>6.03} |", .{f});
    try here.writeAll(white);
}

pub fn prettyV4(v4: [4]f32, paper: *std.Io.Writer) !void {
    const seq: [4]AxId = .{ .x, .y, .z, .w };
    inline for (0..4) |i| {
        try colored(v4[i], paper, seq[i]);
    }
}

pub fn prettyMat(m4: mat4u, paper: *std.Io.Writer, prefix: []const u8) !void {
    const row = 4;

    inline for (0..row) |r| {
        try paper.print("{s}|", .{prefix});
        const rowVal: [4]f32 = .{ m4.mat[0][r], m4.mat[1][r], m4.mat[2][r], m4.mat[3][r] };
        try prettyV4(rowVal, paper);
        try paper.print("|\n", .{});
    }

    try paper.flush();
}

test "is pretty printing" {
    const known_sample = math.matTrans(.{ 12, 13, 14 });

    var somespace: [512]u8 = undefined;
    var controled = std.Io.Writer.fixed(somespace[0..]);
    prettyMat(known_sample, &controled, "    ") catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        return;
    };

    const view = controled.buffered();
    if (std.mem.indexOf(u8, view, "\n")) |idx| {
        const row = view[0..idx];
        const pass = std.mem.indexOf(u8, row, "12") != null;
        try std.testing.expect(pass);
    } else {
        unreachable;
    }
}
