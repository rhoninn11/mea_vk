const std = @import("std");
const m = @import("math.zig");

pub inline fn sawtooth(x: f32) f32 {
    const x_p = (x + std.math.tau * 0.25);
    const x_pp = x_p / (std.math.tau);
    return 2 * (x_pp - @floor(x_pp)) - 1;
}

pub fn wave(phase: f32, frac: f32) f32 {
    const ya = @sin(phase);
    const yb = sawtooth(phase);
    return m.lerp1(ya, yb, frac);
}
