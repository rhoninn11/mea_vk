const std = @import("std");

const motion = @import("motion.zig");
const glfw = @import("third_party/glfw.zig");

pub var glass_input: motion.HoldsAxis = undefined;
pub var plr_input: motion.HoldsAxis = undefined;
pub var ok_vis: motion.KeyAction = .{ .key = glfw.KeyY, .action = glfw.KeyDown };
pub var ok_vis_trigger: motion.Trigger = .{};
pub var shader_reset: motion.KeyAction = .{ .key = glfw.KeyQ, .action = glfw.KeyDown };
pub var shader_reset_trigger: motion.Trigger = .{};
pub var uniform_shift: motion.KeyAction = .{ .key = glfw.KeyE, .action = glfw.KeyDown };
pub var uniform_shift_trigger: motion.Trigger = .{};
pub var slide_l: motion.KeyAction = .{ .key = glfw.KeyV, .action = glfw.KeyDown };
pub var slide_r: motion.KeyAction = .{ .key = glfw.KeyB, .action = glfw.KeyDown };
pub var slide_l_trig: motion.Trigger = .{};
pub var slide_r_trig: motion.Trigger = .{};
pub var exit_trig: motion.Trigger = .{};
pub var time_stop_trig: motion.Trigger = .{};

pub fn init() !void {
    glass_input = try motion.HoldsAxis.init(&.{
        glfw.KeyJ, glfw.KeyK, //
        glfw.KeyH, glfw.KeyL,
    });
    plr_input = try motion.HoldsAxis.init(&.{
        glfw.KeyA, glfw.KeyD, //
        glfw.KeyS, glfw.KeyW,
        glfw.KeyF, glfw.KeyR,
    });
}

const KeyAction = motion.KeyAction;
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
