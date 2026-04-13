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
};

//side processing
const Allocator = std.mem.Allocator;
pub const PairPoint = struct {
    pos: [3]f32,
    progress: f32,
    v: f32,
};
const PairArray = std.ArrayList(PairPoint);
pub const TriangleArray = std.ArrayList(Vertex);

const tri_loops = [_]u8{ 0, 1, 2, 2, 1, 3 };
const quad: []const Vertex = &.{
    Vertex{ .pos = .{ 1, 0, -1 }, .color = .{ 1, 0, 0 } },
    Vertex{ .pos = .{ -1, 0, -1 }, .color = .{ 0, 0, 0 } },
    Vertex{ .pos = .{ 1, 0, 1 }, .color = .{ 1, 1, 0 } },
    Vertex{ .pos = .{ -1, 0, 1 }, .color = .{ 0, 1, 0 } },
};

pub const RingParams = struct {
    len: u8,
    inner_r: f32,
    outer_r: f32,
    flat: bool,

    pub const default: RingParams = .{
        .len = 9,
        .inner_r = 0.7,
        .outer_r = 1.0,
        .flat = true,
    };
};

pub const Utils = struct {
    pub const Math = struct {
        pub fn rotate(mat: m.mat3, tris: *TriangleArray) void {
            const len = tris.items.len;
            for (0..len) |i| {
                const vert = m.vec3u{ .arr = tris.items[i].pos };
                const newpos = m.vec3u{ .vec = m.matXvec3(mat, vert.vec) };
                tris.items[i].pos = newpos.arr;
            }
        }
    };

    pub fn Ring(alloc: Allocator, param: RingParams) !TriangleArray {
        const vert_num: usize = @as(usize, param.len) * 2;

        var pair_arr: PairArray = .empty;
        try pair_arr.resize(alloc, vert_num);
        defer pair_arr.deinit(alloc); //intermediate cals

        ringPairs(pair_arr.items, param);
        return try triangulateSegments(alloc, pair_arr.items);
    }

    pub fn Blocky(alloc: Allocator) !TriangleArray {
        var triangles: TriangleArray = try .initCapacity(alloc, 30);
        errdefer triangles.deinit(alloc);

        var lid: [6]Vertex = undefined;

        for (0.., tri_loops) |i, ti| {
            lid[i] = quad[ti];
            lid[i].color = .{ 1, 1, 0 };
        }
        try triangles.appendSlice(alloc, lid[0..]);
        try addSides(alloc, &triangles);
        return triangles;
    }

    pub fn Ringy(alloc: Allocator) !TriangleArray {
        const unit: f32 = @sqrt(2.0);

        const hmm = RingParams{
            .len = 5,
            .flat = true,
            .outer_r = unit,
            .inner_r = unit * 0.5,
        };

        var ring_tris = try Ring(alloc, hmm);
        for (0..ring_tris.items.len) |i| ring_tris.items[i].color[0] = 1;
        const rotmat = m.rotMatY(0.125);

        Math.rotate(rotmat, &ring_tris);
        try addSides(alloc, &ring_tris);
        return ring_tris;
    }

    fn addSides(alloc: Allocator, tris: *TriangleArray) !void {
        const rotX = m.rotMatX(0.25);
        var face: [6]Vertex = undefined;
        for (0.., tri_loops) |i, ti| {
            face[i] = quad[ti];
            const u: f32 = if (ti < 2) 0 else 1;
            face[i].color = .{ u, 1, 0 };
            const _pos: m.vec3u = .{ .arr = face[i].pos };
            const rotated = m.matXvec3(rotX, _pos.vec);
            const pos_: m.vec3u = .{ .vec = rotated + m.vec3{ 0, -1, -1 } };
            face[i].pos = pos_.arr;
        }
        try tris.appendSlice(alloc, face[0..]);

        const rotY = m.rotMatY(0.25);
        for (0..3) |_| {
            for (0..6) |jj| {
                const _pos: m.vec3u = .{ .arr = face[jj].pos };
                const pos_: m.vec3u = .{ .vec = m.matXvec3(rotY, _pos.vec) };
                face[jj].pos = pos_.arr;
            }
            try tris.appendSlice(alloc, face[0..]);
        }
    }

    fn ringPairs(pair_points: []PairPoint, param: RingParams) void {
        std.debug.assert(@mod(pair_points.len, 2) == 0);
        const segments = pair_points.len / 2;

        for (0..segments) |i| {
            // const flen: f32 = @floatFromInt(len - 1);
            // const fi: f32 = @floatFromInt(i);
            const progress = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments - 1));

            const phi = std.math.tau * progress;
            const stamp_a = PairPoint{
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

            pair_points[i * 2] = stamp_a;
            pair_points[i * 2 + 1] = stamp_b;
        }

        for (0..segments) |pre_i| {
            const stage_i = pre_i * 2;
            const base: [2]f32 = pair_points[stage_i].pos[0..2].*;

            const height: f32 = if (param.flat) 0.0 else 0.5;
            pair_points[stage_i].pos = m.stack(m.mul2D(base, param.inner_r), height);
            pair_points[stage_i + 1].pos = m.stack(m.mul2D(base, param.outer_r), 0);
        }
    }

    fn triangulateSegments(alloc: Allocator, pair_points: []const PairPoint) !TriangleArray {
        std.debug.assert(@mod(pair_points.len, 2) == 0);
        const len = pair_points.len / 2;

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
                const stage = pair_points[pos_i + pos_off];
                const v = Vertex{
                    .pos = .{
                        stage.pos[X],
                        stage.pos[Z],
                        stage.pos[Y],
                    },
                    .color = .{ stage.progress, stage.v, 0 },
                };
                stage_vert[tri_pair_i + jj] = v;
            }
        }
        return stage_vert_arr;
    }
};

pub const VertIndex = struct {
    offsets: [4]u32 = .{ 0, 0, 0, 0 },
    sizes: [4]u32 = .{ 0, 0, 0, 0 },
    head: u8 = 0,
    total: u32 = 0,
    vkBuffer: vk.Buffer = undefined,

    pub fn register(self: *VertIndex, new: []const Vertex) void {
        self.sizes[self.head] = @intCast(new.len);
        self.offsets[self.head] = self.total;
        self.total += @intCast(new.len);
        self.head += 1;
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
pub fn populateModels(alloc: std.mem.Allocator, here: *TriangleArray, as: *VertIndex) !void {
    var param = RingParams.default;
    var shape: TriangleArray = undefined;

    param.len = 5;
    param.flat = true;
    shape = try Utils.Ringy(alloc);
    try here.appendSlice(alloc, shape.items);
    as.register(shape.items);
    shape.deinit(alloc);

    param.len = 32;
    param.flat = false;
    shape = try Utils.Ring(alloc, param);
    try here.appendSlice(alloc, shape.items);
    as.register(shape.items);
    shape.deinit(alloc);

    shape = try Utils.Blocky(alloc);
    try here.appendSlice(alloc, shape.items);
    as.register(shape.items);
    shape.deinit(alloc);
}
