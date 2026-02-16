const UniformData = extern struct {
    osc_scale: [2]f32,
    scale_2d: [2]f32,
    not_used_4d_0: [4]f32,
    termoral: [4]f32,
    not_used_4d_1: [4]f32,
};

const PerInstanceData = extern struct {
    offset_2d: [2]f32,
    other_offsets: [2]f32,
    new_usage: [4]f32,
    not_used_4d_0: [4]f32,
    not_used_4d_1: [4]f32,
};

const m = @import("math.zig");
pub const MatPack = struct {
    model: [16]f32 = m.mat_identity().arr,
    view: [16]f32 = m.mat_identity().arr,
    proj: [16]f32 = m.mat_identity().arr,
};

pub const GroupData = struct {
    // ||| added uniform, storage and texture
    osc_scale: [2]f32 = undefined,
    scale_2d: [2]f32 = undefined,
    not_used_4d_0: [4]f32 = undefined,
    termoral: [4]f32 = undefined,
    not_used_4d_1: [4]f32 = undefined,
    // 16B alignment
    matrices: MatPack = undefined,
};

pub const PerInstance = struct {
    offset_2d: [2]f32 = undefined,
    other_offsets: [2]f32 = undefined,
    new_usage: [4]f32 = undefined,
    empty_rest: [8]f32 = undefined,
};
