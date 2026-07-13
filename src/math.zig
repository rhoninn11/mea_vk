const std = @import("std");
const vk = @import("vulkan-zig");
const rmath = @import("rmath");

pub const tau = std.math.tau;

pub const vec2 = @Vector(2, f32);
pub const vec3 = @Vector(3, f32);
pub const vec4 = @Vector(4, f32);
pub const uvec4 = @Vector(4, u8);

const glsl_alignment = 16;
// glsl mat4 alignment is 16B
test "allignment explorer" {
    const v4a = @alignOf(vec4);
    const v3a = @alignOf(vec3);

    try std.testing.expect(v4a == glsl_alignment);
    try std.testing.expect(v3a == glsl_alignment);

    const v4b = @alignOf([7]f32);
    try std.testing.expect(v4b == 4);

    const raymat: rmath.struct_Matrix = rmath.MatrixIdentity();
    try std.testing.expectEqual(glsl_alignment / 4, @alignOf(@TypeOf(raymat)));

    const uni: mat4u = .{ .rmat = raymat };
    try std.testing.expectEqual(glsl_alignment, @alignOf(@TypeOf(uni)));
}

const sht = @import("shaders/types.zig");
test "union behav" {
    const m_I = matIden();

    const mpa = sht.MatPack{
        .model = m_I.arr,
        .proj = m_I.arr,
        .view = m_I.arr,
    };
    const matpack_alignment = @alignOf(@TypeOf(mpa));
    const unifompack_alignment = @alignOf(sht.GroupData);

    try std.testing.expectEqual(4, matpack_alignment);
    try std.testing.expectEqual(16, glsl_alignment);
    try std.testing.expectEqual(4, unifompack_alignment);
    // TODO: Daaaymn, so how it alighns with mat4 gpu alignment?
}

pub const mat4 = [4]vec4;
pub const mat3 = [3]vec3;

const hmm_a: vec3 = .{ 1, 1, 1 };
const hmm_b: vec3 = .{ 2, 2, 2 };
const hmm_c = hmm_a + hmm_b;

pub const U = 0;
pub const V = 1;

pub const X = 0;
pub const Y = 1;
pub const Z = 2;

pub const R = 0;
pub const G = 1;
pub const B = 2;
pub const A = 3;

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

pub fn WResolveType(comptime w: u8) type {
    return switch (w) {
        2 => vec2,
        3 => vec3,
        4 => vec4,
        else => unreachable,
    };
}
pub fn zero(comptime w: u8) WResolveType(w) {
    return switch (w) {
        2 => .{ 0, 0 },
        3 => .{ 0, 0, 0 },
        4 => .{ 0, 0, 0, 0 },
        else => unreachable,
    };
}

test "well is this is zero" {
    try std.testing.expectEqual(zero(3), zero3());
}

pub fn zero3() vec3 {
    return .{ 0, 0, 0 };
}
pub fn zero4() vec4 {
    return .{ 0, 0, 0, 0 };
}

pub fn stack4(a: vec3, b: f32) vec4 {
    return .{ a[0], a[1], a[2], b };
}

pub fn asPix(srgb: vec3) uvec4 {
    const srgb_ar: [3]f32 = srgb;
    return .{
        @intFromFloat(srgb_ar[0] * 255),
        @intFromFloat(srgb_ar[1] * 255),
        @intFromFloat(srgb_ar[2] * 255),
        255,
    };
}

