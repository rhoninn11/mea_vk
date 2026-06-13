const std = @import("std");
const vk = @import("vulkan-zig");
const t = @import("types.zig");
const m = @import("math.zig");
const motion = @import("motion.zig");
const phys = @import("phys.zig");

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
    _min: u16,
    _max: u16,
    curr: u16,

    pub fn init(min: u16, max: u16) Slider {
        return .{
            ._min = min,
            ._max = max,
            .curr = (min + max) / 2,
        };
    }
    pub fn inc(self: *Self) void {
        self.curr = @min(self.curr + 1, self._max);
    }
    pub fn dec(self: *Self) void {
        self.curr = if (self.curr == self._min) self._min else self.curr - 1;
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

pub const PerfStats = struct {
    t0: i64,
    frame_num: u32,

    pub fn init(io: std.Io) PerfStats {
        std.debug.print("--- empty line ---\n", .{});
        const ts = std.Io.Timestamp.now(io, .real);
        const now_ms = std.Io.Timestamp.toMilliseconds(ts);
        return PerfStats{
            .t0 = now_ms,
            .frame_num = 0,
        };
    }

    pub fn messure(s: *PerfStats, io: std.Io) void {
        const ts = std.Io.Timestamp.now(io, .real);
        const now_ms = std.Io.Timestamp.toMilliseconds(ts);
        const delta = now_ms - s.t0;

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

    pub fn control(self: *CappedPlayer, input: *const in.DulaHoldsAxis, td: f32) void {
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

pub fn playerApplyInput(player: *t.Player, input: *const in.DulaHoldsAxis, td: f32) void {
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

pub const DbgMonitor = struct {
    linecount: u8 = 0,
    enabled: bool = false,

    pub fn clearPrev(self: *DbgMonitor, iowriter: *std.Io.Writer) !void {
        if (self.linecount != 0) for (0..self.linecount) |_| {
            try iowriter.print("\x1b[2K", .{}); // wyczyść linię
            try iowriter.print("\x1b[1A", .{}); // w górę
        };
    }
    pub const DbgVals = struct {
        phi: f32,
        inst_num: u16,
        observer_pos: m.vec3,
        win_size: vk.Extent2D,
    };
    pub fn update(
        self: *DbgMonitor,
        io: std.Io,
        current: *const DbgVals,
    ) !void {
        if (!self.enabled) return;

        var buffer: [1024]u8 = undefined;
        const stdout: std.Io.File = .stderr();
        var w = stdout.writer(io, &buffer);

        //const pointer to interface was the right way on windows
        const iowriter: *std.Io.Writer = &w.interface;

        try self.clearPrev(iowriter);

        var lines: u8 = 9;
        try iowriter.print("---------------\n", .{});
        try iowriter.print("--- {s: <12}: \x1b[31m{d}\x1b[0m\n", .{ "phi", current.phi });
        try iowriter.print("--- {s: <12}: \x1b[32m{d}\x1b[0m\n", .{ "inst_num", current.inst_num });
        try iowriter.print("--- {s: <12}: \x1b[33m{}\x1b[0m\n", .{ "observer", current.observer_pos });
        try iowriter.print("--- {s: <12}: \x1b[33m{}\x1b[0m\n", .{ "window w", current.win_size.width });
        try iowriter.print("--- {s: <12}: \x1b[33m{}\x1b[0m\n", .{ "window h", current.win_size.height });
        try iowriter.print("---------------\n", .{});
        lines += try sdlh.pointerInfo("---", iowriter);
        try iowriter.print("---------------\n", .{});
        lines += try sdlh.getEvCounter().info("--- ", iowriter);
        try iowriter.print("---------------\n", .{});
        try iowriter.flush();

        self.linecount = lines;
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
