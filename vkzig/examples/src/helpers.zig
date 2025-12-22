const std = @import("std");
const baked = @import("baked.zig");

const vk = @import("third_party/vk.zig");

const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Allocator = std.mem.Allocator;

pub const DescriptorPrep = struct {
    const Self = @This();
    d_set_layout_arr: std.ArrayList(vk.DescriptorSetLayout) = .empty,
    d_set_arr: std.ArrayList(vk.DescriptorSet) = .empty,
    buff_arr: std.ArrayList(?GraphicsContext.BufferData) = .empty,

    _gc_ref: *const GraphicsContext,
    _d_set_layout: ?vk.DescriptorSetLayout = undefined,
    _d_pool: ?vk.DescriptorPool = undefined,

    pub fn init(
        alloc: Allocator,
        _gc: *const GraphicsContext,
        len: usize,
        using: baked.DSetInit,
        with: baked.UniformInfo,
    ) !Self {
        const len_u32: u32 = @intCast(len);

        var s = Self{ ._gc_ref = _gc };
        errdefer s.deinit(alloc);
        try s.d_set_layout_arr.resize(alloc, len);
        try s.buff_arr.resize(alloc, len);
        try s.d_set_arr.resize(alloc, len);

        const _bind = vk.DescriptorSetLayoutBinding{
            .p_immutable_samplers = null, // for textures ?
            .stage_flags = using.shader_stage,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .binding = with.location, // w sensie, że lokacja 0?
        };

        // first important element needed later
        s._d_set_layout = try _gc.dev.createDescriptorSetLayout(&.{
            .s_type = .descriptor_set_layout_create_info,
            .p_bindings = @ptrCast(&_bind),
            .binding_count = 1,
        }, null);

        for (0..len) |i| {
            s.d_set_layout_arr.items[i] = s._d_set_layout.?;
            s.buff_arr.items[i] = null;
            s.buff_arr.items[i] = try s._gc_ref.createBuffer(
                using.memory_property,
                with.size,
                using.buffer_usage,
            );
        }

        const p_size = vk.DescriptorPoolSize{
            .type = .uniform_buffer,
            .descriptor_count = len_u32,
        };

        s._d_pool = try s._gc_ref.dev.createDescriptorPool(&vk.DescriptorPoolCreateInfo{
            .s_type = .descriptor_pool_create_info,
            .p_pool_sizes = @ptrCast(&p_size),
            .pool_size_count = 1,
            .max_sets = len_u32,
        }, null);

        // allocation destroyed with pool
        try s._gc_ref.dev.allocateDescriptorSets(
            &vk.DescriptorSetAllocateInfo{
                .s_type = .descriptor_set_allocate_info,
                .descriptor_pool = s._d_pool.?,
                .descriptor_set_count = len_u32,
                .p_set_layouts = s.d_set_layout_arr.items.ptr,
            },
            s.d_set_arr.items.ptr,
        );
        for (0..len) |i| {
            const buf_info = vk.DescriptorBufferInfo{
                .buffer = s.buff_arr.items[i].?.buffer,
                .range = with.size,
                .offset = 0,
            };
            const w_dsc_set = vk.WriteDescriptorSet{
                .s_type = .write_descriptor_set,
                .dst_set = s.d_set_arr.items[i],
                .dst_binding = with.location,
                .dst_array_element = 0,
                .descriptor_type = .uniform_buffer,
                .descriptor_count = 1,
                .p_buffer_info = @ptrCast(&buf_info),
                .p_image_info = &.{},
                .p_texel_buffer_view = &.{},
            };
            s._gc_ref.dev.updateDescriptorSets(1, @ptrCast(&w_dsc_set), 0, null);
        }

        return s;
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        if (self._d_pool) |d_pool| {
            self._gc_ref.dev.destroyDescriptorPool(d_pool, null);
        }

        for (self.buff_arr.items) |possible_buff| {
            if (possible_buff) |buff| {
                buff.deinit(self._gc_ref.dev);
            }
        }

        if (self._d_set_layout) |layout| {
            self._gc_ref.dev.destroyDescriptorSetLayout(layout, null);
        }

        self.d_set_arr.deinit(alloc);
        self.buff_arr.deinit(alloc);
        self.d_set_layout_arr.deinit(alloc);
    }
};
