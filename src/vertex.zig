const std = @import("std");
const gm = @import("graphics_context.zig");
const vk = @import("vulkan-zig");
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

    pos: [3]f32,
    color: [3]f32,
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
    Vertex{ .pos = .{ 1, 0, -1 }, .color = .{ 1, 1, 0 } },
    Vertex{ .pos = .{ -1, 0, -1 }, .color = .{ 0, 1, 0 } },
    Vertex{ .pos = .{ 1, 0, 1 }, .color = .{ 1, 0, 0 } },
    Vertex{ .pos = .{ -1, 0, 1 }, .color = .{ 0, 0, 0 } },
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

pub const Math = struct {
    pub fn matApply(tris: []Vertex, mat: m.mat3) void {
        const len = tris.len;
        for (0..len) |i| {
            const vert = m.vec3u{ .arr = tris[i].pos };
            const newpos = m.vec3u{ .vec = m.matXvec3(mat, vert.vec) };
            tris[i].pos = newpos.arr;
        }
    }
    pub fn scaleApply(verts: []Vertex, scale: m.vec3) void {
        const len = verts.len;
        for (0..len) |i| {
            const vert = m.vec3u{ .arr = verts[i].pos };
            const newpos = m.vec3u{ .vec = vert.vec * scale };
            verts[i].pos = newpos.arr;
        }
    }
    pub fn transApply(verts: []Vertex, offset: m.vec3) void {
        const len = verts.len;
        for (0..len) |i| {
            const vert = m.vec3u{ .arr = verts[i].pos };
            const newpos = m.vec3u{ .vec = vert.vec + offset };
            verts[i].pos = newpos.arr;
        }
    }
    pub const xrot45 = m.rotMatX(0.125);
    pub const xrot90 = m.rotMatX(0.25);
    pub const xrot180 = m.rotMatX(0.5);
    pub const xrot90neg = m.rotMatX(-0.25);

    pub const yrot45 = m.rotMatY(0.125);
    pub const yrot90 = m.rotMatY(0.25);
};

