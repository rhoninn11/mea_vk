const std = @import("std");
const vk = @import("third_party/vk.zig");
const before = @import("before.zig");
const m = @import("math.zig");

const X = 0;
const Y = 1;
const Z = 2;

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

    const Multipler = struct {
        times_one: u32,
        times_vert: u32,
    };

    pub const Stamp = struct {
        pos: [3]f32,
        progress: f32,
        v: f32,
    };

    pub fn Ring(alloc: std.mem.Allocator, len: u8) !std.ArrayList(Vertex) {
        const group = Multipler{
            .times_one = @intCast(len),
            .times_vert = @intCast(len * 2),
        };
        _ = group;

        const vert_num: usize = @as(usize, len) * 2;

        var stage_arr: std.ArrayList(Stamp) = .empty;
        try stage_arr.resize(alloc, vert_num);
        defer stage_arr.deinit(alloc); //intermediate cals

        var staged_stamps = stage_arr.items;
        for (0..len) |i| {
            // const flen: f32 = @floatFromInt(len - 1);
            // const fi: f32 = @floatFromInt(i);
            const progress = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(len - 1));

            const phi = std.math.tau * progress;
            const stamp_a = Stamp{
                .progress = progress,
                .pos = .{
                    std.math.cos(phi),
                    std.math.sin(phi),
                    0,
                },
                .v = 0.0,
            };
            var stamp_b = stamp_a;
            stamp_b.v = 1.0;
            stamp_b.pos[Z] = 0.75;

            staged_stamps[i * 2] = stamp_a;
            staged_stamps[i * 2 + 1] = stamp_b;
        }

        const r = 0.6;
        const r_delta = 0.3;
        for (0..len) |pre_i| {
            const stage_i = pre_i * 2;
            const base: [2]f32 = staged_stamps[stage_i].pos[0..2].*;

            staged_stamps[stage_i].pos = m.stack(m.mul2D(base, r), 0.75);
            staged_stamps[stage_i + 1].pos = m.stack(m.mul2D(base, r + r_delta), 0);
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
                const stage = staged_stamps[pos_i + pos_off];
                stage_vert[tri_pair_i + jj] = .{
                    .pos = .{
                        stage.pos[X],
                        stage.pos[Y],
                        stage.pos[Z],
                    },
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
