const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("third_party/glfw.zig");
const gftx = @import("graphics_context.zig");

const t = @import("types.zig");
const sht = @import("shaders/types.zig");
const m = @import("math.zig");
const utils = @import("utils.zig");
const time = @import("time.zig");

const Allocator = std.mem.Allocator;

pub const PerfStats = utils.PerfStats;

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

const MatPack = sht.MatPack;
pub fn paramatricVariation(pos: m.vec3, targ: m.vec3, persp: bool) !MatPack {
    const persp_window = switch (persp) {
        true => m.mat_persp(1, 0.75, std.math.pi / 2.0, 0.1, 20),
        false => m.mat_ortho_uniformed(10),
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
    const scale: f32 = 1.0 / 64.0;
    const _x = x * scale;
    const _y = y * scale;
    const interm = MatPack{
        .proj = m.mat_ortho(_x, 0, 0, -_y, 16, -16).arr,
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

const EasyAcces = struct {
    window: ?*c_long,
    vkctx: ?*const gftx.GraphicsContext = null,
};

pub const Coords = struct {
    const Self = @This();
    sz_scr: m.vec2,
    sz_area: m.vec2,
    offset: m.vec2,
    pub fn init(screan: vk.Extent2D) Coords {
        var base: Self = .{
            .sz_scr = .{
                m.floaty(@abs(screan.width)),
                m.floaty(@abs(screan.height)),
            },
            .sz_area = undefined,
            .offset = undefined,
        };
        base.calcArea(0.5);
        return base;
    }

    fn calcArea(self: *Coords, fill: f32) void {
        const scr: [2]f32 = self.sz_scr;
        const major: u8 = if (scr[m.X] > scr[m.Y]) m.X else m.Y;
        const minor: u8 = if (major == m.X) m.Y else m.X;

        const sz_min = scr[minor] * fill;
        const off_min = (scr[minor] - sz_min) / 2.0;

        const sz_maj = sz_min;
        const off_maj = (scr[major] - sz_maj) / 2.0;
        var scratch: [2]f32 = undefined;
        scratch[minor] = sz_min;
        scratch[major] = sz_maj;
        self.sz_area = scratch;

        scratch[minor] = off_min;
        scratch[major] = off_maj;
        self.offset = scratch;
    }

    pub fn pointer(self: *const Self, cursor: m.vec2) m.vec3 {
        const axnum = 2;
        const axes: [axnum]u8 = .{ m.X, m.Y };
        var in_num: u8 = 0;
        var r: [axnum]f32 = .{ 0, 0 };
        const c: [axnum]f32 = cursor;
        const o: [axnum]f32 = self.offset;
        const a: [axnum]f32 = self.sz_area;
        for (axes) |ax| {
            const pos = @abs(c[ax]) - o[ax];
            if (pos <= a[ax]) {
                r[ax] = pos / a[ax];
                in_num += 1;
            }
        }

        const test_val: f32 = if (in_num == axnum) 1.0 else 0.0;
        return .{ r[m.X], r[m.Y], test_val };
    }
};
