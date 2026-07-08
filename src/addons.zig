const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("third_party/glfw.zig");
const gftx = @import("graphics_context.zig");

const t = @import("types.zig");
const d = @import("debug.zig");
const sht = @import("shaders/types.zig");
const m = @import("math.zig");
const utils = @import("utils.zig");
const time = @import("time.zig");

const Allocator = std.mem.Allocator;

pub const PerfStats = d.PerfStats;

pub const Timeline = time.Timeline;

pub const GridOps = struct {
    pub fn center(grid: *const sht.GridSize) m.vec3 {
        const mid_2d = middle(grid);
        return .{ mid_2d[0], 0, mid_2d[1] };
    }
    pub fn middle(grid: *const sht.GridSize) m.vec2 {
        const x_mid = @as(f32, @floatFromInt(grid.w - 1)) * 0.5;
        const z_mid = @as(f32, @floatFromInt(grid.h - 1)) * 0.5;
        return .{ x_mid, z_mid };
    }

    pub fn gridDelta(grid: *const sht.GridSize) m.vec3 {
        const a: f32 = 0.0;
        _ = grid;
        return .{ a, 0, 0 };
    }

    pub fn gridIdx(grid: *const sht.GridSize, i: usize) m.vec3 {
        return .{
            @as(f32, @floatFromInt(@mod(i, grid.w))),
            0,
            @as(f32, @floatFromInt(i / grid.w)),
        };
    }
};

// ------------------------------------------------

const EPersp = enum(u8) { ortho = 0, persp, orthoside };

const MatPack = sht.MatPack;
pub fn paramatricVariation(pos: m.vec3, targ: m.vec3, persp: EPersp) !MatPack {
    const persp_window = switch (persp) {
        .ortho => m.mat_ortho_uniformed(10),
        .persp => m.mat_persp(1, 0.75, std.math.pi / 2.0, 0.1, 20),
        .orthoside => m.mat_ortho_shift(10, .{ -5, 0, 0 }),
    };

    const ref_up: m.vec3 = .{ 0, 1, 0 };
    const trans = m.matTrans(-pos);
    const rot = m.lookRotation(pos, targ, ref_up);
    const view_mat = m.matXmat(rot.mat, trans.mat);

    const model_mat = m.lookRotation(m.zero3(), .{ 1, 0, 0 }, .{ 0, 1, 0 });

    const interm = MatPack{
        .proj = persp_window.arr,
        .view = view_mat.arr,
        .model = model_mat.arr,
        // .view = m.mat_translate(-pos).arr,
        // .view = m.lookRotation(.{ 0, 0, -1 }, pos).arr,
    };
    return interm;
}

pub fn guiVisor(x: f32, y: f32) MatPack {
    const interm = MatPack{
        .proj = m.mat_ortho(x, 0, 0, -y, 16, -16).arr,
        .view = m.matIden().arr,
        .model = m.matIden().arr,
        // .view = m.mat_translate(-pos).arr,
        // .view = m.lookRotation(.{ 0, 0, -1 }, pos).arr,
    };
    return interm;
}
pub fn defGuiVisor() MatPack {
    return guiVisor(640, 480);
}

pub fn getWindowSize(window: *glfw.Window) vk.Extent2D {
    var w: c_int = undefined;
    var h: c_int = undefined;
    glfw.getFramebufferSize(window, &w, &h);
    return .{
        .height = @intCast(w),
        .width = @intCast(h),
    };
}

pub fn extentDiffer(a: vk.Extent2D, b: vk.Extent2D) bool {
    return a.width != b.width or a.height != b.height;
}

pub fn visible(a: vk.Extent2D) bool {
    return a.width != 0 and a.height != 0;
}

pub const Coords = struct {
    const Self = @This();
    const HitResult = struct {
        at: m.vec2,
        hit: bool,
    };

    sz_scr: m.vec2,
    sz_area: m.vec2,
    offset: m.vec2,
    pub fn init(screan: vk.Extent2D) Coords {
        var base: Self = .{
            .sz_scr = m.vkextAsV2(screan),
            .sz_area = undefined,
            .offset = undefined,
        };
        base.calcArea(0.9);
        return base;
    }

    fn calcArea(self: *Coords, fill: f32) void {
        const scr: [2]f32 = self.sz_scr;
        const smin = @min(scr[0], scr[1]);
        const padding = smin * (1 - fill) / 2;
        self.sz_area = .{ smin * fill, smin * fill };
        self.offset = .{ padding, padding };
    }

    pub fn update(self: *const Self, cursor: m.vec2) HitResult {
        const axnum = 2;
        const axes: [axnum]u8 = .{ m.X, m.Y };
        var in_num: u8 = 0;
        var r: [axnum]f32 = .{ 0, 0 };
        const c: [axnum]f32 = cursor;
        const o: [axnum]f32 = self.offset;
        const a: [axnum]f32 = self.sz_area;
        for (axes) |ax| {
            const pos = @abs(c[ax]) - o[ax];
            if (pos >= 0 and pos <= a[ax]) {
                r[ax] = pos / a[ax];
                in_num += 1;
            }
        }
        return HitResult{
            .at = .{ r[m.X], r[m.Y] },
            .hit = in_num == axnum,
        };
    }
};

const UVMap = struct {
    offset: m.vec2 = m.v2Zero(),
    mult: m.vec2 = m.v2Zero(),
};

pub const Navig = struct {
    screan: m.vec2,
    cursor: m.vec2,

    scann_sz: m.vec2,
    scann_aspect: m.vec2 = undefined,

    uv_map: UVMap,

    cursor_tex: u16,
    pub fn aspectScale(self: *const Navig) m.vec2 {
        const w, const h = self.scann_sz;
        const hscale = h / w;
        return .{ 1, hscale };
    }

    pub fn aspectScale3(self: *const Navig) m.vec3 {
        const w, const h = self.aspectScale();
        return .{ w, h, 1 };
    }

    pub fn scanPlacement(self: *const Navig) m.mat4 {
        const ws, const hs = self.screan;

        const mmin = @min(ws, hs);

        const padding = mmin * 0.05;
        const s: m.vec3 = .{ mmin * 0.9, mmin * 0.9, 1 };

        const saled = m.matScale(s);
        const moved = m.matTrans(.{ padding, -padding, 0 });
        const combinde = m.matXmat(moved.mat, saled.mat).mat;

        return combinde;
    }

    pub const default = @This(){
        .screan = .{ 128, 128 },
        .cursor = m.v2Zero(),
        .scann_sz = m.v2One(),
        .uv_map = UVMap{},
        .cursor_tex = 0,
    };
};
