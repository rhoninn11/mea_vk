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
pub const DescriptorPrep = struct {
    const Self = @This();
    d_set_layout_arr: std.ArrayList(vk.DescriptorSetLayout) = .empty,
    d_set_arr: std.ArrayList(vk.DescriptorSet) = .empty,
    buff_arr: std.ArrayList(?gftx.BufferData) = .empty,

    gc: *const gftx.GraphicsContext,
    _d_set_layout: ?vk.DescriptorSetLayout = null,
    _d_pool: ?vk.DescriptorPool = null,

    pub fn init(
        alloc: Allocator,
        gc: *const gftx.GraphicsContext,
        len: usize,
        using: gftx.baked.DSetInit,
        with: gftx.baked.UniformInfo,
        img: ?gftx.RGBImage,
    ) !Self {
        const len_u32: u32 = @intCast(len);

        var self: Self = .{
            .gc = gc,
        };

        //dynamic arrays alloc
        const devk = self.gc.dev;
        errdefer self.deinit(alloc);
        try self.d_set_layout_arr.resize(alloc, len);
        try self.buff_arr.resize(alloc, len);
        try self.d_set_arr.resize(alloc, len);

        //binding layout
        const _bind = vk.DescriptorSetLayoutBinding{
            .binding = with.location, // w sensie, że lokacja 0?
            .descriptor_count = 1,
            .descriptor_type = using.usage.descriptor_type,
            .p_immutable_samplers = null, // for textures ?
            .stage_flags = using.shader_stage,
        };

        self._d_set_layout = try devk.createDescriptorSetLayout(&.{
            .s_type = .descriptor_set_layout_create_info,
            .p_bindings = @ptrCast(&_bind),
            .binding_count = 1,
        }, null);

        // duplicate
        for (0..len) |i| {
            self.d_set_layout_arr.items[i] = self._d_set_layout.?;
            self.buff_arr.items[i] = null;
            self.buff_arr.items[i] = try gftx.createBuffer(
                self.gc,
                using.memory_property,
                using.usage.usage_flag,
                with.size,
            );
        }

        // allocate from pool
        const p_size: []const vk.DescriptorPoolSize = &.{.{
            .type = using.usage.descriptor_type,
            .descriptor_count = len_u32,
        }};

        // std.debug.print("+++ pool is {s}\n", .{@tagName(p_size.type)});

        self._d_pool = try self.gc.dev.createDescriptorPool(&vk.DescriptorPoolCreateInfo{
            .s_type = .descriptor_pool_create_info,
            .p_pool_sizes = p_size.ptr,
            .pool_size_count = @intCast(p_size.len),
            .max_sets = len_u32,
        }, null);

        try self.gc.dev.allocateDescriptorSets(
            &vk.DescriptorSetAllocateInfo{
                .s_type = .descriptor_set_allocate_info,
                .descriptor_pool = self._d_pool.?,
                .descriptor_set_count = len_u32,
                .p_set_layouts = self.d_set_layout_arr.items.ptr,
            },
            self.d_set_arr.items.ptr,
        );

        // specify data
        // var hmm: std.ArrayList(vk.WriteDescriptorSet) = .empty;

        for (0..len) |i| {
            if (using.usage.descriptor_type == .combined_image_sampler) {
                const img_info = vk.DescriptorImageInfo{
                    .image_layout = .shader_read_only_optimal,
                    .image_view = img.?.vk_img_view.?,
                    .sampler = img.?.vk_sampler.?,
                };
                const write_image_dsc_set = vk.WriteDescriptorSet{
                    .s_type = .write_descriptor_set,
                    .dst_set = self.d_set_arr.items[i],
                    .dst_binding = with.location,
                    .dst_array_element = 0,
                    .descriptor_type = using.usage.descriptor_type,
                    .descriptor_count = 1,
                    .p_buffer_info = &.{},
                    .p_image_info = @ptrCast(&img_info),
                    .p_texel_buffer_view = &.{},
                };
                self.gc.dev.updateDescriptorSets(1, @ptrCast(&write_image_dsc_set), 0, null);
            } else {
                const buf_info = vk.DescriptorBufferInfo{
                    .buffer = self.buff_arr.items[i].?.dvk_bfr,
                    .range = with.size,
                    .offset = 0,
                };
                const write_buffer_dsc_set = vk.WriteDescriptorSet{
                    .s_type = .write_descriptor_set,
                    .dst_set = self.d_set_arr.items[i],
                    .dst_binding = with.location,
                    .dst_array_element = 0,
                    .descriptor_type = using.usage.descriptor_type,
                    .descriptor_count = 1,
                    .p_buffer_info = @ptrCast(&buf_info),
                    .p_image_info = &.{},
                    .p_texel_buffer_view = &.{},
                };
                self.gc.dev.updateDescriptorSets(1, @ptrCast(&write_buffer_dsc_set), 0, null);
            }
        }

        return self;
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        if (self._d_pool) |d_pool| {
            self.gc.dev.destroyDescriptorPool(d_pool, null);
        }

        for (self.buff_arr.items) |possible_buff| {
            if (possible_buff) |buff| {
                buff.deinit(self.gc);
            }
        }

        if (self._d_set_layout) |layout| {
            self.gc.dev.destroyDescriptorSetLayout(layout, null);
        }

        self.d_set_arr.deinit(alloc);
        self.buff_arr.deinit(alloc);
        self.d_set_layout_arr.deinit(alloc);
    }
};

pub const Gridor = struct {
    pub fn gridMiddle(grid: *const sht.GridSize) m.vec3 {
        std.debug.print("grid is: {} {}\n", .{ grid.row_num, grid.col_num });
        const x_mid = @as(f32, @floatFromInt(grid.row_num - 1)) * 0.5;
        const z_mid = @as(f32, @floatFromInt(grid.col_num - 1)) * 0.5;
        return .{ x_mid, 0, z_mid };
    }

    pub fn gridDelta(grid: *const sht.GridSize) m.vec3 {
        const a: f32 = 0.0;
        _ = grid;
        return .{ a, 0, 0 };
    }

    pub fn gridIdx(grid: *const sht.GridSize, i: usize) m.vec3 {
        return .{
            @as(f32, @floatFromInt(@mod(i, grid.col_num))),
            0,
            @as(f32, @floatFromInt(i / grid.row_num)),
        };
    }

    pub fn xyGrid(x: u8, y: u8) sht.GridSize {
        return sht.GridSize{
            .total = @as(u16, x) * @as(u16, y),
            .col_num = x,
            .row_num = y,
        };
    }
};

// ------------------------------------------------

const MatPack = sht.MatPack;
pub fn paramatricVariation(scale: f32, pos: m.vec3, targ: m.vec3) !MatPack {
    const persp_window = m.mat_persp(1, 0.75, std.math.pi / 2.0, 0.1, 20);
    const ortho_window = m.mat_ortho(scale, -scale, scale, -scale, 20, -20);
    _ = ortho_window;

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
