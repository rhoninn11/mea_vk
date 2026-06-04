const std = @import("std");

const glfw = @import("third_party/glfw.zig");
const sdl = @import("sdl3");

const motion = @import("motion.zig");
const Trigger = motion.Trigger;

pub var exit_trig: Trigger = .{};
pub var time_stop_trig: Trigger = .{};

const KeyAction = motion.mglfw.KeyAction;

const SysLayer = enum {
    layerG,
    layerS,
};

const DulaKeyAction = union(SysLayer) {
    layerG: *const motion.mglfw.KeyAction,
    layerS: *const motion.msdl.KeyAction,
};

pub const DulaHoldsAxis = union(SysLayer) {
    const GAxis = motion.mglfw.HoldsAxis;
    const SAxis = motion.msdl.HoldsAxis;
    layerG: GAxis,
    layerS: SAxis,
    // pub fn update(self: *DulaHoldsAxis) void {
    //     switch (self.*) {
    //         .layerS => |axis| axis.update(),
    //         .layerG => |axis| axis.update(),
    //     }
    // }

    pub fn initG(hmm: []const []const GAxis.BasedOn) !DulaHoldsAxis {
        return .{ .layerG = try GAxis.init(hmm) };
    }
    pub fn initS(hmm: []const []const SAxis.BasedOn) !DulaHoldsAxis {
        return .{ .layerS = try SAxis.init(hmm) };
    }
    pub fn reciveInput(self: *DulaHoldsAxis, duka: DulaKeyAction) void {
        switch (self.*) {
            .layerS => self.layerS.reciveInput(duka.layerS),
            .layerG => self.layerG.reciveInput(duka.layerG),
        }
    }
    pub fn update(self: *DulaHoldsAxis) void {
        switch (self.*) {
            .layerS => self.layerS.update(),
            .layerG => self.layerG.update(),
        }
    }

    pub fn value(self: *const DulaHoldsAxis) []const motion.Axis {
        return switch (self.*) {
            .layerS => &self.layerS.axes,
            .layerG => &self.layerG.axes,
        };
    }
};

const HoldsAxis = motion.mglfw.HoldsAxis;
pub var glass_input: DulaHoldsAxis = undefined;
pub var plr_input: DulaHoldsAxis = undefined;

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

pub fn initG() !void {
    glass_input = try DulaHoldsAxis.initG(&.{
        &.{
            glfw.KeyJ, glfw.KeyK, //
            glfw.KeyH, glfw.KeyL,
        },
    });
    plr_input = try DulaHoldsAxis.initG(&.{
        &.{
            glfw.KeyA, glfw.KeyD, //
            glfw.KeyS, glfw.KeyW,
            glfw.KeyF, glfw.KeyR,
        },
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

    glass_input.reciveInput(.{ .layerG = &x });
    plr_input.reciveInput(.{ .layerG = &x });
}

const KeyActionSdl = motion.msdl.KeyAction;
const Tied = struct {
    key: sdl.keycode.Keycode,
    trig: *Trigger,
};

pub fn initS() !void {
    glass_input = try DulaHoldsAxis.initS(&.{
        &.{
            sdl.keycode.Keycode.j, sdl.keycode.Keycode.k, //
            sdl.keycode.Keycode.h, sdl.keycode.Keycode.l,
        },
    });
    plr_input = try DulaHoldsAxis.initS(&.{
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
}

const sdl_inputs: []const Tied = &.{
    .{ .key = sdl.keycode.Keycode.y, .trig = &ok_vis_trigger },
    .{ .key = sdl.keycode.Keycode.q, .trig = &shader_reset_trigger },
    .{ .key = sdl.keycode.Keycode.e, .trig = &uniform_shift_trigger },
    .{ .key = sdl.keycode.Keycode.v, .trig = &slide_l_trig },
    .{ .key = sdl.keycode.Keycode.b, .trig = &slide_r_trig },
};

const axesCheck = [_]*DulaHoldsAxis{ &glass_input, &plr_input };
pub fn sdlKeyDown(key: sdl.keycode.Keycode) void {
    const x: KeyActionSdl = .{ .key = key, .action = glfw.Press };
    for (sdl_inputs) |bind| {
        if (x.down(bind.key)) bind.trig.activated = true;
    }

    if (x.down(sdl.keycode.Keycode.space)) {
        time_stop_trig.activated = true;
    }

    for (axesCheck) |hmm| hmm.reciveInput(.{ .layerS = &x });
}

pub fn sdlKeyUp(key: sdl.keycode.Keycode) void {
    const x: KeyActionSdl = .{ .key = key, .action = glfw.Release };
    for (axesCheck) |hmm| hmm.reciveInput(.{ .layerS = &x });
}
