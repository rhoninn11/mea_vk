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
    pub fn gridMiddle(grid: *const t.GridSize) m.vec3 {
        std.debug.print("grid is: {} {}\n", .{ grid.row_num, grid.col_num });
        const x_mid = @as(f32, @floatFromInt(grid.row_num - 1)) * 0.5;
        const z_mid = @as(f32, @floatFromInt(grid.col_num - 1)) * 0.5;
        return .{ x_mid, 0, z_mid };
    }

    pub fn gridDelta(grid: *const t.GridSize) m.vec3 {
        const a: f32 = 0.0;
        _ = grid;
        return .{ a, 0, 0 };
    }

    pub fn gridIdx(grid: *const t.GridSize, i: usize) m.vec3 {
        return .{
            @as(f32, @floatFromInt(@mod(i, grid.col_num))),
            0,
            @as(f32, @floatFromInt(i / grid.row_num)),
        };
    }

    pub fn defaultGrid() t.GridSize {
        return xyGrid(8, 8);
    }

    pub fn xyGrid(x: u8, y: u8) t.GridSize {
        return t.GridSize{
            .total = @as(u16, x) * @as(u16, y),
            .col_num = x,
            .row_num = y,
        };
    }
};

pub fn perFrameUniformFill(uniform_dset: DescriptorPrep, frame_idx: u8, total_s: f32, center: m.vec3, size: f32) !void {
    const this_frame_uniform = uniform_dset.buff_arr.items[frame_idx].?;
    const as_group_data: *sht.GroupData = @ptrCast(@alignCast(this_frame_uniform.mapping.?));

    const scale_osc = std.math.sin(total_s) * 0.2 + 2;
    _ = scale_osc;

    as_group_data.*.osc_scale = .{ 0.1, 0.1 };
    as_group_data.*.scale_2d = .{ size, size };
    as_group_data.*.termoral = .{ total_s, 0, 1, 2 };
    as_group_data.*.matrices = try paramatricVariation(
        1,
        center,
        .{ 0, 0, 0 },
    );
}

pub fn storagePrefil(storage_dset: DescriptorPrep, grid: t.GridSize, spacing: f32) void {
    const instance_num = grid.total;
    const lim_num = 8096;
    std.debug.assert(instance_num <= lim_num);

    std.debug.print("is possible to print? {}\n", .{grid});

    const along = 1 / @as(f32, @floatFromInt(instance_num - 1));
    const phase_delta = along * std.math.tau;
    const spread_base = 0;
    const spread_delta = along * 0.2;

    const seed: u64 = @intCast(std.time.timestamp()); // more random
    // const seed: u64 = 42; // deterministic?
    var rng = std.Random.DefaultPrng.init(seed);
    var rnd_gen = rng.random();

    var stack_mem: [lim_num * 4]u8 = undefined;
    var local: std.heap.FixedBufferAllocator = .init(&stack_mem);
    const allocator = local.allocator();

    // const hmm = rnd_gen.float(f32);
    var storage_baker: std.ArrayList(f32) = .empty;
    var storage_baker2: std.ArrayList(f32) = .empty;
    storage_baker.resize(allocator, instance_num) catch unreachable;
    storage_baker2.resize(allocator, instance_num) catch unreachable;

    for (0..instance_num) |i| {
        //random
        storage_baker.items[i] = rnd_gen.float(f32);
        //progression
        const progress = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(instance_num - 1));
        storage_baker2.items[i] = progress;
        //constant wins
        storage_baker.items[i] = -0.125;
    }

    {
        defer storage_baker.deinit(allocator);
        defer storage_baker2.deinit(allocator);

        const middle = Gridor.gridMiddle(&grid);
        for (storage_dset.buff_arr.items) |possible_buffer| {
            const storage = possible_buffer.?;
            const storagePtr: [*]sht.PerInstance = @ptrCast(@alignCast(storage.mapping.?));
            for (0..instance_num) |i| {
                const i_f: f32 = @floatFromInt(i);

                // const y_d = (middle_alt[m.Z] - y_f) / middle_alt[m.Z];
                const g_idx = Gridor.gridIdx(&grid, i);

                const delt = ((middle - g_idx) / middle) * m.splat3d(6);
                const dist = std.math.sqrt(delt[m.X] * delt[m.X] + delt[m.Z] * delt[m.Z]);

                var fresh_one: sht.PerInstance = undefined;
                const pos_1 = (g_idx - middle) * m.splat3d(spacing);

                fresh_one.other_offsets[0] = i_f * phase_delta;
                fresh_one.other_offsets[1] = spread_base + i_f * spread_delta;
                fresh_one.new_usage[0] = storage_baker.items[i]; //offset on ring
                fresh_one.new_usage[1] = dist;
                fresh_one.new_usage[2] = g_idx[m.X];
                fresh_one.new_usage[3] = delt[m.X];
                fresh_one.offset_4d = m.stack4d(pos_1, 1);
                storagePtr[i] = fresh_one;
            }
            std.debug.print("\n", .{});
        }
    }
}

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
