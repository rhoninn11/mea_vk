const std = @import("std");

// pub fn InfoRecorder(hmm: type) !type {
//     const Prev = hmm;
//     const Self = @This();
//     _ = Self;

//     // comptime var message_buffer: [8096]u8 = undefined;
//     // comptime var fbs = std.io.fixedBufferStream(&message_buffer);

//     // const about_type = @typeInfo(Prev);
//     // const decls = about_type.@"struct".decls;
//     // const len = decls.len;
//     // comptime var chars: usize = 0;

//     // const writer = fbs.writer();
//     // for (decls) |d| {
//     //     try writer.print("{s}\n", .{d.name});
//     //     chars += d.name.len;
//     // }
//     // try writer.print("len: {d}\nchar num: {d}\n", .{ len, chars });
//     const about_type = @typeInfo(Prev);
//     const decls = about_type.@"struct".decls;

//     const message = comptime blk: {
//         var message_buffer: [8096:0]u8 = undefined;
//         var fbs = std.io.fixedBufferStream(&message_buffer);
//         var chars: usize = 0;

//         const writer = fbs.writer();
//         for (decls) |d| {
//             try writer.print("{s}\n", .{d.name});
//             chars += d.name.len;
//         }
//         try writer.print("len: {d}\nchar num: {d}\n", .{ decls.len, chars });
//         // fbs.pos

//         break :blk fbs.getWritten();
//     };

//     return struct {
//         fn readInfo() *const [:0]u8 {
//             return message;
//         }
//     };
// }

pub fn structDeclNum(self: type) usize {
    const about_type = @typeInfo(self);
    return about_type.@"struct".decls.len - 1;
}
