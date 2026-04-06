const std = @import("std");

const m = @import("math.zig");
const sht = @import("shaders/types.zig");
const addons = @import("addons.zig");
const dsets = @import("dsets.zig");
const proto = @import("proto.zig");

pub fn perFrameUniformFill(
    uniform_dset: dsets.DescriptorPrep,
    frame_idx: u8,
    total_s: f32,
    camera: m.vec3,
    size: f32,
) !void {
    var stack_mem: [4096]u8 = undefined;
    var provider: std.heap.FixedBufferAllocator = .init(&stack_mem);
    const local_a = provider.allocator();

    const uniform = uniform_dset.buff_arr.items[frame_idx].?;
    const mapping: [*]sht.GroupData = @ptrCast(@alignCast(uniform.mapping.?));
    var scratchpad = try local_a.alloc(sht.GroupData, 2);
    defer @memcpy(mapping, scratchpad);

    for (0..scratchpad.len) |i| {
        scratchpad[i].osc_scale = .{ 0.1, 0.1 };
        scratchpad[i].scale = .{ size, size };
        scratchpad[i].termoral = .{ total_s, 0, 1, 2 };
    }
    const target: m.vec3 = .{ 0, 0, 0 };
    scratchpad[0].matrices = try addons.paramatricVariation(camera, target, true);
    scratchpad[1].matrices = try addons.paramatricVariation(camera, target, false);
}

pub fn storagePrefil(storage_dset: dsets.DescriptorPrep, grid: sht.GridSize, spacing: f32) !void {
    const instance_num = grid.total;
    const lim_num = 8096;
    std.debug.assert(instance_num <= lim_num);

    const along = 1 / @as(f32, @floatFromInt(instance_num - 1));
    const phase_delta = along * std.math.tau;
    const spread_base = 0;
    const spread_delta = along * 0.2;

    const stack_size = lim_num * (8 + @sizeOf(sht.PerInstance));
    std.debug.print("+++ info: prefil stack ~ {d}B\n", .{stack_size});
    var stack_mem: [stack_size]u8 = undefined;
    var provider: std.heap.FixedBufferAllocator = .init(&stack_mem);
    const local_a = provider.allocator();

    // const hmm = rnd_gen.float(f32);
    var storage_baker: std.ArrayList(f32) = .empty;
    try storage_baker.resize(local_a, instance_num);
    defer storage_baker.deinit(local_a);

    for (0..instance_num) |i| {
        const progress = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(instance_num - 1));
        storage_baker.items[i] = progress;
        storage_baker.items[i] = -0.125;
    }

    const middle = addons.Gridor.gridMiddle(&grid);
    const min_dim = if (middle[0] > middle[2]) middle[2] else middle[0];

    const wave_scale = 1.5;
    var scratchpad = try local_a.alloc(sht.PerInstance, instance_num);
    for (storage_dset.buff_arr.items) |possible_buffer| {
        const storage = possible_buffer.?;
        const mapping: [*]sht.PerInstance = @ptrCast(@alignCast(storage.mapping.?));
        defer @memcpy(mapping, scratchpad);

        for (0..instance_num) |i| {
            const i_f: f32 = @floatFromInt(i);

            // const y_d = (middle_alt[m.Z] - y_f) / middle_alt[m.Z];
            const g_idx = addons.Gridor.gridIdx(&grid, i);
            // if (g_idx[m.Z] > 0) {
            //     to_show = false;
            // }

            const delt = ((middle - g_idx) / m.splat3d(min_dim)) * m.splat3d(6 * wave_scale);
            // if (to_show) {
            //     std.debug.print("{} {} {} {}\n", .{ i_f, g_idx, middle, delt });
            // }
            const dist = std.math.sqrt(delt[m.X] * delt[m.X] + delt[m.Z] * delt[m.Z]);

            var fresh_one: sht.PerInstance = undefined;
            const pos_1 = (g_idx - middle) * m.splat3d(spacing);

            fresh_one.other_offsets[0] = i_f * phase_delta;
            fresh_one.other_offsets[1] = spread_base + i_f * spread_delta;
            fresh_one.new_usage[0] = storage_baker.items[i]; //offset on ring
            fresh_one.new_usage[1] = dist;
            fresh_one.new_usage[2] = g_idx[m.X];
            fresh_one.new_usage[3] = delt[m.X];
            fresh_one.offset_4d = m.stack4d(pos_1, 1);

            fresh_one.depth_ctrl[0] = 0;
            fresh_one.depth_ctrl[1] = 0;
            fresh_one.depth_ctrl[2] = i_f * 0.001;

            scratchpad[i] = fresh_one;
        }

        std.debug.print("\n", .{});
    }
}
