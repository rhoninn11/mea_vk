const std = @import("std");
const vk = @import("vulkan-zig");
const gm = @import("graphics_context.zig");
const m = @import("math.zig");
const imgs = @import("imgs/imgs.zig");
const sht = @import("shaders/types.zig");

pub const ShadyGroup = struct {
    const Self = @This();
    const sets = 3;
    uniforms: DescriptorPrep,
    storage: DescriptorPrep,
    omnitex: DescriptorPrep,

    mayby_something_for_compute: DescriptorPrep = undefined,

    pub const Options = struct {
        atlas_size: u16,
        swapchain_lan: u8,
        ubo_size: u32,
        storag_size: u32,
    };

    pub fn deinit(self: *ShadyGroup, ctx: DsetCtx) void {
        self.uniforms.deinit(ctx);
        self.storage.deinit(ctx);
        self.omnitex.deinit(ctx);
    }

    pub fn init(ctx: DsetCtx, opt: Options) !Self {
        var self: Self = undefined;

        // TODO: alloc buffers before Dset Prep
        var dset_uniform: DescriptorPrep = try .init(
            ctx,
            opt.swapchain_lan,
            gm.baked.uniform_frag_vert_dyn,
            &.{.{ .binding = 0, .element_size = opt.ubo_size, .num = 16 }}, //shader.types.zig.GroupData
            null,
        );
        errdefer dset_uniform.deinit(ctx);

        // TODO: alloc buffers before Dset Prep
        var storage: DescriptorPrep = try .init(
            ctx,
            opt.swapchain_lan,
            gm.baked.storage_frag_vert,
            &.{
                .{ .binding = 0, .element_size = opt.storag_size, .num = 1 }, //shader.types.zig.PerInstance
                // .{ .binding = 1, .element_size = storage_b_sz, .num = 1 },
            },
            null,
        );
        errdefer storage.deinit(ctx);

        const dset_atlas: DescriptorPrep = try .init(
            ctx,
            1,
            gm.baked.texture_frag,
            &.{.{ .binding = 0 }},
            opt.atlas_size,
        );

        self.uniforms = dset_uniform;
        self.storage = storage;
        self.omnitex = dset_atlas;
        return self;
    }

    pub fn layout(self: *const Self) [sets]vk.DescriptorSetLayout {
        return .{
            self.uniforms._d_set_layout.?,
            self.storage._d_set_layout.?,
            self.omnitex._d_set_layout.?,
        };
    }
};

