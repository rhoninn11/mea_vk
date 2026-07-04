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

pub const DualHoldsAxis = union(SysLayer) {
    const GAxis = motion.mglfw.HoldsAxis;
    const SAxis = motion.msdl.HoldsAxis;
    layerG: GAxis,
    layerS: SAxis,

    pub fn initS(hmm: []const []const SAxis.BasedOn) !DualHoldsAxis {
        return .{ .layerS = try SAxis.init(hmm) };
    }
    pub fn reciveInput(self: *DualHoldsAxis, duka: DulaKeyAction) void {
        switch (self.*) {
            .layerS => self.layerS.reciveInput(duka.layerS),
            else => {},
        }
    }
    pub fn update(self: *DualHoldsAxis) void {
        switch (self.*) {
            .layerS => self.layerS.update(),
            else => {},
        }
    }

    pub fn value(self: *const DualHoldsAxis) []const motion.Axis {
        return switch (self.*) {
            .layerS => &self.layerS.axes,
            else => &.{.none},
        };
    }
};

const HoldsAxis = motion.mglfw.HoldsAxis;
pub var glass_input: DualHoldsAxis = undefined;
pub var plr_input: DualHoldsAxis = undefined;
pub var pan_input: DualHoldsAxis = undefined;

pub var ok_vis_trigger: Trigger = .{};
pub var shader_reset_trigger: Trigger = .{};
pub var alt_projection_trigger: Trigger = .{};
pub var slide_l_trig: Trigger = .{};
pub var slide_r_trig: Trigger = .{};
pub var dbg_trig: Trigger = .{};
pub var sample_tirg: Trigger = .{};
pub var inverse_tirg: Trigger = .{};

const KeyActionSdl = motion.msdl.KeyAction;
const Tied = struct {
    key: sdl.keycode.Keycode,
    trig: *Trigger,
};

pub fn initS() !void {
    glass_input = try DualHoldsAxis.initS(&.{
        &.{
            sdl.keycode.Keycode.h, sdl.keycode.Keycode.l, //
            sdl.keycode.Keycode.k, sdl.keycode.Keycode.j,
        },
    });
    plr_input = try DualHoldsAxis.initS(&.{
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
    pan_input = try DualHoldsAxis.initS(&.{
        &.{ sdl.keycode.Keycode.space, sdl.keycode.Keycode.tab },
    });
}

const sdl_inputs: []const Tied = &.{
    .{ .key = sdl.keycode.Keycode.y, .trig = &ok_vis_trigger },
    .{ .key = sdl.keycode.Keycode.q, .trig = &shader_reset_trigger },
    .{ .key = sdl.keycode.Keycode.left_alt, .trig = &alt_projection_trigger },
    .{ .key = sdl.keycode.Keycode.v, .trig = &slide_l_trig },
    .{ .key = sdl.keycode.Keycode.b, .trig = &slide_r_trig },
    .{ .key = sdl.keycode.Keycode.two, .trig = &dbg_trig },
    .{ .key = sdl.keycode.Keycode.three, .trig = &time_stop_trig },
    .{ .key = sdl.keycode.Keycode.four, .trig = &inverse_tirg },
};

const axesCheck = [_]*DualHoldsAxis{
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

    for (axesCheck) |hmm| hmm.reciveInput(.{ .layerS = &x });
}

pub fn sdlKeyUp(key: sdl.keycode.Keycode) void {
    const x: KeyActionSdl = .{ .key = key, .action = glfw.Release };
    for (axesCheck) |hmm| hmm.reciveInput(.{ .layerS = &x });
}
