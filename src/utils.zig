const std = @import("std");
const t = @import("types.zig");
const m = @import("math.zig");
const motion = @import("motion.zig");
const phys = @import("phys.zig");

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

const IVec3 = phys.InertiaPack(m.vec3);
pub const CappedPlayer = struct {
    pub const lim_r = Caped.init(1, 5);
    pub const lim_h = Caped.init(-10, 10);

    p: t.Player,
    phi_raw: f32,
    inertia: IVec3.Inertia,
    pub const default: CappedPlayer = .{
        .phi_raw = 0,
        .p = .{
            .phi = 0,
            .r = lim_r.cap(1.75),
            .h = lim_h.cap(1.75),
        },
        .inertia = .init(.{ 0, 0, 0 }),
    };

    pub fn pos(self: *CappedPlayer) m.vec3 {
        return playerPos(&self.p);
    }

    pub fn aroundAxis(phi_axis: motion.Axis) f32 {
        const phi_moved: f32 = switch (phi_axis) {
            motion.Axis.positive => 1,
            motion.Axis.negative => -1,
            else => 0,
        };
        return -phi_moved; //why minus
    }

    pub fn control(self: *CappedPlayer, input: *const motion.HoldsAxis, td: f32) void {
        const phi_spead: f32 = 1;
        const phi_delt = aroundAxis(input.axes[0]) * td * std.math.tau * phi_spead;
        self.phi_raw += phi_delt;

        self.inertia.in(.{ self.phi_raw, 0, 0 });
        self.inertia.simulate(td);

        const phi_sim = self.inertia.out()[0];
        self.p.phi = phi_sim;

        playerApplyInput(&self.p, input, td);
    }
};

pub fn playerPos(p: *t.Player) m.vec3 {
    return m.orbit_r(p.phi, p.r) + m.vec3{ 0, p.h, 0 };
}

pub fn playerApplyInput(player: *t.Player, input: *const motion.HoldsAxis, td: f32) void {
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

    pub fn update(self: *ValMonit, new_val: f32) !void {
        var buffer: [1024]u8 = undefined;
        const stderr_f = std.fs.File.stderr();
        var w = stderr_f.writer(&buffer);
        //TODO: it is a bit broken on windows
        self.val = new_val;

        if (self.printed) {
            for (0..3) |_| {
                try w.interface.print("\x1b[2K", .{}); // wyczyść linię
                try w.interface.print("\x1b[1A", .{}); // w górę
            }
        }

        try w.interface.print("---------------\n", .{});
        try w.interface.print("-- {s} equals \x1b[31m{d}\x1b[0m \n", .{ self.name, self.val });
        try w.interface.print("---------------\n", .{});
        try w.interface.flush();

        self.printed = true;
    }
};

pub fn MemCalc(Base: type) type {
    return struct {
        pub fn memSize(based_on: []const Base) usize {
            std.debug.assert(based_on.len >= 1);
            const unit_size = @sizeOf(@TypeOf(based_on[0]));
            return unit_size * based_on.len;
        }
    };
}
