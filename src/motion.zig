const std = @import("std");
const glfw = @import("third_party/glfw.zig");

pub const KeyAction = struct {
    key: c_int,
    action: c_int,

    pub fn down(self: *const KeyAction, key: glfw.Key) bool {
        return self.action == glfw.Press and self.key == key;
    }

    pub fn up(self: *const KeyAction, key: glfw.Key) bool {
        return self.action == glfw.Release and self.key == key;
    }
};

const Hold = struct {
    active: bool = false,

    pub fn hold(self: *Hold, ka: *const KeyAction, key: glfw.Key) void {
        if (ka.action == glfw.Repeat) return;
        self.active = !self.active and ka.down(key);
        // self.active = self.active and ka.up(key);
        // std.debug.print("well {} {} {}\n", .{ self.active, ka.press(key), ka.up(key) });
    }
};

pub const Axis = enum(u8) {
    none = 0,
    positive = 1,
    negative = 2,
};

const Allocator = std.mem.Allocator;

const MoveErrs = error{
    HoldSizeExceded,
};

const max_holds: comptime_int = 16;
pub const HoldsAxis = struct {
    holds: [max_holds]Hold = undefined,
    keys: [max_holds]c_int = undefined,
    axes: [max_holds / 2]Axis = undefined,
    len: u8,

    pub fn init(keys: []const c_int) !HoldsAxis {
        const len = keys.len;
        std.debug.assert(@mod(len, 2) == 0);
        if (len > max_holds) {
            return MoveErrs.HoldSizeExceded;
        }

        var act = HoldsAxis{ .len = @intCast(len) };
        for (keys, 0..) |k, i| {
            act.holds[i] = Hold{};
            act.keys[i] = k;
        }

        for (0..len / 2) |i| {
            act.axes[i] = .none;
        }

        return act;
    }

    pub fn reciveInput(self: *HoldsAxis, ka: *const KeyAction) void {
        for (0..self.len) |i| {
            if (self.keys[i] == ka.key) {
                self.holds[i].hold(ka, self.keys[i]);
            }
        }
    }

    pub fn update(self: *HoldsAxis) void {
        for (0..(self.len / 2)) |i| {
            const neq = self.holds[i * 2].active;
            const pos = self.holds[i * 2 + 1].active;
            if (neq) self.axes[i] = .negative;
            if (pos) self.axes[i] = .positive;
            if (neq == pos) self.axes[i] = .none;
        }
    }
};

pub const Trigger = struct {
    activated: bool = false,

    pub fn fired(self: *Trigger) bool {
        defer self.activated = false;
        return self.activated;
    }
};