pub const DsetCtx = struct {
    gc: *const gm.GraphicsContext,
    gpa: std.mem.Allocator,
};

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

    const LayoutHl = struct {
        gc: *const gm.GraphicsContext,
        dsctype: vk.DescriptorType,
        stageflags: vk.ShaderStageFlags,

        fn dsetLayout(
            self: *const LayoutHl,
            infos: []const gm.baked.DSetDataInfo,
            arr_size: ?u32,
        ) !vk.DescriptorSetLayout {
            const SLOTS = 4;
            std.debug.assert(infos.len > 0);
            std.debug.assert(infos.len < SLOTS);

            var bindless: bool = false;
            if (arr_size) |size| {
                if (size > 1) bindless = true;
            }
            if (bindless) {
                std.debug.assert(infos.len == 1);
                std.debug.print("+++ binding size is {d}\n", .{arr_size.?});
            }

            const bindless_textures_flags: vk.DescriptorBindingFlags = .{
                .partially_bound_bit = true,
                .variable_descriptor_count_bit = true,
                .update_after_bind_bit = true,
            };
            const more_flags: vk.DescriptorSetLayoutBindingFlagsCreateInfo = .{
                .p_binding_flags = @ptrCast(&bindless_textures_flags),
                .binding_count = 1,
            };
            const more_flexibility: vk.DescriptorSetLayoutCreateFlags = .{
                .update_after_bind_pool_bit = true,
            };

            var slot_used: u8 = 0;
            var _bindings: [SLOTS]vk.DescriptorSetLayoutBinding = undefined;
            for (infos) |info| {
                _bindings[slot_used] = .{
                    .binding = info.binding,
                    .descriptor_count = if (bindless) arr_size.? else 1,
                    .descriptor_type = self.dsctype,
                    .p_immutable_samplers = null, // for textures ?
                    .stage_flags = self.stageflags,
                };
                slot_used += 1;
            }

            const dslci: vk.DescriptorSetLayoutCreateInfo = .{
                .p_next = if (bindless) &more_flags else null,
                .flags = if (bindless) more_flexibility else .{},
                .binding_count = slot_used,
                .p_bindings = @ptrCast(&_bindings),
            };

            return self.gc.dev.createDescriptorSetLayout(&dslci, null);
        }
    };
    const DSetInfo = gm.baked.DSetDataInfo;

    pub fn deinit(self: *Self, ctx: DsetCtx) void {
        const alloc = ctx.gpa;
        const gc = ctx.gc;
        if (self._d_pool) |d_pool| {
            gc.dev.destroyDescriptorPool(d_pool, null);
        }

        for (self.buff_arr.items) |possible_buff| {
            if (possible_buff) |buff| {
                buff.deinit(self.gc);
            }
        }

        if (self._d_set_layout) |layout| {
            gc.dev.destroyDescriptorSetLayout(layout, null);
        }

        self.d_set_arr.deinit(alloc);
        self.buff_arr.deinit(alloc);
        self.d_set_layout_arr.deinit(alloc);
    }

    pub fn init(
        ctx: DsetCtx,
        frame_copies_num: usize,
        using: gm.baked.DSetInit,
        data_info: []const DSetInfo,
        bindless_size: ?u32,
    ) !Self {
        std.debug.assert(data_info.len > 0);
        const len_u32: u32 = @intCast(frame_copies_num);

        const gc = ctx.gc;
        const gpa = ctx.gpa;

        var self: Self = .{
            .gc = gc,
            .set_binding = data_info[0].binding, // for writing bindless textures
            .set_type = using.usage.descriptor_type,
        };
        errdefer self.deinit(ctx);

        const laytr = LayoutHl{
            .gc = gc,
            .dsctype = using.usage.descriptor_type,
            .stageflags = using.shader_stage,
        };

        const arr_size: u32 = bindless_size orelse 1;
        const bindless: bool = bindless_size != null;

        //dynamic arrays alloc
        try self.d_set_layout_arr.resize(gpa, frame_copies_num);
        try self.buff_arr.resize(gpa, frame_copies_num);
        try self.d_set_arr.resize(gpa, frame_copies_num);

        //binding layout
        self._d_set_layout = try laytr.dsetLayout(data_info, arr_size);

        for (0..frame_copies_num) |i| {
            self.d_set_layout_arr.items[i] = self._d_set_layout.?;
            self.buff_arr.items[i] = null;
            if (data_info[0].element_size == 0) continue;

            var total_buffer_sz: u32 = 0;
            for (data_info) |di| total_buffer_sz += di.element_size * di.num;

            self.buff_arr.items[i] = try gm.BufferData.init(
                self.gc,
                using.memory_property,
                using.usage.usage_flag,
                total_buffer_sz,
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
        const dset_pool_opt = vk.DescriptorPoolCreateInfo{
            .flags = pool_flags,
            .p_pool_sizes = p_size.ptr,
            .pool_size_count = @intCast(p_size.len),
            .max_sets = len_u32,
        };

        const could_be_more_global = try self.gc.dev.createDescriptorPool(&dset_pool_opt, null);
        errdefer self.gc.dev.destroyDescriptorPool(could_be_more_global, null);
        self._d_pool = could_be_more_global;

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

        self.writeContent(@truncate(frame_copies_num), data_info[0]);

        return self;
    }

    fn writeContent(self: *Self, times_n: u8, info: DSetInfo) void {
        if (self.set_type == .combined_image_sampler) return;

        //for each chain link
        for (0..times_n) |i| {
            const buf_info = vk.DescriptorBufferInfo{
                .buffer = self.buff_arr.items[i].?.dvk_bfr,
                .range = info.element_size, // relevent for dynamics offset but not exactly the same as single instance data
                .offset = 0,
            };
            const write_ops: []const vk.WriteDescriptorSet = &.{vk.WriteDescriptorSet{
                .s_type = .write_descriptor_set,
                .dst_set = self.d_set_arr.items[i],
                .dst_binding = info.binding,
                .dst_array_element = 0,
                .descriptor_type = self.set_type,
                .descriptor_count = 1,
                .p_buffer_info = @ptrCast(&buf_info),
                .p_image_info = &.{},
                .p_texel_buffer_view = &.{},
            }};
            self.gc.dev.updateDescriptorSets(write_ops, &.{});
        }
    }

    pub fn updateTexture(self: *Self, idx: usize, img: *const imgs.VkImage, array_idx: ?u32) void {
        const img_info = vk.DescriptorImageInfo{
            .image_layout = .shader_read_only_optimal,
            .image_view = img.vk_img_view.?,
            .sampler = img.vk_sampler.?,
        };
        const write_image_dsc_set = &.{vk.WriteDescriptorSet{
            .dst_set = self.d_set_arr.items[idx],
            .dst_binding = self.set_binding,
            .dst_array_element = if (array_idx) |i| i else 0,
            .descriptor_type = self.set_type,
            .descriptor_count = 1,
            .p_buffer_info = &.{},
            .p_image_info = @ptrCast(&img_info),
            .p_texel_buffer_view = &.{},
        }};
        self.gc.dev.updateDescriptorSets(write_image_dsc_set, &.{});
    }

    pub fn instances(self: *const Self, link_id: u8) [*]sht.PerInstance {
        std.debug.assert(self.set_type == .storage_buffer);

        const storage = self.buff_arr.items[link_id].?;
        const mapping: [*]sht.PerInstance = @ptrCast(@alignCast(storage.mapping.?));
        return mapping;
    }
};
