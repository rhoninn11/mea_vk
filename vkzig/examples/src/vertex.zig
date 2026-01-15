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
            .format = .r32g32b32_sfloat,
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

    pos: [3]f32,
    color: [3]f32,

    pub fn Ring(alloc: std.mem.Allocator, len: u8) !std.ArrayList(Vertex) {
        const PreStage = struct {
            pos: [2]f32,
            progress: f32,
            v: f32,
        };

        const vert_num: usize = @as(usize, len) * 2;

        var stage_arr: std.ArrayList(PreStage) = .empty;
        try stage_arr.resize(alloc, vert_num);
        defer stage_arr.deinit(alloc); //intermediate cals

        var stage_0 = stage_arr.items;
        for (0..len) |i| {
            const flen: f32 = @floatFromInt(len - 1);
            const fi: f32 = @floatFromInt(i);
            const progress = fi / flen;

            const phi = std.math.tau * progress;
            var stamp = PreStage{
                .progress = progress,
                .pos = .{
                    std.math.cos(phi),
                    std.math.sin(phi),
                },
                .v = 0.0,
            };
            stage_0[i * 2] = stamp;
            stamp.v = 1.0;
            stage_0[i * 2 + 1] = stamp;
        }

        const r = 0.6;
        const r_delta = 0.3;
        for (0..len) |pre_i| {
            const stage_i = pre_i * 2;
            const base = stage_0[stage_i].pos;

            stage_0[stage_i].pos = mul2D(base, r);
            stage_0[stage_i + 1].pos = mul2D(base, r + r_delta);
        }

        const segments = len - 1;
        const vert_size = @as(usize, segments) * 6;

        var stage_vert_arr: std.ArrayList(Vertex) = .empty;
        try stage_vert_arr.resize(alloc, vert_size);
        var stage_vert = stage_vert_arr.items;
        // const delta: [2]f32 = .{ 0.05, 0.07 };
        // var off: [2]f32 = .{ 0, 0 };

        for (0..segments) |pre_i| {
            const tri_pair_i = pre_i * 6;
            const pos_i = pre_i * 2;

            const pos_offs = [_]u8{ 0, 1, 2, 2, 1, 3 };
            for (pos_offs, 0..) |pos_off, jj| {
                const stage = stage_0[pos_i + pos_off];
                stage_vert[tri_pair_i + jj] = .{
                    .pos = .{ stage.pos[0], stage.pos[1], 0 },
                    .color = .{ stage.progress, stage.v, 0 },
                };
            }
        }
        return stage_vert_arr;
    }
};

pub const VertexAlt1 = struct {
    pos: [3]f32,
};

pub const VertexAlt2 = struct {
    pos: [5]f32,
};

fn tinkering(ToProbe: type) void {
    std.debug.print("{s} | size {d}, aligments {d}\n", .{ @typeName(ToProbe), @sizeOf(ToProbe), @alignOf(ToProbe) });
}
pub fn probing() void {
    tinkering(VertexAlt1);
    tinkering(VertexAlt2);
}
