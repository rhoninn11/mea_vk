const std = @import("std");
const sht = @import("types.zig");
const shm = @import("shm.zig");
const gpu = std.gpu;

// a_ attributes
extern const a_pos: shm.vec3 addrspace(.input);
extern const a_color: @Vector(3, f32) addrspace(.input);

extern var v_color: @Vector(3, f32) addrspace(.output);
extern var v_progress: f32 addrspace(.output);

extern const u_data: sht.GroupData addrspace(.uniform);
extern const s_data: [*]sht.PerInstance addrspace(.storage_buffer);

//but for texture sampling i need to use asm inline (spirv asm?)

export fn main() callconv(.spirv_vertex) void {
    //in
    gpu.location(&a_pos, 0);
    gpu.location(&a_color, 1);

    //out
    gpu.location(&v_color, 0);
    gpu.location(&v_progress, 1);

    //dsets
    gpu.binding(&u_data, 0, 0);
    gpu.binding(s_data.ptr, 1, 0);

    const i = gpu.instance_index;
    const m_inst: sht.PerInstance = s_data.ptr[i];

    const prescale_pos = a_pos * shm.splat3d(u_data.scale_2d.x);
    const inst_offset = m_inst.offset_4d;

    // ciekawe jak się dostać do bindinga...

    const moved = prescale_pos + shm.xyz(inst_offset);
    gpu.position_out.* = .{ moved[0], moved[1], moved[2], 1.0 };

    // uv
    v_color[0] = a_color[0];
    v_color[1] = a_color[1];

    v_progress = a_color[0];
}
