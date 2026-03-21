const std = @import("std");

const m = @import("math.zig");
const sht = @import("shaders/types.zig");
const addons = @import("addons.zig");
const proto = @import("proto.zig");

const DescriptorPrep = addons.DescriptorPrep;

pub fn perFrameUniformFill(uniform_dset: DescriptorPrep, frame_idx: u8, total_s: f32, center: m.vec3, size: f32) !void {
    const this_frame_uniform = uniform_dset.buff_arr.items[frame_idx].?;
    const as_group_data: *sht.GroupData = @ptrCast(@alignCast(this_frame_uniform.mapping.?));

    const scale_osc = std.math.sin(total_s) * 0.2 + 2;
    _ = scale_osc;

    as_group_data.*.osc_scale = .{ 0.1, 0.1 };
    as_group_data.*.scale = .{ size, size };
    as_group_data.*.termoral = .{ total_s, 0, 1, 2 };
    as_group_data.*.matrices = try addons.paramatricVariation(
        1,
        center,
        .{ 0, 0, 0 },
    );
}

pub fn storagePrefil(storage_dset: DescriptorPrep, grid: sht.GridSize, spacing: f32) !void {
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
    const wave_scale = 1.5;
    var scratchpad = try local_a.alloc(sht.PerInstance, instance_num);
    for (storage_dset.buff_arr.items) |possible_buffer| {
        for (0..instance_num) |i| {
            const i_f: f32 = @floatFromInt(i);

            // const y_d = (middle_alt[m.Z] - y_f) / middle_alt[m.Z];
            const g_idx = addons.Gridor.gridIdx(&grid, i);

            const delt = ((middle - g_idx) / middle) * m.splat3d(6 * wave_scale);
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

            scratchpad[i] = fresh_one;
        }
        const storage = possible_buffer.?;
        const mapping: [*]sht.PerInstance = @ptrCast(@alignCast(storage.mapping.?));
        @memcpy(mapping, scratchpad);

        std.debug.print("\n", .{});
    }
}
