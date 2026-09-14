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

pub fn prettyMat(m4: mat4u, here: *std.Io.Writer, prefix: []const u8) !void {
    // TODO: column major would be trickier to color
    const col = 4;
    const row = 4;
    for (0..row) |r| {
        try here.print("{s}|", .{prefix});
        for (0..col) |c| {
            const cVal: [4]f32 = m4.mat[c];

            const x = cVal[r];
            try here.print(" {d:>6.03} ", .{x});
        }
        try here.print("|\n", .{});
    }

    try here.flush();
    // _ = m4;
    // _ = here;
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

test "looking understanding" {
    const observ = vec3{ -1, 1, -1 };

    const M = 0;
    const Ri = 1;
    const _U = 2;
    const target = vec3{ 1, 0, 1 };
    const target_right = vec3{ 1.1, 0, 1 };
    const target_upper = vec3{ 1, 0.1, 1 };

    var somespace: [512]u8 = undefined;

    const transform = try math.matLookAt(observ, target, UP);
    const r_ref_transform = rmath.MatrixLookAt(
        math.rvec3(observ),
        math.rvec3(target),
        math.rvec3(UP),
    );
    const r_mat4u = math.fromRMat4(r_ref_transform);
    {
        var stderr = std.debug.lockStderr(somespace[0..]).file_writer;
        defer std.debug.unlockStderr();

        const w2 = &stderr.interface;
        try prettyMat(transform, w2, "custom ");
        try w2.print("---\n", .{});
        try prettyMat(r_mat4u, w2, "raylib ");
    }

    var outs: [3]vec4 = undefined;
    const to_transform: [3]vec3 = .{ target, target_right, target_upper };
    for (to_transform, 0..) |x, i| {
        outs[i] = math.matXvec(transform.mat, math.stack4(x, 1));
    }

    std.debug.print("---\n", .{});
    std.debug.print("middle one {}\n", .{outs[M]});
    std.debug.print("right one  {}\n", .{outs[Ri]});
    std.debug.print("left one   {}\n", .{outs[_U]});
    try std.testing.expect(math.abs(outs[M][X]) < 0.001);
    try std.testing.expect(math.abs(outs[M][Y]) < 0.001);

    try std.testing.expect(outs[M][X] < outs[Ri][X]); //should be on right
    try std.testing.expect(outs[M][Y] < outs[U][Y]); //should be higher
}
