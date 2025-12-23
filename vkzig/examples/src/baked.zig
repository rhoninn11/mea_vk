const vk = @import("third_party/vk.zig");

pub const DSetInit = struct {
    usage: UsageType,
    memory_property: vk.MemoryPropertyFlags,
    shader_stage: vk.ShaderStageFlags,
};

pub const UsageType = struct {
    usage_flag: vk.BufferUsageFlags,
    descriptor_type: vk.DescriptorType,
};

const uniform_usage: UsageType = .{
    .usage_flag = .{
        .uniform_buffer_bit = true,
    },
    .descriptor_type = .uniform_buffer,
};
const storage_usage: UsageType = .{
    .usage_flag = .{
        .storage_buffer_bit = true,
    },
    .descriptor_type = .storage_buffer,
};

const cpu_accesible_memory: vk.MemoryPropertyFlags = .{
    .host_visible_bit = true,
    .host_coherent_bit = true,
};

pub const uniform_frag_vert = DSetInit{
    .usage = uniform_usage,
    .memory_property = cpu_accesible_memory,
    .shader_stage = .{
        .vertex_bit = true,
        .fragment_bit = true,
    },
};
pub const storage_frag_vert = DSetInit{
    .usage = storage_usage,
    .memory_property = cpu_accesible_memory,
    .shader_stage = .{
        .vertex_bit = true,
        .fragment_bit = true,
    },
};

pub const UniformInfo = struct {
    location: u32,
    size: u32,
};