pub const Utils = struct {
    pub fn Ring(alloc: Allocator, param: RingParams) !TriangleArray {
        const vert_num: usize = @as(usize, param.len) * 2;

        var pair_arr: PairArray = .empty;
        try pair_arr.resize(alloc, vert_num);
        defer pair_arr.deinit(alloc); //intermediate cals

        ringPairs(pair_arr.items, param);
        return try triangulateSegments(alloc, pair_arr.items);
    }

    pub fn Cube(alloc: Allocator) !TriangleArray {
        var triangles: TriangleArray = try .initCapacity(alloc, 30);
        errdefer triangles.deinit(alloc);

        var lid: [6]Vertex = undefined;

        for (0.., tri_loops) |i, ti| {
            lid[i] = quad[ti];
            lid[i].color = .{ 1, 1, 0 };
        }
        // top
        Math.transApply(lid[0..], .{ 0, 1, 0 });
        try triangles.appendSlice(alloc, lid[0..]);
        // middle
        try addSides(alloc, &triangles);
        // bottom
        for (0..lid.len) |i| lid[i].color = .{ 0, 1, 0 };
        Math.matApply(lid[0..], Math.xrot180);
        try triangles.appendSlice(alloc, lid[0..]);
        return triangles;
    }

    pub fn Pierced(gpa: Allocator) !TriangleArray {
        var out_tris: TriangleArray = try .initCapacity(gpa, 48);
        errdefer out_tris.deinit(gpa);

        const unit: f32 = @sqrt(2.0);
        const ring_param = RingParams{
            .len = 5,
            .flat = true,
            .outer_r = unit,
            .inner_r = unit * 0.5,
        };
        var lid_ring = try Ring(gpa, ring_param);
        defer lid_ring.deinit(gpa);

        // top
        for (0..lid_ring.items.len) |i| lid_ring.items[i].color[0] = 1;
        Math.matApply(lid_ring.items, Math.yrot45);
        Math.transApply(lid_ring.items, .{ 0, 1, 0 });
        try out_tris.appendSlice(gpa, lid_ring.items);
        // middle
        try addSides(gpa, &out_tris);
        // bottom
        for (0..lid_ring.items.len) |i| lid_ring.items[i].color[0] = 0;
        Math.matApply(lid_ring.items, Math.xrot180);
        try out_tris.appendSlice(gpa, lid_ring.items);

        return out_tris;
    }

    pub fn Hollow(gpa: Allocator) !TriangleArray {
        const square_blits = 4;
        const border = 0.125;

        var triangles: TriangleArray = try .initCapacity(gpa, 12);
        defer triangles.deinit(gpa);
        {
            // TODO:
            // add propper uv mapping
            try blitQuad(gpa, &triangles);
            Math.matApply(triangles.items, Math.xrot90);

            Math.scaleApply(triangles.items, m.splat3d(0.5));
            Math.scaleApply(triangles.items, .{ 1 - border * 2, border, 1 });
            try triangles.appendSlice(gpa, triangles.items);
            const blade = triangles.items[6..];
            Math.matApply(blade, Math.xrot90neg);
            Math.transApply(blade, .{ 0, border * 0.5, border * 0.5 });
            // add side "wings"
            var wing_vert = blade[2];
            wing_vert.pos[m.X] += border;
            try triangles.append(gpa, wing_vert);
            try triangles.append(gpa, blade[0]);
            try triangles.append(gpa, blade[2]);
            wing_vert = blade[5];
            wing_vert.pos[m.X] -= border;
            try triangles.append(gpa, wing_vert);
            try triangles.append(gpa, blade[5]);
            try triangles.append(gpa, blade[4]);

            Math.transApply(triangles.items, .{ 0, (1 - border) * 0.5, 0.5 - border });
        }

        var triangles_out: TriangleArray = try .initCapacity(gpa, 48);
        defer triangles_out.deinit(gpa);
        {
            for (0..square_blits) |_| {
                try triangles_out.appendSlice(gpa, triangles.items);
                Math.matApply(triangles.items, Math.yrot90);
            }
        }

        var triangles_final: TriangleArray = try .initCapacity(gpa, 96);
        errdefer triangles_final.deinit(gpa);
        {
            try triangles_final.appendSlice(gpa, triangles_out.items);
            Math.matApply(triangles_out.items, Math.xrot180);
            try triangles_final.appendSlice(gpa, triangles_out.items);
            Math.matApply(triangles_out.items, Math.xrot90);
            for (0..square_blits) |_| {
                try triangles_final.appendSlice(gpa, triangles_out.items);
                Math.matApply(triangles_out.items, Math.yrot90);
            }
        }
        BBox.fromTriangles(triangles_final).print("hollow");
        const verts = triangles_final.items;
        const lower = -0.5 + border;
        const upper = 0.5 - border;
        const scale = 1.0 / (upper - lower);

        for (0..verts.len) |i| {
            const clamped = std.math.clamp(verts[i].pos[m.Y], lower, upper);
            verts[i].color[m.X] = (clamped - lower) * scale;
        }

        Math.scaleApply(triangles_final.items, m.splat3d(2));
        return triangles_final;
    }

    fn blitQuad(alloc: Allocator, ta: *TriangleArray) !void {
        var lid: [6]Vertex = undefined;
        for (0.., tri_loops) |i, ti| {
            lid[i] = quad[ti];
        }
        return ta.appendSlice(alloc, &lid);
    }

    pub fn Bilboard(alloc: Allocator) !TriangleArray {
        var triangles: TriangleArray = try .initCapacity(alloc, 6);
        errdefer triangles.deinit(alloc);

        try blitQuad(alloc, &triangles);
        Math.matApply(triangles.items, Math.xrot90);
        return triangles;
    }

    pub fn Hexy(gpa: Allocator) !TriangleArray {
        var triangles: TriangleArray = try .initCapacity(gpa, 6);
        errdefer triangles.deinit(gpa);

        try blitQuad(gpa, &triangles);
        const tis = triangles.items;
        Math.matApply(triangles.items, Math.xrot90);
        Math.scaleApply(triangles.items, .{ @sqrt(3.0) / 3.0, 1, 1 });
        for (0..6) |i| {
            const val = &triangles.items[i].color[0];
            val.* = 0.5 * val.* + 0.5;
        }

        try triangles.appendSlice(gpa, &.{ tis[0], tis[2], Vertex{
            .pos = .{ 1, 0, 0 },
            .color = .{ 1, 1, 0 },
        } });
        try triangles.appendSlice(gpa, &.{ tis[5], tis[4], Vertex{
            .pos = .{ -1, 0, 0 },
            .color = .{ 0, 0, 0 },
        } });

        return triangles;
    }

    fn blitting(alloc: Allocator, stencil: *TriangleArray) !TriangleArray {
        const rotX = m.rotMatX(0.25);

        _ = alloc;
        _ = stencil;
        _ = rotX;
    }

    fn addSides(alloc: Allocator, tris: *TriangleArray) !void {
        var face: [6]Vertex = undefined;
        for (0.., tri_loops) |i, ti| {
            face[i] = quad[ti];
            const u: f32 = if (ti < 2) 0 else 1;
            face[i].color = .{ u, 1, 0 };
        }
        Math.matApply(face[0..], Math.xrot90);
        Math.transApply(face[0..], .{ 0, 0, -1 });
        try tris.appendSlice(alloc, face[0..]);

        for (0..3) |_| {
            Math.matApply(face[0..], Math.yrot90);
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

        for (0..segments) |seg_i| {
            const pnt_i = seg_i * 2;
            const base: [2]f32 = pair_points[pnt_i].pos[0..2].*;

            const height: f32 = if (param.flat) 0.0 else 0.5;
            pair_points[pnt_i + 1].pos = m.stack(m.mul2D(base, param.inner_r), height);
            pair_points[pnt_i].pos = m.stack(m.mul2D(base, param.outer_r), 0);
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

            for (tri_loops, 0..) |pos_off, jj| {
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

const MODEL_MAX: u8 = 8;
pub const VertRepo = struct {
    offsets: [MODEL_MAX]u32 = .{0} ** MODEL_MAX,
    sizes: [MODEL_MAX]u32 = .{0} ** MODEL_MAX,
    head: u8 = 0,
    total: u32 = 0,
    vbo: ?gm.BufferData = null,

    pub fn register(self: *VertRepo, new: []const Vertex) void {
        self.sizes[self.head] = @intCast(new.len);
        self.offsets[self.head] = self.total;
        self.total += @intCast(new.len);
        self.head += 1;
    }
    pub fn populate(self: *VertRepo, alloc: std.mem.Allocator, here: *TriangleArray) !void {
        return populateModels(alloc, here, self);
    }

    pub fn deinit(self: *VertRepo, gc: *const gm.GraphicsContext) void {
        if (self.vbo) |vbo| vbo.deinit(gc);
    }
};

pub fn repoSpawn(alloc: std.mem.Allocator, pic: *const gm.PoolInCtx) !VertRepo {
    var arean: std.heap.ArenaAllocator = .init(alloc);
    defer arean.deinit();

    var verts: TriangleArray = try .initCapacity(arean.allocator(), 256);

    var repo: VertRepo = .{};
    try repo.populate(arean.allocator(), &verts);

    const vert_buffer = try gm.createBuffer(
        pic.gc,
        gm.baked.memory_gpu,
        gm.baked.usage_vert_dst,
        @sizeOf(Vertex) * verts.items.len,
    );
    gm.uploadVertices(pic, vert_buffer.dvk_bfr, verts.items) catch unreachable;
    repo.vbo = vert_buffer;
    return repo;
}

pub const VertexAlt1 = struct {
    pos: [3]f32,
};

pub const VertexAlt2 = struct {
    pos: [5]f32,
};

fn tinkering(ToProbe: type, show: bool) void {
    if (show) {
        std.debug.print("{s} | size {d}, aligments {d}\n", .{ @typeName(ToProbe), @sizeOf(ToProbe), @alignOf(ToProbe) });
    }
}
pub fn probing(show: bool) void {
    tinkering(VertexAlt1, show);
    tinkering(VertexAlt2, show);
}
pub fn populateModels(gpa: std.mem.Allocator, here: *TriangleArray, as: *VertRepo) !void {
    var param = RingParams.default;
    var shape: TriangleArray = undefined;

    // const HOLLOW_CUBE = 0;
    param.len = 5;
    param.flat = true;
    shape = try Utils.Hollow(gpa);
    try here.appendSlice(gpa, shape.items);
    as.register(shape.items);
    shape.deinit(gpa);

    // const CUBE = 1;
    shape = try Utils.Cube(gpa);
    try here.appendSlice(gpa, shape.items);
    as.register(shape.items);
    shape.deinit(gpa);

    // const PIERCERD = 2;
    shape = try Utils.Pierced(gpa);
    try here.appendSlice(gpa, shape.items);
    as.register(shape.items);
    shape.deinit(gpa);

    // const RING = 3;
    //--- First
    param.len = 32;
    param.flat = false;
    shape = try Utils.Ring(gpa, param);
    try here.appendSlice(gpa, shape.items);
    as.register(shape.items);
    shape.deinit(gpa);
    //----

    // const BILBO = 4;
    shape = try Utils.Bilboard(gpa);
    try here.appendSlice(gpa, shape.items);
    as.register(shape.items);
    shape.deinit(gpa);

    // const BILBO_HEX = 5;
    shape = try Utils.Hexy(gpa);
    try here.appendSlice(gpa, shape.items);
    as.register(shape.items);
    shape.deinit(gpa);
}

const BBox = struct {
    min: [3]f32,
    max: [3]f32,

    pub fn fromTriangles(t_arr: TriangleArray) BBox {
        std.debug.assert(t_arr.items.len > 0);
        var min = t_arr.items[0].pos;
        var max = min;
        for (t_arr.items) |vert| {
            for (0..3) |i| {
                if (vert.pos[i] < min[i]) min[i] = vert.pos[i];
                if (vert.pos[i] > max[i]) max[i] = vert.pos[i];
            }
        }
        return .{ .min = min, .max = max };
    }

    pub fn print(self: *const BBox, name: []const u8) void {
        std.debug.print("??? {s} bbox: min - {any} | max - {any}\n", .{ name, self.min, self.max });
    }
};
