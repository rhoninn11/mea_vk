const vk = @import("vulkan-zig");
const gm = @import("../graphics_context.zig");

const GraphicsContext = gm.GraphicsContext;

pub fn imgMemTypeInfer(gc: *const GraphicsContext, flags: vk.MemoryPropertyFlags) !u32 {
    const img_extent: vk.Extent3D = .{ .height = 64, .width = 64, .depth = 1 };

    const Pair = struct { usage: vk.ImageUsageFlags, format: vk.Format };
    const configs: []const Pair = &.{
        Pair{
            .format = .d32_sfloat,
            .usage = .{ .depth_stencil_attachment_bit = true, .transfer_src_bit = true },
        },
        Pair{
            .format = .a8b8g8r8_srgb_pack32,
            .usage = .{ .color_attachment_bit = true, .transfer_src_bit = true },
        },
    };

    var reqs: [configs.len]vk.MemoryRequirements = undefined;

    var base: vk.ImageCreateInfo = .{
        .image_type = .@"2d",
        .format = undefined,
        .extent = img_extent,
        .tiling = .optimal,
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .usage = undefined,
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    };

    for (0.., configs) |i, config| {
        base.usage = config.usage;
        base.format = config.format;

        const img = try gc.dev.createImage(&base, null);
        defer gc.dev.destroyImage(img, null);

        reqs[i] = gc.dev.getImageMemoryRequirements(img);
    }

    const basic_type_idx = try gc.findMemoryTypeIndex(reqs[0].memory_type_bits, flags);

    for (reqs) |req| {
        const type_idx = try gc.findMemoryTypeIndex(req.memory_type_bits, flags);
        if (basic_type_idx != type_idx) {
            return error.different_images_uses_different_memory_type;
        }
    }
    return basic_type_idx;
}

const std = @import("std");
const Shelf = std.AutoHashMap(vk.Image, SpotInfo);

const SpotInfo = struct {
    block_size: u16,
};

pub const LinearImageAllocator = struct {
    const max_elements: comptime_int = 256;
    const Self = @This();

    dev_mem_idx: u32,
    dev_mem: vk.DeviceMemory,

    alloc: std.mem.Allocator,
    store: Shelf,
    stored_elements: u8 = 0,

    // book keeping
    beg: u64 = 0,
    end: u64 = 0,
    total: u64,

    verbose: bool = false,

    pub fn deinit(self: *LinearImageAllocator, gc: *const GraphicsContext) void {
        gc.dev.freeMemory(self.dev_mem, null);
        self.store.deinit();
    }

    pub fn init(
        gpa: std.mem.Allocator,
        gc: *const GraphicsContext,
        flags: vk.MemoryPropertyFlags,
    ) !LinearImageAllocator {
        const mem_idx = try imgMemTypeInfer(gc, flags);
        const total_size = 256 * 1024 * 1024; //256 MB
        const mem = try gc.dev.allocateMemory(&.{
            .s_type = .memory_allocate_info,

            .allocation_size = total_size,
            .memory_type_index = mem_idx,
        }, null);

        var map = Shelf.init(gpa);
        try map.ensureTotalCapacity(Self.max_elements);

        return LinearImageAllocator{
            .dev_mem_idx = mem_idx,
            .dev_mem = mem,

            .alloc = gpa,
            .store = map,

            .total = total_size,
        };
    }

    pub fn imgAlloc(self: *LinearImageAllocator, gc: *const GraphicsContext, img: vk.Image) !void {
        const block_size = 64 * 1024;
        const new_img_reqs = gc.dev.getImageMemoryRequirements(img);

        const missed_by: u64 = @mod(self.end, new_img_reqs.alignment);

        if (missed_by != 0) {
            self.end += (new_img_reqs.alignment - missed_by);
        }

        const beg_of_alloc = self.end;
        const end_of_alloc = beg_of_alloc + new_img_reqs.size;
        if (end_of_alloc > self.total) {
            return error.OutOfMemory;
        }

        var blocks = new_img_reqs.size / block_size;
        if (@mod(new_img_reqs.size, block_size) != 0) blocks += 1;

        const kb = new_img_reqs.size / 1024;
        const real_kb = blocks * block_size / 1024;

        try gc.dev.bindImageMemory(img, self.dev_mem, beg_of_alloc);
        if (self.stored_elements == Self.max_elements - 1) return error.no_more_slots;

        try self.store.put(img, .{ .block_size = @intCast(blocks) });

        self.stored_elements += 1;
        self.end = end_of_alloc;
        if (self.verbose) {
            std.debug.print("new img alloc: {d} kB | {d} kB | {d} blocks | {d}B alignment | {d} alloc num \n", .{ //
                kb, real_kb, blocks, new_img_reqs.alignment, self.stored_elements,
            });
        }
    }

    pub fn imgFree(self: *LinearImageAllocator, img: vk.Image) void {
        if (self.verbose) {
            if (self.store.get(img)) |hmm| {
                std.debug.print("freeining image that holds {d} 64k memory blocks\n", .{hmm.block_size});
            }
        }
    }
};
