const std = @import("std");
const utils = @import("utils.zig");
const meagen = @import("gen/meagen.pb.zig");
const addon = @import("addons.zig");
const dset = @import("dset.zig");
const motion = @import("motion.zig");
const sht = @import("shaders/types.zig");
const shu = @import("shaders/utils.zig");

const m = @import("math.zig");
const input = @import("input.zig");

const Errorset = error{
    constrained,
};

inline fn info(g: sht.GridSize, t: meagen.ImgType) meagen.ImgInfo {
    return meagen.ImgInfo{
        .width = g.w,
        .height = g.h,
        .img_type = t,
    };
}

pub fn spawnMonoImg(alloc: std.mem.Allocator, g: sht.GridSize) !meagen.Image {
    var rng = try utils.DefaultRng();
    var pixels = try alloc.alloc(u8, g.total);

    for (0..g.h) |y| {
        for (0..g.w) |xx| {
            const gdx = shu.gridI(g, xx, y);
            const randval = rng.int(u8);
            pixels[gdx] = randval;
        }
    }

    return meagen.Image{
        .info = info(g, meagen.ImgType.MONO),
        .pixels = pixels,
    };
}

const uHdr = extern union {
    byte: [2]u8,
    hdr: u16,
};

pub inline fn trygZero1(val: f32) f32 {
    return (val + 1) * 0.5;
}

pub inline fn tryg2u16f(val: f32) f32 {
    return ((val + 1) * 0.5 * ((1 << 16) - 3) + 1);
}

pub fn xyTrygHdr(alloc: std.mem.Allocator, g: sht.GridSize) !meagen.Image {
    var pixels = try alloc.alloc(u8, g.total * @sizeOf(u16));
    const fy: f32 = 1;
    const f1y: f32 = 0.12;
    const fx: f32 = 1;
    for (0..g.h) |y| {
        const y_phase = m.floaty(y) / 16; // give him some samples per cycle
        const y_sin = @sin(y_phase * std.math.tau * fy);
        const y_ufit = tryg2u16f(y_sin);

        const yl = trygZero1(@sin(y_phase * std.math.tau * f1y));
        // _ = yl_sin;

        for (0..g.w) |xx| {
            const x_phase = m.floaty(xx) / 16;
            const x_sin = @sin(x_phase * std.math.tau * fx);
            const x_ufit = tryg2u16f(x_sin);

            const combined = x_ufit * 0.5 + y_ufit * 0.5 * yl;
            const hdrval: uHdr = .{ .hdr = @as(u16, @intFromFloat(combined)) };

            const gdx = shu.gridI(g, xx, y);
            pixels[gdx * 2] = hdrval.byte[0];
            pixels[gdx * 2 + 1] = hdrval.byte[1];
        }
    }

    return meagen.Image{
        .info = info(g, meagen.ImgType.DUO),
        .pixels = pixels,
    };
}

pub fn findSedes(io: std.Io, here: []const u8) ![]const u8 {
    const serdes_dir = try std.Io.Dir.cwd().openDir(
        io,
        here,
        .{ .iterate = true },
    );
    defer serdes_dir.close(io);

    var iterator = serdes_dir.iterate();

    while (try iterator.next(io)) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".serdes")) {
            return entry.name;
        }
    }
    return error.NoSerdes;
}

