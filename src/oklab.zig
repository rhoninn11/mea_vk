const std = @import("std");
const source = @import("third_party/oklab.zig");
const m = @import("math.zig");
const dset = @import("dset.zig");
const sht = @import("shaders/types.zig");
const addons = @import("addons.zig");

pub fn srgb_to_oklab(srgb: m.vec3) m.vec3 {
    const lms_conv: [3]m.vec3 = .{
        .{ 0.4122214708, 0.5363325363, 0.0514459929 },
        .{ 0.2119034982, 0.6806995451, 0.1073969566 },
        .{ 0.0883024619, 0.2817188376, 0.6299787005 },
    };
    var lms: m.vec3 = undefined;
    for (0..3) |i| lms[i] = m.dot(lms_conv[i], srgb);
    for (0..3) |i| lms[i] = std.math.cbrt(lms[i]);

    const lab_conv: [3]m.vec3 = .{
        .{ 0.2104542553, 0.7936177850, -0.0040720468 },
        .{ 1.9779984951, -2.4285922050, 0.4505937099 },
        .{ 0.0259040371, 0.7827717662, -0.8086757660 },
    };
    var lab: m.vec3 = undefined;
    for (0..3) |i| lab[i] = m.dot(lab_conv[i], lms);

    return lab;
}

pub fn oklab_to_srgb(lab: m.vec3) m.vec3 {
    const lms_conv: [3]m.vec3 = .{
        .{ 1, 0.3963377774, 0.2158037573 },
        .{ 1, -0.1055613458, -0.0638541728 },
        .{ 1, -0.0894841775, -1.2914855480 },
    };

    var lms: m.vec3 = undefined;
    for (0..3) |i| lms[i] = m.dot(lms_conv[i], lab);
    for (0..3) |i| lms[i] = lms[i] * lms[i] * lms[i];

    const srgb_conv: [3]m.vec3 = .{
        .{ 4.0767416621, -3.3077115913, 0.2309699292 },
        .{ -1.2684380046, 2.6097574011, -0.3413193965 },
        .{ -0.0041960863, -0.7034186147, 1.7076147010 },
    };

    var srgb: m.vec3 = undefined;
    for (0..3) |i| srgb[i] = m.dot(srgb_conv[i], lms);
    return srgb;
}

pub fn demo() void {
    const rgbs: [3]m.vec3 = .{
        .{ 1, 0, 0 },
        .{ 0, 1, 0 },
        .{ 0, 0, 1 },
    };
    var labs: [3]m.vec3 = undefined;
    for (0..3) |i| labs[i] = srgb_to_oklab(rgbs[i]);
    // std.debug.print("-------", .{});
    // for (0..3) |i| std.debug.print("+++ srgb: {} -> lab: {}\n", .{ rgbs[i], labs[i] });
    // std.debug.print("-------", .{});

    const L: f32 = 0.37;
    const C: f32 = 0.15;
    const delta: f32 = 0.026;
    const steps: u8 = 32;
    // std.debug.print("|-------\n", .{});
    for (0..steps) |i| {
        const phase = m.floaty(i) * delta * std.math.tau;
        const a = C * @cos(phase);
        const b = C * @sin(phase);
        const lab: m.vec3 = .{ L, a, b };
        const rgb: m.vec3 = oklab_to_srgb(lab);
        // std.debug.print("phase {} | lab: {} -> srgb {}\n", .{ m.floaty(i) * delta * 360, lab, rgb });
        _ = rgb;
    }
    // std.debug.print("|-------\n", .{});

    const r_delta: f32 = 1 / m.floaty(steps);
    for (0..3) |jj| {
        for (0..steps) |i| {
            const rdv = m.splat3d(m.floaty(i) * r_delta);
            var srgb: m.vec3 = .{ 0, 0, 0 };
            srgb[jj] = 1;
            srgb *= rdv;
            const lab = srgb_to_oklab(srgb);
            // std.debug.print("srgb: {} -> lab {}\n", .{ srgb, lab });
            _ = lab;
        }
    }
}

