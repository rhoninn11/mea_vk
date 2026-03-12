const m = @import("../math.zig");

pub const vec3 = m.vec3;
pub const vec4 = m.vec4;
pub const splat3d = m.splat3d;

pub fn xyz(rgba: f32[4]) vec3 {
    return .{ rgba[0], rgba[1], rgba[2] };
}
