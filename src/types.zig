const vk = @import("third_party/vk.zig");
const m = @import("math.zig");
const gput = @import("shaders/types.zig");

pub const GroupData = gput.GroupData;
pub const PerInstance = gput.PerInstance;

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
    format: ?vk.Format = null,
    flags: TransitPrep,
};

pub const GridSize = struct {
    cell_num: u16,
    col_num: u8,
    row_num: u8,
};
