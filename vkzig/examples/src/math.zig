const std = @import("std");

const vec3 = @Vector(3, f32);
const vec4 = @Vector(4, f32);

const mat4 = [4]vec4;

const hmm_a: vec3 = .{ 1, 1, 1 };
const hmm_b: vec3 = .{ 2, 2, 2 };
const hmm_c = hmm_a + hmm_b;

const X = 0;
const Y = 1;
const Z = 2;

pub fn sum(a: [2]f32) f32 {
    return a[0] + a[1];
}
pub fn diff(a: [2]f32) f32 {
    return a[0] - a[1];
}

pub fn mul2D(a: [2]f32, times: f32) [2]f32 {
    return .{ a[X] * times, a[Y] * times };
}

pub fn add(a: [2]f32, b: [2]f32) [2]f32 {
    return .{ a[X] + b[X], a[Y] + b[Y] };
}

pub fn stack(a: [2]f32, z: f32) [3]f32 {
    return .{ a[X], a[Y], z };
}

pub fn zero3() vec3 {
    return .{ 0, 0, 0 };
}

pub fn stack4d(a: vec3, b: f32) vec4 {
    return .{ a[0], a[1], a[2], b };
}

pub fn dot(a: vec3, b: vec3) f32 {
    const squared = a[X] * b[X] + a[Y] * b[Y] + a[Z] * b[Z];
    return squared;
}

pub fn cross(a: vec3, b: vec3) vec3 {
    return .{
        a[1] * b[2] - a[2] * b[1], // x a0 b0
        a[2] * b[0] - a[0] * b[2], // y a1 b1
        a[0] * b[1] - a[1] * b[0], // z a2 b2
    };
}

test "if it even crossing" {
    const y = vec3{ 0, 1, 0 };
    const z = vec3{ 0, 0, 1 };
    const x = cross(z, y);
    // std.debug.print("!!! cross result: {d} {d} {d}\n", .{ x[0], x[1], x[2] });
    try std.testing.expect(x[0] < -0.9999);
    try std.testing.expect(x[1] < 0.0001);
    try std.testing.expect(x[2] < 0.0001);
}

const vec3u = extern union {
    vec: vec3,
    arr: [3]f32,
};

const mat4u = extern union {
    vec: mat4,
    arr: [16]f32,
};

pub fn len(vec: vec3) f32 {
    const squared = vec[X] * vec[X] + vec[Y] * vec[Y] + vec[Z] * vec[Z];
    return std.math.sqrt(squared);
}

pub fn norm(v: vec3) vec3 {
    return v / @as(vec3, @splat(len(v)));
}

pub fn mat_identity() [16]f32 {
    return .{
        1, 0, 0, 0, //
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };
}

pub fn mat_ortho() [16]f32 {
    const scale: f32 = 1.33;
    const right_left: [2]f32 = .{ scale, -scale }; //   right left
    const bot_top: [2]f32 = .{ scale, -scale }; //   up down     | vk has reversed y
    const far_near: [2]f32 = .{ 10, 0 }; // far near
    return .{
        2 / diff(right_left), 0,                 0,                  -sum(right_left) / diff(right_left), //
        0,                    2 / diff(bot_top), 0,                  -sum(bot_top) / diff(bot_top),
        0,                    0,                 1 / diff(far_near), -far_near[1] / diff(far_near),
        0,                    0,                 0,                  1,
    };
}

pub fn mat_persp() [16]f32 {
    return mat_identity();
}

pub fn mat_print(mati: mat4u, name: []const u8) void {
    const mat = mati.arr;
    std.debug.print("+++ {s}\n", .{name});
    for (0..4) |row| {
        const base = row * 4;
        std.debug.print(" | {d:.3} {d:.3} {d:.3} {d:.3} |\n", .{ mat[base], mat[base + 1], mat[base + 2], mat[base + 3] });
    }
    std.debug.print("\n\n", .{});
}

const MathErr = error{
    to_close_to_singularity,
};

pub fn abs(a: f32) f32 {
    return a * std.math.sign(a);
}

const minus_vec3 = @as(vec3, @splat(-1));

pub fn mat_look_at(from: vec3, at: vec3, up: vec3) ![16]f32 {
    const delta = at - from;
    const m_forward = norm(delta);
    if (abs(dot(m_forward, up)) > 0.95) {
        return MathErr.to_close_to_singularity;
    }

    const m_left = norm(cross(m_forward, up));
    const m_up = cross(m_left, m_forward);

    const mat: mat4 = .{
        stack4d(m_left * minus_vec3, from[X]),
        stack4d(m_up, from[Y]),
        stack4d(m_forward, from[Z]),
        stack4d(zero3(), 1),
    };
    const dual: mat4u = .{ .vec = mat };
    return dual.arr;
    // return mat_identity();
}
