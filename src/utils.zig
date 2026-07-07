const std = @import("std");
const vk = @import("vulkan-zig");
const t = @import("types.zig");
const m = @import("math.zig");
const motion = @import("motion.zig");
const phys = @import("phys.zig");
const sht = @import("shaders/types.zig");

const in = @import("input.zig");

const sdlh = @import("sdlh.zig");

pub fn trimSufix(str: []const u8, sufix: []const u8) []const u8 {
    const ends = std.mem.endsWith(u8, str, sufix);
    return if (ends) str[0..(str.len - sufix.len)] else str;
}
pub fn trimPrefix(str: []const u8, prefix: []const u8) []const u8 {
    const starts = std.mem.startsWith(u8, str, prefix);
    return if (starts) str[prefix.len..] else str;
}

pub fn strcompR(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}
pub fn strcompL(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .gt;
}

pub const Slider = struct {
    const Self = Slider;
    min: u16,
    max: u16,
    curr: u16,
    pub fn init(_min: u16, _max: u16) Slider {
        return .{ .min = _min, .max = _max, .curr = _min };
    }

    pub fn initMid(_min: u16, _max: u16) Slider {
        var base = init(_min, _max);
        base.curr = (base.min + base.max) / 2;
        return base;
    }
    pub fn inc(self: *Self) void {
        self.curr = @min(self.curr + 1, self.max);
    }
    pub fn dec(self: *Self) void {
        self.curr = if (self.curr == self.min) self.min else self.curr - 1;
    }
    pub fn incX5(self: *Self) void {
        for (0..5) |_| self.inc();
    }
    pub fn decX5(self: *Self) void {
        for (0..5) |_| self.dec();
    }

    pub fn drive(self: *Self, x_axis: motion.Axis) u16 {
        switch (x_axis) {
            motion.Axis.positive => self.inc(),
            motion.Axis.negative => self.dec(),
            else => {},
        }
        return self.curr;
    }

    pub fn frac(self: *const Self) f32 {
        return m.floaty(self.curr) / m.floaty(self.max);
    }
};

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

    pub fn update(self: *CappedPlayer, td: f32, input: *const in.DualHoldsAxis) void {
        const phi_spead: f32 = 1;
        const phi_delt = aroundAxis(input.value()[0]) * td * std.math.tau * phi_spead;
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

pub fn playerApplyInput(player: *t.Player, input: *const in.DualHoldsAxis, td: f32) void {
    const plr = player;

    const r_speed: f32 = 3;
    const proximity = input.value()[1];
    player.r = switch (proximity) {
        motion.Axis.negative => plr.r + r_speed * td,
        motion.Axis.positive => plr.r - r_speed * td,
        else => plr.r,
    };
    plr.r = CappedPlayer.lim_r.cap(plr.r);

    const h_speed: f32 = 3;
    const height = input.value()[2];
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

pub fn MemCalc(Base: type) type {
    return struct {
        pub fn memSize(based_on: []const Base) usize {
            std.debug.assert(based_on.len >= 1);
            const unit_size = @sizeOf(@TypeOf(based_on[0]));
            return unit_size * based_on.len;
        }
    };
}
pub const Smooth = struct {
    const Pvec3 = phys.InertiaPack(m.vec3);

    inertia: Pvec3.Inertia = .init(.{ 0, 0, 0 }),

    pub fn update(self: *@This(), td: f32, target: f32) void {
        self.inertia.in(.{ target, 0, 0 });
        self.inertia.simulate(td);
    }

    pub fn out(self: *@This()) f32 {
        const val, _, _ = self.inertia.out();
        return val;
    }
};