const U16max: f32 = 1 << 16;
pub const OkUnderstanding = struct {
    grid: sht.GridSize,

    pub fn splatSpace(self: *const OkUnderstanding, storage_dset: dset.DescriptorPrep) !void {
        const total = self.grid.total;
        const lim_num = 8096;
        std.debug.assert(total <= lim_num);

        const stack_size = lim_num * @sizeOf(sht.PerInstance);
        var stack_mem: [stack_size]u8 = undefined;

        var provider: std.heap.FixedBufferAllocator = .init(&stack_mem);
        const local_a = provider.allocator();

        var scratchpad = try local_a.alloc(sht.PerInstance, total);
        for (storage_dset.buff_arr.items) |possible_buffer| {
            const storage = possible_buffer.?;
            const mapping: [*]sht.PerInstance = @ptrCast(@alignCast(storage.mapping.?));
            @memcpy(scratchpad, mapping);
            var phase: f32 = 0;

            const chroma: f32 = 0.2;
            // L 0-1 -> just progress over iteration
            const l_delt: f32 = 1.0 / @as(f32, @floatFromInt(self.grid.total - 1));
            var l: f32 = -l_delt;
            const phase_delt: f32 = 0.01;
            for (0..total) |i| {
                l += l_delt;
                const lab: m.vec3 = .{
                    l,
                    chroma * @cos(std.math.tau * phase),
                    chroma * @sin(std.math.tau * phase),
                };
                phase += phase_delt;
                var srgb_pos = oklab_to_srgb(lab);
                var inst_data: sht.PerInstance = scratchpad[i];
                const clamp_lim: f32 = 2;
                for (0..3) |jj| {
                    if (srgb_pos[jj] < 0) srgb_pos[jj] = 0;
                    if (srgb_pos[jj] > clamp_lim) srgb_pos[jj] = clamp_lim;
                }

                inst_data.offset_4d = .{ srgb_pos[0], srgb_pos[1], srgb_pos[2], 0 };
                inst_data.depth_ctrl[0] = 2;
                inst_data.depth_ctrl[1] = 0;

                scratchpad[i] = inst_data;
            }
            @memcpy(mapping, scratchpad);
        }
    }

    pub fn sampleSpace(alloc: std.mem.Allocator, L: f32, g: *const sht.GridSize) ![]u8 {
        const texture_mem = try alloc.alloc(u8, g.total * @sizeOf(u32));

        const mid = addons.GridOps.middle2D(g);
        const chroma = 0.05;
        var invalid_pixels: u32 = 0;
        for (0..g.h) |yy| {
            for (0..g.w) |x| {
                const idx: m.vec2 = .{ @as(f32, @floatFromInt(x)), @as(f32, @floatFromInt(yy)) };
                var ab = idx - mid;
                ab /= m.splat2d(3.5);
                ab *= m.splat2d(chroma);
                const srgb = oklab_to_srgb(.{ L, ab[0], ab[1] });
                var valid = true;
                for (0..3) |i| valid = valid and (srgb[i] > 0) and (srgb[i] <= 1);

                const mem_idx = (yy * g.w + x) * 4;
                if (valid) {
                    texture_mem[mem_idx] = @intFromFloat(srgb[0] * 255);
                    texture_mem[mem_idx + 1] = @intFromFloat(srgb[1] * 255);
                    texture_mem[mem_idx + 2] = @intFromFloat(srgb[2] * 255);
                    texture_mem[mem_idx + 3] = 255;
                } else {
                    invalid_pixels += 1;
                    texture_mem[mem_idx] = 0;
                    texture_mem[mem_idx + 1] = 0;
                    texture_mem[mem_idx + 2] = 0;
                    texture_mem[mem_idx + 3] = 0;
                }
            }
        }
        //alpha-to-coverage: https://www.youtube.com/watch?v=ltvI_gatbic
        const cover: u32 = ((g.total - invalid_pixels) * 1000) / g.total;
        const cover_f: f32 = @as(f32, @floatFromInt(cover)) / 10;

        std.debug.print("+++ L {d:.2} c {d} | tex full {d:.2}%\n", .{ L, chroma, cover_f });

        return texture_mem;
    }
};
