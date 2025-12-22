const std = @import("std");
const zig_oct = @import("zig_oct");
const fs = std.fs;
const assert = std.debug.assert;

const LocalErrors = error{
    MissingArgument,
    DirOpenFailed,
    OpsFailed,
};

fn readArg(args: [][:0]u8, name: [:0]const u8) ![:0]u8 {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, name)) {
            const val_idx = i + 1;
            assert(args.len > val_idx);
            return args[val_idx];
        }
    }

    std.log.err("!!! arg {s} missing", .{name});
    return LocalErrors.MissingArgument;
}

fn tag(tag_name: [:0]const u8) void {
    std.debug.print("before fail {s}\n", .{tag_name});
}

fn exec(alloc: std.mem.Allocator) !void {
    const args = try std.process.argsAlloc(alloc);
    defer alloc.free(args);

    const cwd = std.fs.cwd();

    const data_dir_flag: [:0]const u8 = "-d";
    const data_dir_path: [:0]u8 = try readArg(args, data_dir_flag);
    const data_dir: std.fs.Dir = cwd.openDir(data_dir_path, .{ .iterate = true }) catch {
        std.log.err("!!! directory open for {s} failed\n", .{data_dir_flag});
        return error.DirOpenFailed;
    };

    var dir_walker = try data_dir.walk(alloc);
    while (try dir_walker.next()) |entry| {
        std.debug.print(" in {s} is {s}\n", .{ data_dir_path, entry.path });
    }

    simpleImg(data_dir, "image_out") catch |err| {
        std.log.err("!!! image export failed", .{});
        return err;
    };
}

fn simpleImg(store_here: std.fs.Dir, basename: [:0]const u8) !void {
    const char_limit = 128;
    var ppm_filename_buf: [char_limit]u8 = undefined;
    var png_filename_buf: [char_limit]u8 = undefined;
    const ppm_filename = try std.fmt.bufPrintZ(&ppm_filename_buf, "{s}.ppm", .{basename});
    const png_filename = try std.fmt.bufPrintZ(&png_filename_buf, "{s}.png", .{basename});

    std.debug.print("attempt to open {s}\n", .{ppm_filename});

    const result_file = try store_here.createFile(ppm_filename, .{});
    {
        defer result_file.close();

        var writer_scratchpad: [char_limit]u8 = undefined;
        var file_writer = result_file.writer(&writer_scratchpad);
        var writer = &file_writer.interface;

        const width = 128;
        const height = 128;
        const color: [3]u8 = .{ 0, 251, 122 };
        try writer.print("P6\n{d} {d}\n255\n", .{ width, height });
        for (0..height) |y| {
            for (0..width) |x| {
                try writer.printAscii(&color, .{});
                _ = x;
                _ = y;
            }
        }

        try writer.flush();
        std.debug.print("+++ data written to ({s})\n", .{ppm_filename});
    }

    {
        var child = std.process.Child.init(&.{
            "ffmpeg", "-i", ppm_filename, "-q:v", "2", png_filename,
        }, std.heap.page_allocator);

        _ = try child.spawnAndWait();
        std.debug.print("+++ data converted to ({s})", .{png_filename});
    }

    // try writer.print("P6\n{} {}\n255\n", .{ width, height })
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    _ = exec(arena.allocator()) catch |err| {
        std.log.err("!!! execution failed: {}", .{err});
    };
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
