const std = @import("std");
const vk = @import("third_party/vk.zig");
const before = @import("before.zig");

const X = 0;
const Y = 1;
fn mul2D(a: [2]f32, times: f32) [2]f32 {
    return .{ a[X] * times, a[Y] * times };
}

fn add(a: [2]f32, b: [2]f32) [2]f32 {
    return .{ a[X] + b[X], a[Y] + b[Y] };
}

pub const Vertex = struct {
    pub const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    pub const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "color"),
        },
    };
    const Self = @This();
    pub const GeoRaw = []Self;
    pub const s_fields_num = before.structDeclNum(Self);

    pos: [2]f32,
    color: [3]f32,

    pub fn Ring(alloc: std.mem.Allocator, len: u8) !std.ArrayList(Vertex) {
        const vert_num: usize = @as(usize, len) * 2;

        const PreStage = struct {
            pos: [2]f32,
            progres: f32,
        };
        var stage_arr: std.ArrayList(PreStage) = .empty;
        try stage_arr.resize(alloc, vert_num);
        defer stage_arr.deinit(alloc);

        var stage_slice = stage_arr.items;
        for (0..len) |i| {
            const flen: f32 = @floatFromInt(len - 1);
            const fi: f32 = @floatFromInt(i);
            const progress = fi / flen;

            const phi = std.math.tau * progress;
            const stamp = PreStage{
                .progres = progress,
                .pos = .{
                    std.math.cos(phi),
                    std.math.sin(phi),
                },
            };
            stage_slice[i * 2] = stamp;
            stage_slice[i * 2 + 1] = stamp;
        }

        const r = 0.6;
        const r_delta = 0.3;
        for (0..len) |pre_i| {
            const stage_i = pre_i * 2;
            const base = stage_slice[stage_i].pos;

            stage_slice[stage_i].pos = mul2D(base, r);
            stage_slice[stage_i + 1].pos = mul2D(base, r + r_delta);
        }

        const segments = len - 1;
        const vert_size = @as(usize, segments) * 6;
        var vert_arr: std.ArrayList(Vertex) = .empty;
        try vert_arr.resize(alloc, vert_size);

        var vert_here = vert_arr.items;
        // const delta: [2]f32 = .{ 0.05, 0.07 };
        // var off: [2]f32 = .{ 0, 0 };

        for (0..segments) |pre_i| {
            const tri_pair_i = pre_i * 6;
            const pos_i = pre_i * 2;

            const pos_offs = [_]u8{ 0, 1, 2, 2, 1, 3 };
            for (pos_offs, 0..) |pos_off, jj| {
                const stage = stage_slice[pos_i + pos_off];
                vert_here[tri_pair_i + jj] = .{
                    .pos = stage.pos,
                    .color = .{ stage.progres, 0, 0 },
                };
            }
        }
        return vert_arr;
    }
};
