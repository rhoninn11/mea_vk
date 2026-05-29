const std = @import("std");
const utils = @import("utils.zig");

const Io = std.Io;
const Allocotor = std.mem.Allocator;

pub fn fileRead(io: Io, gpa: Allocotor, filepath: []const u8) ![]u8 {
    var chunk4k: [4096]u8 = undefined;
    const cwd = std.Io.Dir.cwd();

    const anyfile = cwd.openFile(io, filepath, .{}) catch {
        return error.NoFile;
    };
    defer anyfile.close(io);
    var rFile = anyfile.reader(io, chunk4k[0..]);

    const size = try rFile.getSize();
    const ioreader: *std.Io.Reader = &rFile.interface;
    return try ioreader.readAlloc(gpa, size);
}

pub fn stdoutWriter(io: std.Io, buffer: []u8) *std.Io.Writer {
    const stderr = std.Io.File.stderr();
    var writer = stderr.writer(io, buffer);
    return &writer.interface;
}

const PathList = std.ArrayList([]const u8);
const PRA_PATH_N: comptime_int = 32;
pub fn findExt(io: std.Io, arena: std.mem.Allocator, here: []const u8, ext: []const u8) !PathList {
    const serdes_dir = try std.Io.Dir.cwd().openDir( //
        io, here, .{ .iterate = true });
    defer serdes_dir.close(io);

    var iterator = serdes_dir.iterate();

    var found_files: std.ArrayList([]const u8) = try .initCapacity(arena, PRA_PATH_N);
    while (try iterator.next(io)) |entry| {
        if (std.mem.endsWith(u8, entry.name, ext)) {
            const full_path = try std.fs.path.join(arena, &.{ here, entry.name });
            try found_files.append(arena, full_path);
        }
    }

    if (found_files.items.len == 0) return error.NoFile;

    return found_files;
}
pub const ZippedFiles = struct {
    const SliceAlign = @alignOf([]const u8);
    file_sets: [][][]u8,
    file_paths: [][]u8,
    chars: []u8,

    pub fn init(comptime N: usize, gpa: std.mem.Allocator, set_num: usize, glyph_num: usize) !ZippedFiles {
        return .{
            .file_sets = try gpa.alloc([][]u8, set_num),
            .file_paths = try gpa.alloc([]u8, set_num * N),
            .chars = try gpa.alloc(u8, glyph_num),
        };
    }

    pub fn deinit(self: *ZippedFiles, gpa: std.mem.Allocator) void {
        gpa.free(self.file_sets);
        gpa.free(self.file_paths);
        gpa.free(self.chars);
    }
};

pub fn zipSearch(
    io: std.Io,
    gpa: std.mem.Allocator,
    seach_loc: []const u8,
    comptime exts_zip: []const []const u8,
) !void {
    const N = exts_zip.len;
    const Bins = [N]?u32;
    const PathArrayList = std.ArrayList([]const u8);
    const FileMap = std.StringHashMap(Bins);

    const LambdaL = struct {
        pub fn catchNames(opa: std.mem.Allocator, map: *FileMap) !PathList {
            var names_of_sort: PathArrayList = try .initCapacity(opa, PRA_PATH_N);
            defer std.mem.sort([]const u8, names_of_sort.items, {}, utils.strcompR);

            var it = map.iterator();
            while (it.next()) |e| {
                var valid = true;
                for (e.value_ptr) |presence|
                    valid = (valid and presence != null);

                if (valid)
                    try names_of_sort.append(opa, e.key_ptr.*);
            }
            return names_of_sort;
        }
    };

    var arana: std.heap.ArenaAllocator = .init(gpa);
    defer arana.deinit();

    const aa = arana.allocator();
    var zip_lists: [N]PathArrayList = undefined;

    for (0..N) |i| {
        zip_lists[i] = findExt(io, aa, seach_loc, exts_zip[i]) catch {
            return error.NoZipping;
        };
    }

    const EMPTY_BINS: Bins = .{null} ** N;
    var found_map: FileMap = .init(aa);
    try found_map.ensureTotalCapacity(32);

    for (0.., zip_lists) |ext_idx, list| {
        const ext = exts_zip[ext_idx];

        for (0.., list.items) |list_idx, element| {
            const almost_key = utils.trimPrefix(element, seach_loc);
            const key = utils.trimSufix(almost_key, ext);

            if (found_map.getPtr(key) == null)
                try found_map.put(key, EMPTY_BINS);

            if (found_map.getPtr(key)) |val|
                val[ext_idx] = @as(u32, @intCast(list_idx));
        }
    }

    const names_of_sort = try LambdaL.catchNames(aa, &found_map);

    const names_count = names_of_sort.items.len;
    var glyph_count: usize = 0;
    for (names_of_sort.items) |name| {
        for (found_map.get(name).?, 0..) |inices, group_idx| {
            const path_len = zip_lists[group_idx].items[inices.?].len;
            glyph_count += path_len;
        }
    }

    var zipout: ZippedFiles = try .init(N, gpa, names_count, glyph_count);
    defer zipout.deinit(gpa);

    var char_offset: usize = 0;
    for (names_of_sort.items) |name| {
        const ok = found_map.get(name).?;
        for (0.., ok) |ext_idx, str_idx| {
            const path = zip_lists[ext_idx].items[str_idx.?];
            const sub = zipout.chars[char_offset..][0..path.len];
            @memcpy(sub, path);
            char_offset += path.len;
        }
    }
}
