const std = @import("std");

const glfw = @import("third_party/glfw.zig");
const sdl = @import("sdl3");

const motion = @import("motion.zig");
const Trigger = motion.Trigger;

pub var exit_trig: Trigger = .{};
pub var time_stop_trig: Trigger = .{};

pub const IHoldAx = motion.msdl.HoldAx;

pub var glass_input: IHoldAx = undefined;
pub var plr_input: IHoldAx = undefined;
pub var pan_input: IHoldAx = undefined;

const KeyActionSdl = motion.msdl.KeyAction;
const Tied = struct {
    key: sdl.keycode.Keycode,
    trig: *Trigger,
};

pub fn initS() !void {
    glass_input = try IHoldAx.init(&.{
        &.{
            sdl.keycode.Keycode.h, sdl.keycode.Keycode.l, //
            sdl.keycode.Keycode.k, sdl.keycode.Keycode.j,
        },
    });
    plr_input = try IHoldAx.init(&.{
        &.{
            sdl.keycode.Keycode.a, sdl.keycode.Keycode.d, //
            sdl.keycode.Keycode.s, sdl.keycode.Keycode.w,
            sdl.keycode.Keycode.f, sdl.keycode.Keycode.r,
        },
        &.{
            sdl.keycode.Keycode.left, sdl.keycode.Keycode.right, //
            sdl.keycode.Keycode.down, sdl.keycode.Keycode.up,
            sdl.keycode.Keycode.f,    sdl.keycode.Keycode.r,
        },
    });
    pan_input = try IHoldAx.init(&.{
        // TODO: mouse hold for dragging
        &.{ sdl.keycode.Keycode.space, sdl.keycode.Keycode.tab },
    });
}

pub var ok_vis_trigger: Trigger = .{};
pub var shader_reset_trigger: Trigger = .{};
pub var alt_projection_trigger: Trigger = .{};
pub var slide_l_trig: Trigger = .{};
pub var slide_r_trig: Trigger = .{};
pub var dbg_trig: Trigger = .{};
pub var sample_tirg: Trigger = .{};
pub var inverse_tirg: Trigger = .{};
pub var persp_switch: Trigger = .{};

const sdl_inputs: []const Tied = &.{
    .{ .key = sdl.keycode.Keycode.y, .trig = &ok_vis_trigger },
    .{ .key = sdl.keycode.Keycode.q, .trig = &shader_reset_trigger },
    .{ .key = sdl.keycode.Keycode.left_alt, .trig = &alt_projection_trigger },
    .{ .key = sdl.keycode.Keycode.v, .trig = &slide_l_trig },
    .{ .key = sdl.keycode.Keycode.b, .trig = &slide_r_trig },
    .{ .key = sdl.keycode.Keycode.two, .trig = &dbg_trig },
    .{ .key = sdl.keycode.Keycode.three, .trig = &time_stop_trig },
    .{ .key = sdl.keycode.Keycode.four, .trig = &inverse_tirg },
    .{ .key = sdl.keycode.Keycode.five, .trig = &persp_switch },
};

const axesCheck = [_]*IHoldAx{
    &glass_input,
    &plr_input,
    &pan_input,
};
pub fn updateAxes() void {
    for (axesCheck) |ax| ax.update();
}

pub fn sdlKeyDown(key: sdl.keycode.Keycode) void {
    const x: KeyActionSdl = .{ .key = key, .action = glfw.Press };
    for (sdl_inputs) |bind| {
        if (x.down(bind.key)) bind.trig.activated = true;
    }

    for (axesCheck) |hld_ax| hld_ax.reciveInput(&x);
}

pub fn sdlKeyUp(key: sdl.keycode.Keycode) void {
    const x: KeyActionSdl = .{ .key = key, .action = glfw.Release };
    for (axesCheck) |hld_ax| hld_ax.reciveInput(&x);
}
