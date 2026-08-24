const std = @import("std");

pub const Group = enum(u16) {
    cubes = 0,
    okg,
    text,
    layer,
};

const sz2k = 2048;
const sz4k = 4096;
const sz6k = sz2k + sz4k;
const szblk = 128;
const why_text_here = sz4k + 512;

pub const Range = struct { beg: u16, end: u16 };
pub const instablo: std.enums.EnumArray(Group, Range) = .init(.{
    .cubes = .{ .beg = 0, .end = sz4k - 1 },
    .okg = .{ .beg = sz4k, .end = sz4k + szblk - 1 },
    .text = .{ .beg = why_text_here, .end = sz6k - 1 },
    .layer = .{ .beg = sz6k, .end = sz6k + sz2k - 1 },
});

// TODO: texture map

// 0 - 3 few, mostly test textures
// 4 for atlas
// 5 scan data
// 32 default gradient
// 33 - 159 ok slices
