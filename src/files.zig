const std = @import("std");

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
