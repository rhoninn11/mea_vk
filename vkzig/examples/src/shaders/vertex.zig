const std = @import("std");
const gpu = std.gpu;

extern const a_pos: @Vector(2, f32) addrspace(.input);
extern const a_color: @Vector(3, f32) addrspace(.input);

extern var v_color: @Vector(3, f32) addrspace(.output);

const UniformData = extern struct {
    osc_scale: [2]f32,
    scale_2d: [2]f32,
    not_used_4d_0: [4]f32,
    termoral: [4]f32,
    not_used_4d_1: [4]f32,
};

const PerInstanceData = struct {
    offset_2d: [2]f32,
    other_offsets: [2]f32,
    new_usage: [4]f32,
    not_used_4d_0: [4]f32,
    not_used_4d_1: [4]f32,
};

extern const u_data: UniformData addrspace(.uniform);
extern const s_data: [*]PerInstanceData addrspace(.storage_buffer);

//but for texture sampling i need to use asm inline (spirv asm?)

export fn main() callconv(.spirv_vertex) void {
    gpu.location(&a_pos, 0);
    gpu.location(&a_color, 1);
    gpu.location(&v_color, 0);

    gpu.binding(&u_data, 0, 0);
    gpu.binding(s_data.ptr, 2, 0);

    gpu
        .

        // ciekawe jak się dostać do bindinga...

        gpu.position_out.* = .{ a_pos[0], a_pos[1], 0.0, 1.0 };
    v_color = a_color;
}
