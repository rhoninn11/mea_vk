const std = @import("std");
const glfw = @import("third_party/glfw.zig");
const sdl = @import("sdl3");

const Allocator = std.mem.Allocator;

pub const mglfw: type = HostMotion(c_int);
pub const msdl: type = HostMotion(sdl.keycode.Keycode);

pub const Axis = enum(i8) {
    none = 0,
    positive = 1,
    negative = -1,
};

const MoveErrs = error{
    HoldSizeExceded,
};

pub const Trigger = struct {
    activated: bool = false,

    pub fn fired(self: *Trigger) bool {
        defer self.activated = false;
        return self.activated;
    }
};

const max_holds: comptime_int = 16;
pub fn HostMotion(keytype: type) type {
    return struct {
        pub const KeyAction = struct {
            key: keytype,
            action: c_int,

            pub fn down(self: *const KeyAction, key: keytype) bool {
                return self.action == glfw.Press and self.key == key;
            }

            pub fn up(self: *const KeyAction, key: keytype) bool {
                return self.action == glfw.Release and self.key == key;
            }
        };

        pub const Hold = struct {
            active: bool = false,

            pub fn hold(self: *Hold, ka: *const KeyAction, key: keytype) void {
                if (ka.action == glfw.Repeat) return;

                if (!self.active and ka.down(key)) self.active = true;
                if (self.active and ka.up(key)) self.active = false;
            }
        };

        pub const HoldsAxis = struct {
            pub const BasedOn = keytype;
            holds: [max_holds]Hold = undefined,
            keys: [max_holds]keytype = undefined,
            axes: [max_holds / 2]Axis = undefined,
            keyn: u8,
            setn: u8,

            pub fn init(sets: []const []const keytype) !HoldsAxis {
                const set_num = sets.len;
                std.debug.assert(set_num > 0);

                const key_num = sets[0].len;
                std.debug.assert(@mod(key_num, 2) == 0);
                for (sets) |set| std.debug.assert(set.len == key_num);

                if (set_num * key_num > max_holds) {
                    return MoveErrs.HoldSizeExceded;
                }

                var self = HoldsAxis{
                    .keyn = @intCast(key_num),
                    .setn = @intCast(set_num),
                };
                for (0.., sets) |ss, keys| {
                    for (0.., keys) |i, key| {
                        self.holds[i] = Hold{};
                        const j = ss * self.keyn + i;
                        self.keys[j] = key;

                        std.debug.print("hold({d}) binded with key({d})\n", .{ i, j });
                    }
                }

                for (0..(key_num / 2)) |i| {
                    self.axes[i] = .none;
                }

                return self;
            }

            pub fn reciveInput(self: *HoldsAxis, ka: *const KeyAction) void {
                axis: for (0..self.keyn) |ii| {
                    for (0..self.setn) |s| {
                        const j = s * self.keyn + ii;
                        if (self.keys[j] == ka.key) {
                            self.holds[ii].hold(ka, self.keys[j]);
                            continue :axis; //hold updated by one set so go to next
                        }
                    }
                }
            }

            pub fn update(self: *HoldsAxis) void {
                for (0..(self.keyn / 2)) |i| {
                    const neq = self.holds[i * 2].active;
                    const pos = self.holds[i * 2 + 1].active;
                    if (neq) self.axes[i] = .negative;
                    if (pos) self.axes[i] = .positive;
                    if (neq == pos) self.axes[i] = .none;
                }
            }
        };
    };
}
