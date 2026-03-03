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
