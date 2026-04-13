const std = @import("std");
const t = @import("types.zig");
const motion = @import("motion.zig");

pub fn Slider(vecTpy: type) type {
    return struct {
        const Self = @This();
        hmm: *const []const vecTpy,
        len: u8,
        idx: u8,
        pub fn init(point: *const []const vecTpy) Self {
            std.debug.assert(point.len < std.math.maxInt(u8));
            return .{
                .hmm = point,
                .len = @intCast(point.len),
                .idx = 0,
            };
        }
        pub fn curr(self: *Self) vecTpy {
            return self.hmm.ptr[self.idx];
        }
        pub fn next(self: *Self) vecTpy {
            self.idx = @mod(self.idx + 1, self.len);
            return self.hmm.ptr[self.idx];
        }
        pub fn prev(self: *Self) vecTpy {
            self.idx = if (self.idx == 0) self.len - 1 else self.idx - 1;
            return self.hmm.ptr[self.idx];
        }
    };
}

pub const Caped = struct {
    min: f32,
    max: f32,

    pub fn init(min: f32, max: f32) Caped {
        return Caped{
            .min = min,
            .max = max,
        };
    }

    pub fn cap(self: Caped, val: f32) f32 {
        return @min(@max(val, self.min), self.max);
    }
};

pub const PerfStats = struct {
    t0: i64,
    frame_num: u32,

    pub fn init() PerfStats {
        std.debug.print("--- empty line ---\n", .{});
        return PerfStats{
            .t0 = std.time.milliTimestamp(),
            .frame_num = 0,
        };
    }

    pub fn messure(s: *PerfStats) void {
        const now = std.time.milliTimestamp();
        const delta = now - s.t0;

        const messure_interval = 1000.0;
        const update_interval = 500;
        const update_interval_i: u32 = @intFromFloat(update_interval);

        const scale: f32 = messure_interval / update_interval;
        if (delta > update_interval_i) {
            // std.debug.print("\x1B[A\x1B[2K", .{});
            var fps: f32 = @floatFromInt(s.frame_num);
            fps *= scale;

            if (fps > 9000) {
                // std.debug.print("+++ omg is over 9000 {d}\n", .{fps});
            }
            // std.debug.print("+++ rendering hit {d} fps\n", .{fps});
            s.t0 += update_interval_i;
            s.frame_num = 0;
        }

        s.frame_num += 1;
    }
};
pub const CappedPlayer = struct {
    pub const lim_r = Caped.init(1, 5);
    pub const lim_h = Caped.init(-10, 10);

    p: t.Player,
    pub const default: CappedPlayer = .{ .p = .{
        .phi = 0,
        .r = lim_r.cap(1.75),
        .h = lim_h.cap(1.75),
    } };
};

pub fn PlayerUpdate(player: *t.Player, input: *const motion.HoldsAxis, td: f32) void {
    const plr = player;

    const r_speed: f32 = 3;
    const proximity = input.axes[1];
    player.r = switch (proximity) {
        motion.Axis.negative => plr.r + r_speed * td,
        motion.Axis.positive => plr.r - r_speed * td,
        else => plr.r,
    };
    plr.r = CappedPlayer.lim_r.cap(plr.r);

    const h_speed: f32 = 3;
    const height = input.axes[2];
    plr.h = switch (height) {
        motion.Axis.negative => plr.h - h_speed * td,
        motion.Axis.positive => plr.h + h_speed * td,
        else => plr.h,
    };
    plr.h = CappedPlayer.lim_h.cap(plr.h);
}

pub inline fn DefaultRng() !std.Random {
    var prng: std.Random.DefaultPrng = .init(blk: {
        var seed: u64 = 42; //for determinism xd
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    return prng.random();
}

pub const ValMonit = struct {
    printed: bool = false,
    name: []const u8,
    val: f32,

    pub fn update(self: *ValMonit, new_val: f32) void {
        self.val = new_val;
        if (self.printed) {
            for (0..3) |_| {
                std.debug.print("\x1b[2K", .{}); // wyczyść linię
                std.debug.print("\x1b[1A", .{}); // w górę
            }
        }

        std.debug.print("---------------\n", .{});
        std.debug.print("-- {s} equals \x1b[31m{d}\x1b[0m \n", .{ self.name, self.val });
        std.debug.print("---------------\n", .{});

        self.printed = true;
    }
};
