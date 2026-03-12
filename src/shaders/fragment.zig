const std = @import("std");
const shm = @import("shm.zig");
const gpu = std.gpu;

extern const v_color: shm.vec3 addrspace(.input);
extern const v_progress: f32 addrspace(.input);

extern var f_color: shm.vec4 addrspace(.output);

export fn main() callconv(.spirv_fragment) void {
    gpu.location(&v_color, 0);
    gpu.location(&v_color, 1);

    gpu.location(&f_color, 0);

    const red: shm.vec3 = .{ 1, 0, 0 };
    const col = red * shm.splat3d(v_color[0]);

    f_color = .{ col[0], col[1], col[2], 1.0 };
}
