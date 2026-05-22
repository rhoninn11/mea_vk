const std = @import("std");

const glfw = @import("third_party/glfw.zig");
const sdl = @import("sdl3");

const motion = @import("motion.zig");
const Trigger = motion.Trigger;

pub var exit_trig: Trigger = .{};
pub var time_stop_trig: Trigger = .{};

const KeyAction = motion.mglfw.KeyAction;
const HoldsAxis = motion.mglfw.HoldsAxis;
pub var glass_input: HoldsAxis = undefined;
pub var plr_input: HoldsAxis = undefined;

pub var ok_vis_trigger: Trigger = .{};
pub var shader_reset_trigger: Trigger = .{};
pub var uniform_shift_trigger: Trigger = .{};
pub var slide_l_trig: Trigger = .{};
pub var slide_r_trig: Trigger = .{};

pub var ok_vis: KeyAction = .{ .key = glfw.KeyY, .action = glfw.KeyDown };
pub var shader_reset: KeyAction = .{ .key = glfw.KeyQ, .action = glfw.KeyDown };
pub var uniform_shift: KeyAction = .{ .key = glfw.KeyE, .action = glfw.KeyDown };
pub var slide_l: KeyAction = .{ .key = glfw.KeyV, .action = glfw.KeyDown };
pub var slide_r: KeyAction = .{ .key = glfw.KeyB, .action = glfw.KeyDown };

pub fn init() !void {
    glass_input = try HoldsAxis.init(&.{
        glfw.KeyJ, glfw.KeyK, //
        glfw.KeyH, glfw.KeyL,
    });
    plr_input = try HoldsAxis.init(&.{
        glfw.KeyA, glfw.KeyD, //
        glfw.KeyS, glfw.KeyW,
        glfw.KeyF, glfw.KeyR,
    });
}

pub fn key_callback(win: ?*glfw.Window, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = scancode;
    _ = mods;
    _ = win;
    const x: KeyAction = .{
        .action = action,
        .key = key,
    };
    if (x.down(glfw.KeyEscape)) {
        std.debug.print("exititng\n", .{});
        exit_trig.activated = true;
    }
    if (x.down(glfw.KeySpace)) {
        time_stop_trig.activated = true;
    }

    if (x.down(shader_reset.key)) {
        shader_reset_trigger.activated = true;
    }

    if (x.down(uniform_shift.key)) {
        uniform_shift_trigger.activated = true;
    }
    if (x.down(slide_l.key)) {
        slide_l_trig.activated = true;
    }
    if (x.down(slide_r.key)) {
        slide_r_trig.activated = true;
    }
    if (x.down(ok_vis.key)) {
        ok_vis_trigger.activated = true;
    }

    glass_input.reciveInput(&x);
    plr_input.reciveInput(&x);
}

const KeyActionSdl = motion.msdl.KeyAction;
const Tied = struct {
    key: sdl.keycode.Keycode,
    trig: *Trigger,
};

const sdl_inputs: []const Tied = &.{
    .{ .key = sdl.keycode.Keycode.y, .trig = &ok_vis_trigger },
    .{ .key = sdl.keycode.Keycode.q, .trig = &shader_reset_trigger },
    .{ .key = sdl.keycode.Keycode.e, .trig = &uniform_shift_trigger },
    .{ .key = sdl.keycode.Keycode.v, .trig = &slide_l_trig },
    .{ .key = sdl.keycode.Keycode.b, .trig = &slide_r_trig },
};

pub fn sdlKeyDown(key: sdl.keycode.Keycode) void {
    const x: KeyActionSdl = .{ .key = key, .action = glfw.Press };
    for (sdl_inputs) |bind| {
        if (x.down(bind.key)) bind.trig.activated = true;
    }
}
