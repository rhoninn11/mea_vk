const std = @import("std");

pub const vec2 = @Vector(2, f32);
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
pub fn zero4() vec4 {
    return .{ 0, 0, 0, 0 };
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

test "|mat_mul_vec" {
    const v = vec3{ 8, -2, 1 };
    const b = matXvec(mat_identity().mat, stack4d(v, 1));

    try std.testing.expect(len(v - trim3d(b)) < 0.001);
}

pub fn matXmat(A: mat4, B: mat4) mat4u {
    return .{
        .mat = .{
            matXvec(A, B[0]), //column-major
            matXvec(A, B[1]),
            matXvec(A, B[2]),
            matXvec(A, B[3]),
        },
    };
}

test "|mat_mul_mat" {
    const a: vec3 = .{ 1, 3, 5 };
    const b: vec3 = .{ -2, 12, -5 };
    const c = a + b;

    const A = mat_translate(a);
    const B = mat_translate(b);
    const C = matXmat(A.mat, B.mat);

    const x = vec4{ 0, 0, 0, 1 };
    const y = matXvec(C.mat, x);

    var e = c - trim3d(y);
    for (0..3) |i| e[i] = abs(e[i]);
    try std.testing.expect(@reduce(.Add, e) < 0.001);
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

pub fn mat_translate(t: vec3) mat4u {
    return mat4u{
        .mat = .{
            .{ 1, 0, 0, 0 }, //column-major
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ t[0], t[1], t[2], 1 },
        },
    };
}

test "|point_moved" {
    const a = vec3{ 1, 2, 3 };
    const b = vec3{ -1, 7, 18 };
    const assumed = a + b;
    const mat = mat_translate(a);
    const t = matXvec(mat.mat, stack4d(b, 1));

    std.debug.print("translate \n", .{});
    std.debug.print("t {}\n", .{t});

    var e = assumed - trim3d(t);
    for (0..3) |i| e[i] = abs(e[i]);
    try std.testing.expect(@reduce(.Add, e) < 0.001);
}

pub fn lookRotation(pos: vec3, target: vec3) mat4u {
    const ref_up: vec3 = .{ 0, 1, 0 };
    std.debug.print("pos {}, target {}\n", .{ pos, target });

    const delta = target - pos;
    const forward = norm(delta);
    if (abs(dot(forward, ref_up)) > 0.95) {
        @panic("singularity");
    }

    const right = norm(cross(ref_up, forward));
    const up = cross(forward, right);

    // return .{
    //     .mat = .{
    //         stack4d(right, 0), //column-major
    //         stack4d(up, 0),
    //         stack4d(forward, 0),
    //         stack4d(zero3(), 1),
    //     },
    // };
    return .{
        .mat = .{
            stack4d(.{ right[X], up[X], forward[X] }, 0), //column-major
            stack4d(.{ right[Y], up[Y], forward[Y] }, 0),
            stack4d(.{ right[Z], up[Z], forward[Z] }, 0),
            stack4d(zero3(), 1),
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

pub fn mat_ortho_default() mat4u {
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

    const M2 = mat_ortho_default();
    const v2 = matXvec(M2.mat, stack4d(x2, 1));
    const v3 = matXvec(M2.mat, stack4d(x3, 1));
    try std.testing.expect(len(y2 - trim3d(v2)) < 0.001);
    try std.testing.expect(len(y3 - trim3d(v3)) < 0.001);
}
pub fn mat_persp(width: f32, height: f32, fov: f32, near: f32, far: f32) mat4u {
    std.debug.assert(height != 0);

    const aspect = width / height;
    const tan_val = std.math.tan(fov / 2);
    const depth = far - near;
    // std.debug.print("hmm {}\n", .{tan_val});
    return mat4u{
        .mat = .{
            .{ 1 / (aspect * tan_val), 0, 0, 0 }, //column-major
            .{ 0, -1 / tan_val, 0, 0 },
            .{ 0, 0, far / depth, 1 },
            .{ 0, 0, -far * near / depth, 0 },
        },
    };
}

pub fn math_persp_def() mat4u {
    return mat_persp(4, 3, std.math.pi / 2.0, 0.1, 10);
}

test "|persp_to_vulkan" {
    const x0 = .{ 1, 0, 1, 1 };
    const x1 = .{ 1, 0, 8, 1 };

    const M1 = math_persp_def().mat;

    const y0 = matXvec(M1, x0);
    const y1 = matXvec(M1, x1);

    try std.testing.expect(y0[0] / y0[3] > y1[0] / y1[3]);
    //Lesson: GPUs are deviding vec3 by w coordinate
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

pub fn mat_look_at(pos: vec3, target: vec3, ref_up: vec3) !mat4u {
    _ = ref_up;

    const trans = mat_translate(-pos);
    const rot = lookRotation(pos, target);
    return matXmat(rot.mat, trans.mat);

    // const mat: mat4u = .{
    //     .mat = .{
    //         stack4d(.{ right[X], up[X], forward[X] }, 0), //column-major
    //         stack4d(.{ right[Y], up[Y], forward[Y] }, 0),
    //         stack4d(.{ right[Z], up[Z], forward[Z] }, 0),
    //         stack4d(trans, 1),
    //     },
    // };
    // return mat;
}

const UP = vec3{ 0, 1, 0 };
test "is_matrix_looking" {
    const observ = vec3{ -1, 1, -1 };

    const M = 0;
    const R = 1;
    const U = 2;
    const point_m = vec3{ 1, 0, 1 };
    const point_r = vec3{ 1.1, 0, 1 };
    const point_u = vec3{ 1, 0.1, 1 };

    const mat = try mat_look_at(observ, point_m, UP);
    const pts: [3]vec3 = .{ point_m, point_r, point_u };
    var outs: [3]vec4 = undefined;
    for (pts, 0..) |x, i| {
        outs[i] = matXvec(mat.mat, stack4d(x, 1));
    }

    std.debug.print("---\n", .{});
    std.debug.print("middle one {}\n", .{outs[M]});
    std.debug.print("right one  {}\n", .{outs[R]});
    std.debug.print("left one   {}\n", .{outs[U]});
    try std.testing.expect(abs(outs[M][X]) < 0.001);
    try std.testing.expect(abs(outs[M][Y]) < 0.001);

    try std.testing.expect(outs[M][X] < outs[R][X]); //should be on right
    try std.testing.expect(outs[M][Y] < outs[U][Y]); //should be higher
}
