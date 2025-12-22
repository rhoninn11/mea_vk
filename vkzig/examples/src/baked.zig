const vk = @import("third_party/vk.zig");

pub const DSetInit = struct {
    buffer_usage: vk.BufferUsageFlags,
    memory_property: vk.MemoryPropertyFlags,
    shader_stage: vk.ShaderStageFlags,
};

pub const u_vert = DSetInit{
    .buffer_usage = .{
        .uniform_buffer_bit = true,
    },
    .memory_property = .{
        .host_visible_bit = true,
        .host_coherent_bit = true,
    },
    .shader_stage = .{
        .vertex_bit = true,
    },
};

pub const u_frag_vert = blk: {
    var fragment_also = u_vert;
    fragment_also.shader_stage.fragment_bit = true;
    break :blk fragment_also;
};

pub const UniformInfo = struct {
    location: u32,
    size: u32,
};
