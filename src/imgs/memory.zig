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

pub fn MemBitmap(block_num: u16, block_size: u64) type {
    const mask_size = 8;
    std.debug.assert(@rem(block_num, mask_size) == 0);

    return struct {
        const Self = @This();
        const elements = block_num / mask_size;

        bitmap: [elements]u8,
        pub fn init() Self {
            var me: Self = undefined;
            @memset(me.bitmap[0..], 0);
            return me;
        }

        pub const MarkOp = enum(u8) { unset = 0, set };

        pub fn allocateSpot(self: *Self, req: vk.MemoryRequirements) !LocDesc {
            const spot = try self.propperSpot(req);
            self.markSpot(spot, .set);
            return spot;
        }

        pub fn freeSpot(self: *Self, spot: LocDesc) void {
            self.markSpot(spot, .unset);
        }

        pub fn count(self: *Self) u16 {
            var full_num: u16 = 0;
            for (self.bitmap) |mask| {
                for (0..8) |shift| {
                    if (((mask << @truncate(shift)) & 128) == 128) {
                        full_num += 1;
                    }
                }
            }
            return full_num;
        }

        fn markSpot(self: *Self, spot: LocDesc, mark: MarkOp) void {
            for (0..spot.num) |i| {
                const block_idx = spot.blk_idx + i;
                const byte_idx = block_idx / mask_size;
                const shift = @mod(block_idx, mask_size);

                const l_bit: u8 = 128;

                switch (mark) {
                    .set => self.bitmap[byte_idx] |= @as(u8, l_bit >> @truncate(shift)),
                    .unset => self.bitmap[byte_idx] &= ~@as(u8, l_bit >> @truncate(shift)),
                }
            }
        }

        fn requiredBlocks(size: u64) u16 {
            var blocks = size / block_size;
            if (@mod(size, block_size) != 0) blocks += 1;
            return @truncate(blocks);
        }

        pub fn alignDelta(block: u64, alignment: u64) u64 {
            const addr = @as(u64, block) * block_size;
            const missed_by = @mod(addr, alignment);
            if (missed_by != 0) {
                return alignment - missed_by;
            }
            return 0;
        }

        fn propperSpot(self: *Self, req: vk.MemoryRequirements) !LocDesc {
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
                            const loc = LocDesc{
                                .blk_idx = block_idx,
                                .num = block_needed_real,
                            };

                            return loc;
                        }
                        block_needed = block_needed_real;
                    }
                }
            }
            return error.OutOfBlocks;
        }
    };
}

test "setin and restin" {
    const bs = 16;
    const max_loop = 16;
    var storage = MemBitmap(32, bs).init();

    const first_half = LocDesc{
        .blk_idx = 0,
        .num = 16,
    };

    try std.testing.expect(storage.count() == 0);
    storage.markSpot(first_half, .set);
    try std.testing.expect(storage.count() == first_half.num);
    storage.markSpot(first_half, .unset);
    try std.testing.expect(storage.count() == 0);

    const non_important = 0;
    const basic = vk.MemoryRequirements{
        .memory_type_bits = non_important,
        .alignment = 1,
        .size = bs * 2,
    };
    var index: [max_loop]LocDesc = undefined;
    var succes: u8 = 0;
    for (0..max_loop) |_| {
        index[succes] = storage.allocateSpot(basic) catch {
            break;
        };
        succes += 1;
    }

    try std.testing.expectEqual(16, succes);
    try std.testing.expectEqual(32, storage.count());

    for (0..succes) |i| {
        storage.freeSpot(index[i]);
    }

    try std.testing.expectEqual(0, storage.count());
}

pub const LinearImageAllocator = struct {
    const total_size = 256 * 1024 * 1024; //256 MB
    const block_size = 64 * 1024; //64 KB
    const block_num = total_size / block_size;

    const Self = @This();
    const Bitmap = MemBitmap(block_num, block_size);

    dev_mem_idx: u32,
    dev_mem: vk.DeviceMemory,
    bitmap: Bitmap,

    pub fn deinit(self: *LinearImageAllocator, gc: *const GraphicsContext) void {
        gc.dev.freeMemory(self.dev_mem, null);
    }

    pub fn init(
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
            .bitmap = .init(),
        };
    }

    pub fn imgAlloc(self: *LinearImageAllocator, gc: *const GraphicsContext, img: vk.Image) !LocDesc {
        const req = gc.dev.getImageMemoryRequirements(img);
        const spot = try self.bitmap.allocateSpot(req);
        const alignment_delta = Bitmap.alignDelta(spot.blk_idx, req.alignment);
        const offset = @as(u64, block_size) * spot.blk_idx + alignment_delta;

        std.debug.print("+++ offset is {d} alignment is {d}\n", .{ offset, req.alignment });
        try gc.dev.bindImageMemory(img, self.dev_mem, offset);

        return spot;
    }

    pub fn imgFree(self: *LinearImageAllocator, spot: LocDesc) void {
        self.bitmap.freeSpot(spot);
    }
};
