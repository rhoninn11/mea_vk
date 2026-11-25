const std = @import("std");
const tt = @import("stbtt");

const glfw = @import("third_party/glfw.zig");
const vk = @import("vulkan-zig");

const sht = @import("shaders/types.zig");
const shu = @import("shaders/utils.zig");
const gm = @import("graphics_context.zig");

const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const swap = @import("swapchain.zig");
const a = @import("addons.zig");
const d = @import("debug.zig");
const dset = @import("dset.zig");

const vertex = @import("vertex.zig");

const m = @import("math.zig");
const t = @import("types.zig");
const u = @import("utils.zig");

const map = @import("map.zig");
const phys = @import("phys.zig");
const imgs = @import("imgs/imgs.zig");
const refils = @import("refills.zig");
const oklab = @import("oklab.zig");
const files = @import("files.zig");

const oct = @import("oct");
const well = oct.f32_arr_3d_t;

const InertiaVec2 = phys.InertiaPack(m.vec3);
const Vertex = vertex.Vertex;

const Allocator = std.mem.Allocator;

const motion = @import("motion.zig");
const devui = @import("devui.zig");

const pipe = @import("pipe.zig");

const app_name = "oct_anotator";
const future_app_name = "oct_calculator";

var time_glob: ?*a.Timeline = null;
const BasicErrs = error{
    NoCtx,
};

const sdlh = @import("sdlh.zig");

const input = @import("input.zig");
const host = @import("host.zig");

const proto = @import("proto/proto.zig");
const fonts = @import("fonts.zig");
const _main = @import("main/the_deeprest.zig");
pub const vk_portal = vk;

pub fn main(init: std.process.Init) !void {
    const MAX_ARGS = 32;
    var opts = host.Opts{};
    {
        const fld_names = @typeInfo(host.Opts).@"struct".field_names;
        var over_args = try init.minimal.args.iterateAllocator(init.gpa);
        defer over_args.deinit();

        std.debug.print(" ------------------------------------------------\n", .{});
        defer std.debug.print(" ------------------------------------------------\n", .{});
        var i: i8 = 0;
        while (over_args.next()) |arg| {
            defer i = i + 1;
            std.debug.assert(i < MAX_ARGS);
            std.debug.print("| args used by program {d} {s}\n", .{ i, arg });

            inline for (fld_names) |fld_name| {
                const arg_val = arg.ptr;
                if (std.mem.eql(u8, std.mem.span(arg_val), fld_name)) {
                    std.debug.print("+ {s} matched\n", .{fld_name});
                    @field(opts, fld_name) = true;
                }
            }
        }
    }
    std.debug.print("!!!!!!!!!! {any}\n", .{opts});
    try host.sdlHost(init, opts, deeper);

    std.debug.print("+++ leaving host\n", .{});
}

fn deeper(access: host.EasyAcces) host.OnHostErrors!void {
    const theDeepestFn = _main.theDeepest;
    theDeepestFn(access) catch |err| {
        std.debug.print("passenger error, converting to one of MainErrors src {}\n", .{err});
        return host.OnHostErrors.passengerError;
    };
}

test "does it even testing" {
    try std.testing.expect(true);
}
