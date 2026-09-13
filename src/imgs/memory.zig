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
const Shelf = std.AutoHashMap(vk.Image, LocDesc);

pub const LocDesc = struct {
    blk_idx: u16,
    num: u16,
};

pub const LinearImageAllocator = struct {
    const total_size = 256 * 1024 * 1024; //256 MB
    const block_size = 64 * 1024;
    const block_num = total_size / block_size;
    const mask_bytes = block_num / 8;

    const Self = @This();

    dev_mem_idx: u32,
    dev_mem: vk.DeviceMemory,

    alloc: std.mem.Allocator,
    stored_elements: u8 = 0,

    // book keeping
    beg: u64 = 0,
    end: u64 = 0,
    total: u64,

    verbose: bool = false,
    bitmap: [mask_bytes]u8,

    pub fn deinit(self: *LinearImageAllocator, gc: *const GraphicsContext) void {
        gc.dev.freeMemory(self.dev_mem, null);
    }

    pub fn init(
        gpa: std.mem.Allocator,
        gc: *const GraphicsContext,
        flags: vk.MemoryPropertyFlags,
    ) !LinearImageAllocator {
        const mem_idx = try imgMemTypeInfer(gc, flags);
        const mem = try gc.dev.allocateMemory(&.{
            .allocation_size = total_size,
            .memory_type_index = mem_idx,
        }, null);

        return LinearImageAllocator{
            .dev_mem_idx = mem_idx,
            .dev_mem = mem,

            .alloc = gpa,

            .total = total_size,
            .bitmap = undefined,
        };
    }

    fn findSpot(self: *LinearImageAllocator, req: vk.MemoryRequirements) !LocDesc {
        const blocks = requiredBlocks(req.size);
        var block_idx: u16 = 0;
        var blocks_free: u16 = 0;
        var block_needed: u16 = blocks;
        for (self.bitmap, 0..) |mask, i| {
            for (0..8) |jj| {
                const index = i * 8 + jj;
                if (((mask << @truncate(jj)) & 128) == 128) {
                    block_needed = blocks;
                    block_idx = @truncate(index + 1);
                    blocks_free = 0;
                } else {
                    blocks_free += 1;
                }

                if (blocks_free >= block_needed) {
                    const delta = alignDelta(block_idx, req.alignment);
                    const block_needed_real = requiredBlocks(req.size + delta);
                    if (block_needed_real == block_needed) {
                        return LocDesc{
                            .blk_idx = block_idx,
                            .num = block_needed_real,
                        };
                    }
                    block_needed = block_needed_real;
                }
            }
        }
        return error.outofmem;
    }

    fn requiredBlocks(size: u64) u16 {
        var blocks = size / block_size;
        if (@mod(size, block_size) != 0) blocks += 1;
        return @truncate(blocks);
    }

    fn alignDelta(block: u64, alignment: u64) u64 {
        const addr = @as(u64, block) * block_size;
        const missed_by = @mod(addr, alignment);
        if (missed_by != 0) {
            return alignment - missed_by;
        }
        return 0;
    }

    pub fn imgAlloc2(self: *LinearImageAllocator, gc: *const GraphicsContext, img: vk.Image) !LocDesc {
        const require = gc.dev.getImageMemoryRequirements(img);

        const memory_spot = try self.findSpot(require);

        const offset_align = alignDelta(memory_spot.blk_idx, require.alignment);
        const offset_mem = @as(u64, memory_spot.blk_idx) * block_size + offset_align;

        try gc.dev.bindImageMemory(img, self.dev_mem, offset_mem);
        self.markSpot(memory_spot, .set);
        return memory_spot;
    }

    pub fn imgFree2(self: *LinearImageAllocator, spot: LocDesc) void {
        self.markSpot(spot, .unset);
    }

    const MarkOp = enum(u8) { unset = 0, set };

    pub fn markSpot(self: *LinearImageAllocator, spot: LocDesc, mark: MarkOp) void {
        for (0..spot.num) |i| {
            const block_idx = spot.blk_idx + i;
            const byte_idx = block_idx / 8;
            const shift = @mod(block_idx, 8);

            const l_bit: u8 = 128;

            switch (mark) {
                .set => self.bitmap[byte_idx] |= @as(u8, l_bit >> @truncate(shift)),
                .unset => self.bitmap[byte_idx] &= ~@as(u8, l_bit >> @truncate(shift)),
            }
        }
    }

    pub fn imgAlloc(self: *LinearImageAllocator, gc: *const GraphicsContext, img: vk.Image) !void {
        const require = gc.dev.getImageMemoryRequirements(img);

        var align_delta: u64 = 0;
        const missed_by: u64 = @mod(self.end, require.alignment);
        if (missed_by != 0) {
            align_delta = require.alignment - missed_by;
            self.end += align_delta;
        }

        const beg_of_alloc = self.end;
        const end_of_alloc = beg_of_alloc + require.size;
        if (end_of_alloc > self.total) {
            return error.OutOfMemory;
        }

        const memory_needed = align_delta + require.size;
        var blocks = memory_needed / block_size;
        if (@mod(memory_needed, block_size) != 0) blocks += 1;

        const kb = memory_needed / 1024;
        const real_kb = blocks * block_size / 1024;

        try gc.dev.bindImageMemory(img, self.dev_mem, beg_of_alloc);

        self.stored_elements += 1;
        self.end = end_of_alloc;
        if (self.verbose) {
            std.debug.print("new img alloc: {d} kB | {d} kB | {d} blocks | {d}B alignment | {d} alloc num \n", .{ //
                kb, real_kb, blocks, require.alignment, self.stored_elements,
            });
        }
    }

    pub fn imgFree(self: *LinearImageAllocator, img: vk.Image) void {
        if (self.verbose) {
            std.debug.print("freeining image that holds {d} 64k memory blocks\n", .{100});
            _ = img;
        }
    }
};
