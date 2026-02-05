const std = @import("std");
const vk = @import("third_party/vk.zig");
const gftx = @import("graphics_context.zig");

const t = @import("types.zig");
const m = @import("math.zig");

const Allocator = std.mem.Allocator;

pub const PerfStats = struct {
    t0: i64,
    frame_num: u32,

    pub fn init() PerfStats {
        std.debug.print("--- empty line ---\n", .{});
        return PerfStats{
            .t0 = std.time.milliTimestamp(),
            .frame_num = 0,
        };
    }

    pub fn messure(s: *PerfStats) void {
        const now = std.time.milliTimestamp();
        const delta = now - s.t0;

        const messure_interval = 1000.0;
        const update_interval = 500;
        const update_interval_i: u32 = @intFromFloat(update_interval);

        const scale: f32 = messure_interval / update_interval;
        if (delta > update_interval_i) {
            std.debug.print("\x1B[A\x1B[2K", .{});
            var fps: f32 = @floatFromInt(s.frame_num);
            fps *= scale;

            if (fps > 9000) {
                // A first i didnt expected speed like 12k fps are even possible while window rendering
                // but switching to linux from windows enabled such an improvement xD

                // std.debug.print("+++ omg is over 9000 {d}\n", .{fps});
            }
            std.debug.print("+++ rendering hit {d} fps\n", .{fps});
            s.t0 += update_interval_i;
            s.frame_num = 0;
        }

        s.frame_num += 1;
    }
};

pub const Timeline = struct {
    _t0: i64,
    _t_last: i64,

    total_s: f32,
    delta_s: f32,

    time_passage: bool = true,

    pub fn init() Timeline {
        const now = std.time.microTimestamp();
        return Timeline{
            ._t0 = now,
            ._t_last = now,
            .total_s = 0,
            .delta_s = 0.0001,
        };
    }

    pub fn update(self: *Timeline) void {
        const now = std.time.microTimestamp();

        const delta = @as(f32, @floatFromInt(now - self._t_last));

        self._t_last = now;
        self.delta_s = delta / 1000000;
        if (self.time_passage) {
            self.total_s += self.delta_s;
        }
    }
};

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
                with.size,
                using.usage.usage_flag,
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
                buff.deinit(self.gc.dev);
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

pub fn paramatricVariation(scale: f32, param: f32) !t.MatPack {
    std.debug.print("+++ param: {d}\n", .{param});
    const ortho_window = m.mat_ortho(scale, -scale, scale, -scale, 20, -20);

    const interm = t.MatPack{
        .proj = ortho_window.arr,
        .view = (try m.mat_look_at(
            .{ param, 0, -1 },
            .{ 0, 0, 0 },
            .{ 0, 1, 0 },
        )).arr,
    };
    return interm;
}
