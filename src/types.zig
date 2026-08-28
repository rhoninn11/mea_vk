const vk = @import("vulkan-zig");
const m = @import("math.zig");
const gput = @import("shaders/types.zig");
const sht = @import("shaders/types.zig");

// TODO: group by src/dst not stage/access
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

pub const SyncPrep = struct {
    const SyncPoint = struct {
        stage: vk.PipelineStageFlags,
        access: vk.AccessFlags,
    };

    src: SyncPoint,
    dst: SyncPoint,
};

pub const ImgLTranConfig = struct {
    image: vk.Image,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    sync_point: SyncPrep,
};

pub const Player = struct {
    phi: f32,
    h: f32,
    r: f32,
};

pub const Ray = struct {
    up: m.vec3 = .{ 0, 1, 0 },
    at: m.vec3,
    to: m.vec3,
};
