const std = @import("std");
const vk = @import("vulkan-zig");

const gm = @import("graphics_context.zig");
const GraphicsContext = gm.GraphicsContext;

const MemProx = struct {
    mem: vk.DeviceMemory,
    size: u64,
};

pub const BufferData = struct {
    buffvk: vk.Buffer,
    dvk_mem: vk.DeviceMemory,
    mapping: ?*anyopaque,

    pub fn deinit(self: *const BufferData, gc: *const GraphicsContext) void {
        const dev_prox = gc.dev_api;
        if (self.mapping) |_| dev_prox.unmapMemory(self.dvk_mem);
        dev_prox.destroyBuffer(self.buffvk, null);
        dev_prox.freeMemory(self.dvk_mem, null);
    }

    pub fn init(
        gc: *const GraphicsContext,
        mem_flags: vk.MemoryPropertyFlags,
        usage: vk.BufferUsageFlags,
        bsize: u64,
    ) !BufferData {
        const devk = gc.dev_api;
        const default_size = bsize;

        const bfr = try devk.createBuffer(&vk.BufferCreateInfo{
            .size = default_size,
            .usage = usage,
            .sharing_mode = .exclusive,
        }, null);

        // TODO: propably few memory pools based on "imag" image
        const prox = try getMemory(gc, bfr, mem_flags);
        errdefer unreachable;

        var mapping: ?*anyopaque = null;
        if (mem_flags.host_visible) {
            mapping = try devk.mapMemory(prox.mem, 0, prox.size, .{});
        }
        return BufferData{
            .buffvk = bfr,
            .dvk_mem = prox.mem,
            .mapping = mapping,
        };
    }

    fn getMemory(
        gc: *const GraphicsContext,
        bfr: vk.Buffer,
        mem_flags: vk.MemoryPropertyFlags,
    ) !MemProx {
        const r = gc.dev_api.getBufferMemoryRequirements(bfr);
        // INFO: requirements propably will be bigger then original size

        const dev_mem = try gc.allocate(r, mem_flags);
        errdefer gc.dev_api.freeMemory(dev_mem, null);

        try gc.dev_api.bindBufferMemory(bfr, dev_mem, 0);

        return MemProx{
            .mem = dev_mem,
            .size = r.size,
        };
    }

    pub fn memMapping(self: *BufferData) [*]u8 {
        const mapping: [*]u8 = @ptrCast(@alignCast(self.mapping));
        return mapping;
    }
};

const memory = @import("memory.zig");
pub const BufferData2 = struct {
    const Self = @This();
    mmap: [*]u8,
    buffvk: vk.Buffer,
    loc: memory.LocDesc,

    pub fn deinit(self: *Self, gc: *const GraphicsContext) void {
        gc.dev_api.destroyBuffer(self.buffvk, null);
    }

    pub fn init(
        gc: *const GraphicsContext,
        staga: *memory.StagerAllocator,
        mem_flags: vk.MemoryPropertyFlags,
        usage: vk.BufferUsageFlags,
        bsize: u64,
    ) !Self {
        std.debug.assert(mem_flags.host_visible);

        const create_b = vk.BufferCreateInfo{
            .size = bsize,
            .usage = usage,
            .sharing_mode = .exclusive,
        };

        const buff = try gc.dev_api.createBuffer(&create_b, null);
        errdefer gc.dev_api.destroyBuffer(buff, null);

        const loc = try staga.stageAlloc(gc, buff);
        return .{
            .mmap = staga.memMapping(loc),
            .buffvk = buff,
            .loc = loc,
        };
    }
};
