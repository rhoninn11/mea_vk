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

pub fn splat4d(a: f32) vec4 {
    return @splat(a);
}
pub fn trim3d(a: vec4) vec3 {
    return .{ a[0], a[1], a[2] };
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
    mat: mat4,
    arr: [16]f32,
};

pub fn matMul(m: mat4, v: vec4) vec4 {
    var out: vec4 = m[0] * splat4d(v[0]);
    for (1..4) |i| out += m[i] * splat4d(v[i]);
    return out;
}

test "mat mul test" {
    const v = vec3{ 8, -2, 1 };
    const b = matMul(mat_identity().mat, stack4d(v, 1));

    try std.testing.expect(len(v - trim3d(b)) < 0.001);
    try std.testing.expect(false);
    // TODO: not sure if works properly
}

pub fn len(vec: vec3) f32 {
    const squared = @reduce(.Add, vec * vec);
    return std.math.sqrt(squared);
}

test "len test" {
    const v = vec3{ 1, 0, 0 };
    const neer_zero = len(v) - 1;
    try std.testing.expect(abs(neer_zero) < 0.001);
}

pub fn norm(v: vec3) vec3 {
    return v / @as(vec3, @splat(len(v)));
}

pub fn mat_identity() mat4u {
    const out: mat4u = .{
        .arr = .{
            1, 0, 0, 0, //
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        },
    };
    return out;
}

pub fn mat_ortho(right: f32, left: f32, up: f32, down: f32, far: f32, near: f32) mat4u {
    const m4: mat4u = .{
        .arr = .{
            2 / (right - left), 0,               0,                -(right + left) / (right - left), //
            0,                  2 / (down - up), 0,                -(down + up) / (down - up),
            0,                  0,               1 / (far - near), -near / (far - near),
            0,                  0,               0,                1,
        },
    };
    return m4;
}

pub fn mat_ortho_norm() mat4u {
    const scale = 2;
    // from up down depends, y axis flip in vulkan
    return mat_ortho(scale, -scale, scale, -scale, scale, -scale);
}

test "ortho to vulkan" {
    const initial = vec3{ 10, 10, -1 };
    const final = vec3{ 1, -1, 0 };
    const mat = mat_ortho(10, 5, 10, 5, 1, -1);
    const after_transform = matMul(mat.mat, stack4d(initial, 1));

    mat_print(mat, "ortho");
    std.debug.print("{}\n", .{after_transform});
    try std.testing.expect(len(final - trim3d(after_transform)) < 0.001);
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

pub fn mat_look_at(pos: vec3, target: vec3, up: vec3) ![16]f32 {
    const delta = target - pos;
    const m_forward = norm(delta);
    if (abs(dot(m_forward, up)) > 0.95) {
        return MathErr.to_close_to_singularity;
    }

    const m_left = norm(cross(m_forward, up));
    const m_up = cross(m_left, m_forward);

    const mat: mat4 = .{
        .{ m_left[X], m_up[X], m_forward[X], pos[X] },
        .{ m_left[Y], m_up[Y], m_forward[Y], pos[Y] },
        .{ m_left[Z], m_up[Z], m_forward[Z], pos[Z] },
        stack4d(zero3(), 1),
    };
    const dual: mat4u = .{ .mat = mat };
    return dual.arr;
    // return mat_identity();
}