const PathList = std.ArrayList([]u8);
const defPathListSize = 32;
pub fn findExt(io: std.Io, arena: std.mem.Allocator, here: []const u8, ext: []const u8) !PathList {
    const serdes_dir = try std.Io.Dir.cwd().openDir( //
        io, here, .{ .iterate = true });
    defer serdes_dir.close(io);

    var iterator = serdes_dir.iterate();

    var found_files: std.ArrayList([]u8) = try .initCapacity(arena, defPathListSize);
    while (try iterator.next(io)) |entry| {
        if (std.mem.endsWith(u8, entry.name, ext)) {
            const full_path = try std.fs.path.join(arena, &.{ here, entry.name });
            try found_files.append(arena, full_path);
        }
    }

    if (found_files.items.len == 0) return error.NoFile;

    return found_files;
}
fn stringCompGrow(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

pub const SearchResult = struct {
    const SliceAlign = @alignOf([]const u8);
    file_packs: []const []const []const u8,
    file_paths: []const []const u8,
    chars: []const u8,

    pub fn deinit(self: SearchResult, gpa: std.mem.Allocator) void {
        gpa.free(self.file_packs);
        gpa.free(self.file_paths);
        gpa.free(self.chars);
    }
};

inline fn fileSearchZip(
    io: std.Io,
    gpa: std.mem.Allocator,
    prefix: []const u8,
    comptime exts_zip: []const []const u8,
) !void {
    const N = exts_zip.len;

    var arana: std.heap.ArenaAllocator = .init(gpa);
    defer arana.deinit();

    const aa = arana.allocator();
    var zipLists: [N]PathList = undefined;

    for (0..N) |i| {
        zipLists[i] = findExt(io, aa, prefix, exts_zip[0]) catch {
            return error.NoReults;
        };
    }

    const fresh_val: [N]?u32 = .{null} ** N;
    var found_map: std.StringHashMap([N]?u32) = .init(aa);
    try found_map.ensureTotalCapacity(32);

    for (zipLists, 0..) |list, ext_idx| {
        for (list.items, 0..) |element, list_idx| {
            const almost_key = std.mem.trimStart(u8, element, prefix);
            const key = std.mem.trimEnd(u8, almost_key, exts_zip[ext_idx]);

            if (found_map.getPtr(key) == null) try found_map.put(key, fresh_val);

            if (found_map.getPtr(key)) |val| val[ext_idx] = @as(u32, @intCast(list_idx));
        }
    }

    var names2sort: std.ArrayList([]const u8) = try .initCapacity(aa, defPathListSize);
    {
        defer std.mem.sort([]const u8, names2sort.items, {}, stringCompGrow);
        var it = found_map.iterator();
        while (it.next()) |e| {
            var valid = true;
            for (e.value_ptr) |val| valid = (valid and val != null);
            if (valid) {
                try names2sort.append(aa, e.key_ptr.*);
            }
        }
    }

    const results_num = names2sort.items.len;
    var char_size: usize = 0;
    for (names2sort.items) |name| {
        for (found_map.get(name).?, 0..) |inices, group_idx| {
            const path_len = zipLists[group_idx].items[inices.?].len;
            char_size += path_len;
        }
        std.debug.print("+++ pared name {s}\n", .{name});
    }

    var packs = try gpa.alloc([]const []const u8, results_num);
    var names = try gpa.alloc([]const u8, results_num * N);
    var chars = try gpa.alloc(u8, char_size);
    defer {
        gpa.free(packs);
        gpa.free(names);
        gpa.free(chars);
    }
    names[0] = "essa";
    packs[0] = &.{"essa"};

    var char_offset: usize = 0;
    for (names2sort.items) |name| {
        const ok = found_map.get(name).?;
        for (0.., ok) |ext_idx, str_idx| {
            const path = zipLists[ext_idx].items[str_idx.?];
            const sub = chars[char_offset..][0..path.len];
            @memcpy(sub, path);
            char_offset += path.len;
        }
    }
}

pub fn serdesLoad(io: std.Io, gpa: std.mem.Allocator) !meagen.Image {
    const cwd = std.Io.Dir.cwd();
    const prefix = "./fs/serdes";

    fileSearchZip(io, gpa, prefix, &.{ ".serdes", "serdes.mono" }) catch |err| {
        std.debug.print("!!! error searching files {s}\n", .{@errorName(err)});
    };

    const foundname = findSedes(io, prefix) catch |err| {
        std.debug.print("!!! synth data | {s}\n", .{@errorName(err)});
        return try xyTrygHdr(gpa, shu.xyGrid(256, 880));
    };
    var some_space: [1024]u8 = undefined;
    const filepath = try std.fmt.bufPrint(some_space[0..], "{s}/{s}", .{ prefix, foundname });

    const serdesfile = cwd.openFile(io, filepath, .{}) catch |err| {
        std.debug.print("!!! synth data | {s} | {s}\n", .{ filepath, @errorName(err) });
        return try xyTrygHdr(gpa, shu.xyGrid(256, 880));
    };
    defer serdesfile.close(io);

    var file_buffer: [8096]u8 = undefined;
    var rader = serdesfile.reader(io, &file_buffer);

    std.debug.print("+++ loading serdes data from {s}\n", .{filepath});
    return meagen.Image.decode(&rader.interface, gpa);
}

pub const LookingGlass = struct {
    pos: @Vector(2, i32),
    size: sht.GridSize,
    img: *meagen.Image,

    pub fn init(from: *meagen.Image, gsz: sht.GridSize) LookingGlass {
        std.debug.assert(from.info.?.img_type == meagen.ImgType.DUO);
        return LookingGlass{
            .pos = .{ 0, 0 },
            .size = gsz,
            .img = from,
        };
    }
    pub fn update(self: *LookingGlass, axes: *const input.DulaHoldsAxis) bool {
        const src_size = self.img.info.?;

        const max_x = @as(i32, @intCast(src_size.width)) - @as(i32, @intCast(self.size.w)) - 1;
        const max_y = @as(i32, @intCast(src_size.height)) - @as(i32, @intCast(self.size.h)) - 1;

        const x_axis = axes.value()[1];
        self.pos[0] = switch (x_axis) {
            motion.Axis.positive => if (self.pos[0] < max_x) self.pos[0] + 1 else max_x,
            motion.Axis.negative => if (self.pos[0] > 0) self.pos[0] - 1 else 0,
            else => self.pos[0],
        };

        const y_axis = axes.value()[0];
        self.pos[1] = switch (y_axis) {
            motion.Axis.positive => if (self.pos[1] < max_y) self.pos[1] + 1 else max_y,
            motion.Axis.negative => if (self.pos[1] > 0) self.pos[1] - 1 else 0,
            else => self.pos[1],
        };

        if (x_axis != motion.Axis.none or y_axis != motion.Axis.none) {
            // std.debug.print("new position at x:{} y:{}\n", .{ self.pos[0], self.pos[1] });
            return true;
        }
        return false;
    }

    pub fn pixval(self: *LookingGlass, i: usize) u16 {
        const x = @mod(i, @as(usize, @intCast(self.size.w)));
        const y = i / @as(usize, @intCast(self.size.w));
        std.debug.assert(y < self.size.h);

        return pixvalXY(self, x, y);
    }

    pub fn pixvalXY(self: *LookingGlass, x: usize, y: usize) u16 {
        const img_x = @as(usize, @intCast(self.pos[0])) + x;
        const img_y = @as(usize, @intCast(self.pos[1])) + y;

        const _info = self.img.info.?;

        const idx = _info.width * img_y + img_x;

        var hdr_val: uHdr = undefined;
        hdr_val.byte[0] = self.img.pixels[idx * 2];
        hdr_val.byte[1] = self.img.pixels[idx * 2 + 1];

        return hdr_val.hdr;
    }

    const U16max: f32 = 1 << 16;
    pub fn updateStorage(self: *LookingGlass, storage_dset: dset.DescriptorPrep, enabled: bool) !void {
        const total = self.size.total;
        const lim_num = 8096;
        std.debug.assert(total <= lim_num);
        const stack_size = lim_num * @sizeOf(sht.PerInstance);
        var stack_mem: [stack_size]u8 = undefined;

        var provider: std.heap.FixedBufferAllocator = .init(&stack_mem);
        const local_a = provider.allocator();

        var scratchpad = try local_a.alloc(sht.PerInstance, total);
        var max_val: f32 = 1000000;
        var min_val: f32 = -1000000;
        const trim_factor = 0.4;
        for (storage_dset.buff_arr.items) |possible_buffer| {
            const storage = possible_buffer.?;
            const mapping: [*]sht.PerInstance = @ptrCast(@alignCast(storage.mapping.?));
            @memcpy(scratchpad, mapping);
            for (0..total) |i| {
                var prev_one: sht.PerInstance = scratchpad[i];
                const h = @as(f32, @floatFromInt(self.pixval(i)));

                const level = h / U16max;
                const tresholded = @max(0, ((level - trim_factor) / (1 - trim_factor)));
                if (h > max_val) max_val = h;
                if (h < min_val) min_val = h;
                prev_one.depth_ctrl[0] = if (enabled) 1 else 0;
                prev_one.depth_ctrl[1] = tresholded;

                // prev_one.depth_ctrl[1] = 0;

                scratchpad[i] = prev_one;
            }
            @memcpy(mapping, scratchpad);
        }
        // std.debug.print("+++ min: {} max: {}\n", .{ min_val, max_val });
    }
};
