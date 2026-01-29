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

const vec3u = union {
    vec: vec3,
    arr: [3]f32,
};

pub fn len(vec: vec3) f32 {
    const squared = vec[X] * vec[X] + vec[Y] * vec[Y] + vec[Z] * vec[Z];
    return std.math.sqrt(squared);
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
    const rl: [2]f32 = .{ 1, -1 }; //   right left
    const ud: [2]f32 = .{ -1, 1 }; //   up down     | vk has reversed y
    const @"fn": [2]f32 = .{ 1, 0 }; // far near
    return .{
        2 / diff(rl), 0,            0,                -sum(rl) / diff(rl), //
        0,            2 / diff(ud), 0,                -sum(ud) / diff(ud),
        0,            0,            -2 / diff(@"fn"), -sum(@"fn") / diff(@"fn"),
        0,            0,            0,                1,
    };
}

pub fn mat_look_at(from: vec3, at: vec3, up: vec3) [16]f32 {
    var forward = at - from;

    const d_len = len(forward);
    forward = forward / @as(vec3, @splat(d_len));

    const hmm: mat4 = .{
        stack4d(zero3(), from[X]),
        stack4d(zero3(), from[Y]),
        stack4d(forward, from[Z]),
        stack4d(zero3(), 1),
    };
    _ = hmm;
    _ = up;
    return mat_identity();
}
