const vk = @import("third_party/vk.zig");
const m = @import("math.zig");
const gput = @import("shaders/types.zig");

pub const TransitPrep = struct {
    const Stages = struct {
        src: vk.PipelineStageFlags,
        dst: vk.PipelineStageFlags,
    };
    const Accesses = struct {
        src: vk.AccessFlags,
        dst: vk.AccessFlags,
    };

    stages: Stages,
    accesses: Accesses,
};

pub const ImgLTranConfig = struct {
    image: vk.Image,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    flags: TransitPrep,
};

pub const Player = struct {
    phi: f32,
    h: f32,
    r: f32,
};