pub inline fn splat4d(a: f32) vec4 {
    return @splat(a);
}
pub inline fn splat3d(a: f32) vec3 {
    return @splat(a);
}
pub inline fn splat2d(a: f32) vec2 {
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

pub const vec3u = extern union {
    vec: vec3,
    arr: [3]f32,
};

const mat4u = extern union {
    mat: mat4,
    arr: [16]f32,
    rmat: rmath.struct_Matrix,
};
const mat3u = extern union {
    mat: mat3,
    arr: [12]f32,
};

test "do mat3 take 12b of space?" {
    try std.testing.expectEqual(12 * 4, @sizeOf(mat3u));
}

pub fn matXvec3(m: mat3, v: [3]f32) [3]f32 {
    var out: vec3 = m[0] * splat3d(v[0]);
    for (1..3) |i| out += m[i] * splat3d(v[i]);
    return out;
}

pub fn matXvec(m: mat4, v: [4]f32) [4]f32 {
    var out: vec4 = m[0] * splat4d(v[0]);
    for (1..4) |i| out += m[i] * splat4d(v[i]);
    return out;
}

test "|mat_mul_vec" {
    const v = vec3{ 8, -2, 1 };
    const b = matXvec(matIden().mat, stack4(v, 1));

    try std.testing.expect(len(v - trim3d(b)) < 0.001);
}

pub fn matXmat3(m_a: mat3, m_b: mat3) mat3u {
    return .{
        .mat = .{
            matXvec3(m_a, m_b[0]), //column-major
            matXvec3(m_a, m_b[1]),
            matXvec3(m_a, m_b[2]),
        },
    };
}
pub fn matXmat(m_a: mat4, m_b: mat4) mat4u {
    return .{
        .mat = .{
            matXvec(m_a, m_b[0]), //column-major
            matXvec(m_a, m_b[1]),
            matXvec(m_a, m_b[2]),
            matXvec(m_a, m_b[3]),
        },
    };
}

test "|mat_mul_mat" {
    const a: vec3 = .{ 1, 3, 5 };
    const b: vec3 = .{ -2, 12, -5 };
    const c = a + b;

    const m_a = matTrans(a);
    const m_b = matTrans(b);
    const C = matXmat(m_a.mat, m_b.mat);

    const x = vec4{ 0, 0, 0, 1 };
    const y = matXvec(C.mat, x);

    var e: [3]f32 = c - trim3d(y);
    for (0..3) |i| e[i] = abs(e[i]);

    try std.testing.expect(@reduce(.Add, @as(vec3, e)) < 0.001);
}

pub fn norm(v: vec3) vec3 {
    return v / @as(vec3, @splat(len(v)));
}

pub fn matIden() mat4u {
    return mat4u{
        .mat = .{
            .{ 1, 0, 0, 0 }, //column-major
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

pub fn matTrans(t: vec3) mat4u {
    return mat4u{
        .mat = .{
            .{ 1, 0, 0, 0 }, //column-major
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ t[0], t[1], t[2], 1 },
        },
    };
}

pub fn matScale(s: vec3) mat4u {
    return mat4u{
        .mat = .{
            .{ s[0], 0, 0, 0 }, //column-major
            .{ 0, s[1], 0, 0 },
            .{ 0, 0, s[2], 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

test "|point_moved" {
    const a = vec3{ 1, 2, 3 };
    const b = vec3{ -1, 7, 18 };
    const assumed = a + b;
    const mat = matTrans(a);
    const t = matXvec(mat.mat, stack4(b, 1));

    std.debug.print("translate \n", .{});
    std.debug.print("t {}\n", .{@as(vec4, t)});

    var e: [3]f32 = assumed - trim3d(t);
    for (0..3) |i| e[i] = abs(e[i]);
    try std.testing.expect(@reduce(.Add, @as(vec3, e)) < 0.001);
}

pub fn lookRotation(pos: vec3, target: vec3, ref_up: vec3) mat4u {
    const delta = target - pos;
    const forward = norm(delta);
    if (abs(dot(forward, ref_up)) > 0.95) {
        @panic("singularity");
    }

    const right = norm(cross(ref_up, forward));
    const up = cross(forward, right);

    return .{
        .mat = .{
            // ratation transposition
            stack4(.{ right[X], up[X], forward[X] }, 0), //column-major
            stack4(.{ right[Y], up[Y], forward[Y] }, 0),
            stack4(.{ right[Z], up[Z], forward[Z] }, 0),
            stack4(zero3(), 1),
        },
    };
}

pub fn matOrtho(right: f32, left: f32, up: f32, down: f32, far: f32, near: f32) mat4u {
    const w = right - left;
    const h = down - up; // Vk has -Y axis
    const d = (far - near);
    return mat4u{
        .mat = .{
            .{ 2 / w, 0, 0, 0 }, // column-major
            .{ 0, 2 / h, 0, 0 },
            .{ 0, 0, 1 / d, 0 },
            .{ -(right + left) / w, -(down + up) / h, -near / d, 1 },
        },
    };
}
pub fn matDeepOrtho(right: f32, left: f32, up: f32, down: f32) mat4u {
    // depth enough is fine right now
    return matOrtho(right, left, up, down, 1000, -1000);
}

pub fn mat_ortho_default() mat4u {
    const scale = 1;
    return matOrthoUni(scale);
}

pub fn matOrthoUni(scale: f32) mat4u {
    // from up down depends, y axis flip in vulkan
    return matOrtho(scale, -scale, scale, -scale, scale, -scale);
}

pub fn matOrthoShift(scale: f32, shift: vec3) mat4u {
    const x, const y, _ = shift;
    return matDeepOrtho(x + scale, x - scale, y + scale, y - scale);
}

test "|ortho_to_vulkan" {
    const x0 = vec3{ 10, 10, 1 };
    const x1 = vec3{ 5, 5, -1 };
    const y0 = vec3{ 1, -1, 1 };
    const y1 = vec3{ -1, 1, 0 };

    const M1 = matOrtho(10, 5, 10, 5, 1, -1);
    const v0 = matXvec(M1.mat, stack4(x0, 1));
    const v1 = matXvec(M1.mat, stack4(x1, 1));
    try std.testing.expect(len(y0 - trim3d(v0)) < 0.001);
    try std.testing.expect(len(y1 - trim3d(v1)) < 0.001);

    const x2: vec3 = .{ 1, 1, 1 };
    const x3: vec3 = .{ -1, -1, -1 };
    const y2 = vec3{ 1, -1, 1 };
    const y3 = vec3{ -1, 1, 0 };

    const M2 = mat_ortho_default();
    const v2 = matXvec(M2.mat, stack4(x2, 1));
    const v3 = matXvec(M2.mat, stack4(x3, 1));
    try std.testing.expect(len(y2 - trim3d(v2)) < 0.001);
    try std.testing.expect(len(y3 - trim3d(v3)) < 0.001);
}
pub fn matPersp(width: f32, height: f32, fov: f32, near: f32, far: f32) mat4u {
    std.debug.assert(height != 0);

    const aspect = width / height;
    const tan_val = std.math.tan(fov / 2);
    const depth = far - near;
    return mat4u{
        .mat = .{
            .{ 1 / (aspect * tan_val), 0, 0, 0 }, //column-major
            .{ 0, -1 / tan_val, 0, 0 },
            .{ 0, 0, far / depth, 1 },
            .{ 0, 0, -far * near / depth, 0 },
        },
    };
}

pub fn matPerspDef() mat4u {
    return matPersp(4, 3, std.math.pi / 2.0, 0.1, 10);
}

test "|persp_to_vulkan" {
    const x0 = .{ 1, 0, 1, 1 };
    const x1 = .{ 1, 0, 8, 1 };

    const M1 = matPerspDef().mat;

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

pub fn matLookAt(pos: vec3, target: vec3, ref_up: vec3) !mat4u {
    const alt = true;
    switch (alt) {
        true => {
            const from_rl = rmath.MatrixLookAt(
                rvec3(pos),
                rvec3(target),
                rvec3(ref_up),
            );

            const alt_result: mat4u = .{ .rmat = from_rl };
            return alt_result;
        },
        false => {
            const trans = matTrans(-pos);
            const rot = lookRotation(pos, target, ref_up);
            return matXmat(rot.mat, trans.mat);
        },
    }
}

const UP = vec3{ 0, 1, 0 };

fn rvec3(v3: vec3) rmath.struct_Vector3 {
    return rmath.struct_Vector3{ .x = v3[0], .y = v3[1], .z = v3[2] };
}

test "is_matrix_looking" {
    const observ = vec3{ -1, 1, -1 };

    const M = 0;
    const Ri = 1;
    const _U = 2;
    const target = vec3{ 1, 0, 1 };
    const target_right = vec3{ 1.1, 0, 1 };
    const target_upper = vec3{ 1, 0.1, 1 };

    const transform = try matLookAt(observ, target, UP);
    const r_ref_transform = rmath.MatrixLookAt(
        rvec3(observ),
        rvec3(target),
        rvec3(UP),
    );
    std.debug.print("custom look_at {any}\n", .{transform.arr});
    std.debug.print("raylib look_at {any}\n", .{r_ref_transform});
    var outs: [3]vec4 = undefined;
    const to_transform: [3]vec3 = .{ target, target_right, target_upper };
    for (to_transform, 0..) |x, i| {
        outs[i] = matXvec(transform.mat, stack4(x, 1));
    }

    std.debug.print("---\n", .{});
    std.debug.print("middle one {}\n", .{outs[M]});
    std.debug.print("right one  {}\n", .{outs[Ri]});
    std.debug.print("left one   {}\n", .{outs[_U]});
    try std.testing.expect(abs(outs[M][X]) < 0.001);
    try std.testing.expect(abs(outs[M][Y]) < 0.001);

    try std.testing.expect(outs[M][X] < outs[Ri][X]); //should be on right
    try std.testing.expect(outs[M][Y] < outs[U][Y]); //should be higher
}

pub inline fn orbit(phi: f32) vec3 {
    return .{ std.math.cos(phi), 0, -std.math.sin(phi) };
}
pub inline fn orbit_r(phi: f32, r: f32) vec3 {
    return vec3{ std.math.cos(phi), 0, -std.math.sin(phi) } * splat3d(r);
}

pub fn rotMatY(part: f32) mat3 {
    const x: vec3 = .{ 1, 0, 0 };
    const z: vec3 = .{ 0, 0, 1 };

    const radians = part * std.math.tau;

    const sin = std.math.sin(radians);
    const cos = std.math.cos(radians);

    const x_ = splat3d(cos) * x + splat3d(sin) * z;
    const z_ = -splat3d(sin) * x + splat3d(cos) * z;
    return .{
        x_,
        .{ 0, 1, 0 },
        z_,
    };
}

pub fn rotMatX(part: f32) mat3 {
    const y: vec3 = .{ 0, 1, 0 };
    const z: vec3 = .{ 0, 0, 1 };

    const radians = part * std.math.tau;

    const sin = std.math.sin(radians);
    const cos = std.math.cos(radians);

    const z_ = splat3d(cos) * z + splat3d(sin) * y;
    const y_ = -splat3d(sin) * z + splat3d(cos) * y;
    return .{
        .{ 1, 0, 0 },
        y_,
        z_,
    };
}

// conversions
pub inline fn uinty(val: anytype) u32 {
    return @as(u32, @intCast(val));
}
pub inline fn u16ty(val: anytype) u16 {
    return @as(u16, @intCast(val));
}

pub inline fn floaty(usz: anytype) f32 {
    return @as(f32, @floatFromInt(usz));
}

pub inline fn radial(phi: f32, r: f32) vec2 {
    return .{ @cos(phi) * r, @sin(phi) * r };
}

pub inline fn trygZero1(val: f32) f32 {
    return (val + 1) * 0.5;
}

pub inline fn tryg2u16f(val: f32) f32 {
    return ((val + 1) * 0.5 * ((1 << 16) - 3) + 1);
}

pub inline fn v2One() vec2 {
    return .{ 1, 1 };
}

pub inline fn v2Zero() vec2 {
    return .{ 1, 1 };
}

pub fn vkextAsV2(vkext: vk.Extent2D) vec2 {
    return .{
        floaty(vkext.width),
        floaty(vkext.height),
    };
}

pub fn top(v: vec2) u8 {
    return if (v[X] > v[Y]) X else Y;
}
