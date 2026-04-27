const std = @import("std");
const vk = @import("third_party/vk.zig");
const gm = @import("graphics_context.zig");
const m = @import("math.zig");

pub const DescriptorPrep = struct {
    const Self = @This();
    d_set_layout_arr: std.ArrayList(vk.DescriptorSetLayout) = .empty,
    d_set_arr: std.ArrayList(vk.DescriptorSet) = .empty,
    buff_arr: std.ArrayList(?gm.BufferData) = .empty,

    gc: *const gm.GraphicsContext,
    _d_set_layout: ?vk.DescriptorSetLayout = null,
    _d_pool: ?vk.DescriptorPool = null,

    set_binding: u32,
    set_type: vk.DescriptorType,

    fn dsetLayout(
        devk: vk.DeviceProxy,
        binding: u32,
        set_type: vk.DescriptorType,
        sh_stage_flags: vk.ShaderStageFlags,
        arr_size: ?u32,
    ) !vk.DescriptorSetLayout {
        var bindless: bool = false;
        if (arr_size) |size| {
            if (size > 1) bindless = true;
        }
        if (bindless) {
            std.debug.print("+++ binding size is {d}\n", .{arr_size.?});
        }

        const _bind = vk.DescriptorSetLayoutBinding{
            .binding = binding,
            .descriptor_count = if (bindless) arr_size.? else 1,
            .descriptor_type = set_type,
            .p_immutable_samplers = null, // for textures ?
            .stage_flags = sh_stage_flags,
        };
        const binding_flgs: vk.DescriptorBindingFlags = .{
            .partially_bound_bit = true,
            .variable_descriptor_count_bit = true,
            .update_after_bind_bit = true,
        };
        const flags_info: vk.DescriptorSetLayoutBindingFlagsCreateInfo = .{
            .p_binding_flags = @ptrCast(&binding_flgs),
            .binding_count = 1,
        };
        const create_flags: vk.DescriptorSetLayoutCreateFlags = .{
            .update_after_bind_pool_bit = true,
        };

        const dslci: vk.DescriptorSetLayoutCreateInfo = .{
            .p_bindings = @ptrCast(&_bind),
            .flags = if (bindless) create_flags else .{},
            .binding_count = 1,
            .p_next = if (bindless) &flags_info else null,
        };

        return devk.createDescriptorSetLayout(&dslci, null);
    }
    pub fn init(
        alloc: std.mem.Allocator,
        gc: *const gm.GraphicsContext,
        frame_copies_num: usize,
        using: gm.baked.DSetInit,
        data_info: gm.baked.DSetDataInfo,
        bindless_size: ?u32,
    ) !Self {
        const len_u32: u32 = @intCast(frame_copies_num);

        var self: Self = .{
            .gc = gc,
            .set_binding = data_info.binding,
            .set_type = using.usage.descriptor_type,
        };
        const arr_size: u32 = bindless_size orelse 1;
        const bindless: bool = bindless_size != null;

        //dynamic arrays alloc
        const devk = self.gc.dev;
        errdefer self.deinit(alloc);
        try self.d_set_layout_arr.resize(alloc, frame_copies_num);
        try self.buff_arr.resize(alloc, frame_copies_num);
        try self.d_set_arr.resize(alloc, frame_copies_num);

        //binding layout
        self._d_set_layout = try Self.dsetLayout(devk, //
            self.set_binding, self.set_type, //
            using.shader_stage, arr_size);

        for (0..frame_copies_num) |i| {
            self.d_set_layout_arr.items[i] = self._d_set_layout.?;
            self.buff_arr.items[i] = null;
            if (data_info.element_size == 0) continue;

            self.buff_arr.items[i] = try gm.createBuffer(
                self.gc,
                using.memory_property,
                using.usage.usage_flag,
                data_info.element_size * data_info.num,
            );
        }

        // allocate from pool
        const pool_capacity = len_u32 * if (bindless_size) |bs| bs else 1;

        const p_size: []const vk.DescriptorPoolSize = &.{.{
            .type = self.set_type,
            .descriptor_count = pool_capacity,
        }};

        // std.debug.print("+++ pool is {s}\n", .{@tagName(p_size.type)});

        const pool_flags: vk.DescriptorPoolCreateFlags = .{
            .update_after_bind_bit = true,
        };

        self._d_pool = try self.gc.dev.createDescriptorPool(&vk.DescriptorPoolCreateInfo{
            .s_type = .descriptor_pool_create_info,
            .flags = pool_flags,
            .p_pool_sizes = p_size.ptr,
            .pool_size_count = @intCast(p_size.len),
            .max_sets = len_u32,
        }, null);

        // eg. "arr_size" bindles textures
        const variable_count: vk.DescriptorSetVariableDescriptorCountAllocateInfo = .{
            .descriptor_set_count = 1,
            .p_descriptor_counts = @ptrCast(&arr_size),
        };

        try self.gc.dev.allocateDescriptorSets(
            &vk.DescriptorSetAllocateInfo{
                .s_type = .descriptor_set_allocate_info,
                .descriptor_pool = self._d_pool.?,
                .descriptor_set_count = len_u32,
                .p_set_layouts = self.d_set_layout_arr.items.ptr,
                .p_next = if (bindless) @ptrCast(&variable_count) else null,
            },
            self.d_set_arr.items.ptr,
        );

        // specify data
        // var hmm: std.ArrayList(vk.WriteDescriptorSet) = .empty;

        for (0..frame_copies_num) |i| {
            if (self.set_type != .combined_image_sampler) {
                const buf_info = vk.DescriptorBufferInfo{
                    .buffer = self.buff_arr.items[i].?.dvk_bfr,
                    .range = data_info.element_size, // relevent for dynamics offset but not exactly the same as single instance data
                    .offset = 0,
                };
                const write_ops: []const vk.WriteDescriptorSet = &.{vk.WriteDescriptorSet{
                    .s_type = .write_descriptor_set,
                    .dst_set = self.d_set_arr.items[i],
                    .dst_binding = data_info.binding,
                    .dst_array_element = 0,
                    .descriptor_type = using.usage.descriptor_type,
                    .descriptor_count = 1,
                    .p_buffer_info = @ptrCast(&buf_info),
                    .p_image_info = &.{},
                    .p_texel_buffer_view = &.{},
                }};
                self.gc.dev.updateDescriptorSets(m.uinty(write_ops.len), write_ops.ptr, 0, null);
            }
        }

        return self;
    }

    pub fn updateTexture(self: *Self, idx: usize, img: *const gm.RGBImage, array_idx: ?u32) void {
        const img_info = vk.DescriptorImageInfo{
            .image_layout = .shader_read_only_optimal,
            .image_view = img.vk_img_view.?,
            .sampler = img.vk_sampler.?,
        };
        const write_image_dsc_set = vk.WriteDescriptorSet{
            .dst_set = self.d_set_arr.items[idx],
            .dst_binding = self.set_binding,
            .dst_array_element = if (array_idx) |i| i else 0,
            .descriptor_type = self.set_type,
            .descriptor_count = 1,
            .p_buffer_info = &.{},
            .p_image_info = @ptrCast(&img_info),
            .p_texel_buffer_view = &.{},
        };
        self.gc.dev.updateDescriptorSets(1, @ptrCast(&write_image_dsc_set), 0, null);
    }

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
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
