const std = @import("std");

const vec3 = @Vector(3, f32);
const vec4 = @Vector(4, f32);

// column-major
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
    return @reduce(.Add, a * b);
}

pub fn cross(a: vec3, b: vec3) vec3 {
    return .{
        a[1] * b[2] - a[2] * b[1], // x a0 b0
        a[2] * b[0] - a[0] * b[2], // y a1 b1
        a[0] * b[1] - a[1] * b[0], // z a2 b2
    };
}

pub fn len(vec: vec3) f32 {
    return std.math.sqrt(dot(vec, vec));
}

test "len test" {
    const v = vec3{ 1, 0, 0 };
    const neer_zero = len(v) - 1;
    try std.testing.expect(abs(neer_zero) < 0.001);
}

test "if it even crossing" {
    const y = vec3{ 0, 1, 0 };
    const z = vec3{ 0, 0, 1 };
    const x = cross(z, y); // right handed
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

pub fn matXvec(m: mat4, v: vec4) vec4 {
    var out: vec4 = m[0] * splat4d(v[0]);
    for (1..4) |i| out += m[i] * splat4d(v[i]);
    return out;
}

test "mat mul test" {
    const v = vec3{ 8, -2, 1 };
    const b = matXvec(mat_identity().mat, stack4d(v, 1));

    try std.testing.expect(len(v - trim3d(b)) < 0.001);
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
    const w = right - left;
    const h = down - up; // Vk has -Y axis
    const d = far - near;
    const m4: mat4u = .{
        .mat = .{
            .{ 2 / w, 0, 0, 0 }, // column-major
            .{ 0, 2 / h, 0, 0 },
            .{ 0, 0, 1 / d, 0 },
            .{ -(right + left) / w, -(down + up) / h, -near / d, 1 },
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
    const after_transform = matXvec(mat.mat, stack4d(initial, 1));

    // mat_print(mat, "ortho");
    // std.debug.print("{}\n", .{after_transform});
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

pub fn mat_look_at(pos: vec3, target: vec3, up: vec3) !mat4u {
    const delta = target - pos;
    const m_forward = norm(delta);
    if (abs(dot(m_forward, up)) > 0.95) {
        return MathErr.to_close_to_singularity;
    }

    const m_left = norm(cross(m_forward, up));
    const m_up = cross(m_left, m_forward);

    const mat: mat4u = .{
        .mat = .{
            stack4d(m_left, 0), //column-major
            stack4d(m_up, 0),
            stack4d(m_forward, 0),
            stack4d(pos, 1),
        },
    };
    return mat;
    // return mat_identity();
}

test "is matrix looking" {
    const random_point = vec3{ 1, 0, 0 };

    const mat = try mat_look_at(.{ 2, 0, 0 }, random_point, .{ 0, 1, 0 });

    const t_point = matXvec(mat.mat, stack4d(random_point, 1));
    mat_print(mat, "look at");
    std.debug.print("{}\n", .{t_point});
    try std.testing.expect(abs(t_point[0]) < 0.001);
    try std.testing.expect(abs(t_point[1]) < 0.001);
}
