const m = @import("../math.zig");
pub const MatPack = extern struct {
    model: [16]f32 = m.mat_identity().arr,
    view: [16]f32 = m.mat_identity().arr,
    proj: [16]f32 = m.mat_identity().arr,
};

pub const GroupData = extern struct {
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
    offset_4d: [4]f32 = undefined,
    depth_ctrl: [4]f32 = undefined,
};

const DepthControl = extern struct {
    gate: f32,
    level: f32,
    not_used_0: f32,
    not_used_1: f32,
};

pub const GridSize = struct {
    total: u32,
    w: u16,
    h: u16,

    pub const default: GridSize = .{
        .w = 32,
        .h = 32,
        .total = 1024,
    };

    pub const g64: GridSize = .{
        .w = 64,
        .h = 64,
        .total = 4096,
    };
};
