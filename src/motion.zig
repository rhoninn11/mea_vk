const std = @import("std");
const glfw = @import("third_party/glfw.zig");

pub const KeyAction = struct {
    key: c_int,
    action: c_int,

    pub fn down(self: *const KeyAction, key: glfw.Key) bool {
        return self.action == glfw.Press and self.key == key;
    }

    pub fn up(self: *const KeyAction, key: glfw.Key) bool {
        return self.action == glfw.Up and self.key == key;
    }
};

const Hold = struct {
    active: bool = false,

    pub fn hold(self: *Hold, ka: *const KeyAction, key: glfw.Key) void {
        if (ka.action == glfw.Repeat) return;
        self.active = !self.active and ka.down(key);
        self.active = self.active and ka.up(key);
        // std.debug.print("well {} {} {}\n", .{ self.active, ka.press(key), ka.up(key) });
    }
};

pub const MovesA = enum(u8) {
    none = 0,
    left = 1,
    right = 2,
};
pub const MovesB = enum(u8) {
    none = 0,
    near = 1,
    far = 2,
};
pub const MovesC = enum(u8) {
    none = 0,
    down = 1,
    up = 2,
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

const MaxHolds = 16;
pub const Holds = struct {
    holds: [MaxHolds]Hold = undefined,
    keys: [MaxHolds]c_int = undefined,
    len: u8,

    pub fn init(keys: []const c_int) !Holds {
        const len = keys.len;
        std.debug.assert(@mod(len, 2) == 0);
        if (len > MaxHolds) {
            return MoveErrs.HoldSizeExceded;
        }

        var act = Holds{ .len = @intCast(len) };
        for (keys, 0..) |k, i| {
            act.holds[i] = Hold{};
            act.keys[i] = k;
        }

        return act;
    }

    pub fn passKeyAction(self: *Holds, ka: *const KeyAction) void {
        for (0..self.len) |i| {
            self.holds[i].hold(ka, self.keys[i]);
        }
    }
};

pub const HoldsAxis = struct {
    holds: [MaxHolds]Hold = undefined,
    keys: [MaxHolds]c_int = undefined,
    axes: [MaxHolds / 2]Axis = undefined,
    len: u8,

    pub fn init(keys: []const c_int) !HoldsAxis {
        const len = keys.len;
        std.debug.assert(@mod(len, 2) == 0);
        if (len > MaxHolds) {
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

    pub fn passKeyAction(self: *HoldsAxis, ka: *const KeyAction) void {
        for (0..self.len) |i| {
            self.holds[i].hold(ka, self.keys[i]);
        }
    }

    pub fn clear(self: *HoldsAxis) void {
        for (0..(self.len / 2)) |i| {
            self.axes[i] = .none;
        }
    }
    pub fn input_continue(self: *HoldsAxis) void {
        for (0..(self.len / 2)) |i| {
            const neq = self.holds[i * 2].active;
            const pos = self.holds[i * 2 + 1].active;
            if (neq) self.axes[i] = .negative;
            if (pos) self.axes[i] = .positive;
            if (neq == pos) self.axes[i] = .none;
        }
    }
};
