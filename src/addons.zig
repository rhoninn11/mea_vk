const std = @import("std");
const vk = @import("third_party/vk.zig");
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
    pub fn middle(grid: *const sht.GridSize) m.vec3 {
        const mid_2d = middle2D(grid);
        return .{ mid_2d[0], 0, mid_2d[1] };
    }
    pub fn middle2D(grid: *const sht.GridSize) m.vec2 {
        std.debug.print("grid is: {} {}\n", .{ grid.h, grid.w });
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
    const trans = m.mat_translate(-pos);
    const rot = m.lookRotation(pos, targ, ref_up);
    const camera_mat = m.matXmat(rot.mat, trans.mat);

    const model_mat = m.lookRotation(m.zero3(), .{ 1, 0, 0 }, .{ 0, 1, 0 });

    const interm = MatPack{
        .proj = persp_window.arr,
        .view = camera_mat.arr,
        .model = model_mat.arr,
        // .view = m.mat_translate(-pos).arr,
        // .view = m.lookRotation(.{ 0, 0, -1 }, pos).arr,
    };
    return interm;
}

pub fn guiVisor(x: f32, y: f32) MatPack {
    const scale: f32 = 1.0 / 128.0;
    const _x = x * scale;
    const _y = y * scale;
    const interm = MatPack{
        .proj = m.mat_ortho(_x * 0.5, -_x * 0.5, _y * 0.5, -_y * 0.5, 16, -16).arr,
        .view = m.mat_identity().arr,
        .model = m.mat_identity().arr,
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
