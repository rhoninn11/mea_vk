const std = @import("std");

pub const vec3 = @Vector(3, f32);
pub const vec4 = @Vector(4, f32);

// column-major
pub const mat4 = [4]vec4;

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
    return mat4u{
        .mat = .{
            .{ 1, 0, 0, 0 }, //column-major
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

pub fn mat_ortho(right: f32, left: f32, up: f32, down: f32, far: f32, near: f32) mat4u {
    const w = right - left;
    const h = down - up; // Vk has -Y axis
    const d = far - near;
    return mat4u{
        .mat = .{
            .{ 2 / w, 0, 0, 0 }, // column-major
            .{ 0, 2 / h, 0, 0 },
            .{ 0, 0, 1 / d, 0 },
            .{ -(right + left) / w, -(down + up) / h, -near / d, 1 },
        },
    };
}

pub fn mat_ortho_norm() mat4u {
    const scale = 1;
    // from up down depends, y axis flip in vulkan
    return mat_ortho(scale, -scale, scale, -scale, scale, -scale);
}

test "|ortho_to_vulkan" {
    const x0 = vec3{ 10, 10, 1 };
    const x1 = vec3{ 5, 5, -1 };
    const y0 = vec3{ 1, -1, 1 };
    const y1 = vec3{ -1, 1, 0 };

    const M1 = mat_ortho(10, 5, 10, 5, 1, -1);
    const v0 = matXvec(M1.mat, stack4d(x0, 1));
    const v1 = matXvec(M1.mat, stack4d(x1, 1));
    try std.testing.expect(len(y0 - trim3d(v0)) < 0.001);
    try std.testing.expect(len(y1 - trim3d(v1)) < 0.001);

    const x2: vec3 = .{ 1, 1, 1 };
    const x3: vec3 = .{ -1, -1, -1 };
    const y2 = vec3{ 1, -1, 1 };
    const y3 = vec3{ -1, 1, 0 };

    const M2 = mat_ortho_norm();
    const v2 = matXvec(M2.mat, stack4d(x2, 1));
    const v3 = matXvec(M2.mat, stack4d(x3, 1));
    try std.testing.expect(len(y2 - trim3d(v2)) < 0.001);
    try std.testing.expect(len(y3 - trim3d(v3)) < 0.001);
}
pub fn mat_persp() [16]f32 {
    return mat_identity();
}

pub fn mat_print(mat: mat4, name: []const u8) void {
    std.debug.print("+++ {s}\n", .{name});
    for (0..4) |row| {
        std.debug.print(
            " | {d:.3} {d:.3} {d:.3} {d:.3} |\n",
            .{ mat[0][row], mat[1][row], mat[2][row], mat[3][row] },
        );
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
    const m_z = norm(delta);
    if (abs(dot(m_z, up)) > 0.95) {
        return MathErr.to_close_to_singularity;
    }

    const m_x = -norm(cross(m_z, up));
    const m_y = -cross(m_x, m_z);

    const trans: vec3 = .{
        -dot(m_x, pos),
        -dot(m_y, pos),
        -dot(m_z, pos),
    };
    const mat: mat4u = .{
        .mat = .{
            stack4d(m_x, 0), //column-major
            stack4d(m_y, 0),
            stack4d(m_z, 0),
            stack4d(trans, 1),
        },
    };
    return mat;
    // return mat_identity();
}

test "is_matrix_looking" {
    const up = vec3{ 0, 1, 0 };
    const random_point = vec3{ 0, 0, 0.5 };
    const right_nighbour = vec3{ 1, 0, 0.5 };
    const up_nighbour = vec3{ 0, 1, 0.5 };
    const observ = vec3{ 0, 0, -2 };

    const mat = try mat_look_at(observ, random_point, up);

    std.debug.print("forward: {}\n", .{mat.mat[2]});

    const t0 = matXvec(mat.mat, stack4d(random_point, 1));
    const t1 = matXvec(mat.mat, stack4d(right_nighbour, 1));
    const t2 = matXvec(mat.mat, stack4d(up_nighbour, 1));
    std.debug.print("targeted: {}\n", .{t0});
    std.debug.print("right?: {}\n", .{t1});
    std.debug.print("up?: {}\n", .{t2});
    try std.testing.expect(abs(t0[0]) < 0.001);
    try std.testing.expect(abs(t0[1]) < 0.001);

    try std.testing.expect(t0[0] < t1[0]); //should be on right
    try std.testing.expect(t0[1] < t2[1]); //should be higher
}
