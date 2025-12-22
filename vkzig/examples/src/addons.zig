const std = @import("std");

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
            std.debug.print("\x1B[A\x1B[2K", .{});
            var fps: f32 = @floatFromInt(s.frame_num);
            fps *= scale;

            if (fps > 9000) {
                std.debug.print("+++ omg is over 9000 {d}\n", .{fps});
            }
            std.debug.print("+++ rendering hit {d} fps\n", .{fps});
            s.t0 += update_interval_i;
            s.frame_num = 0;
        }

        s.frame_num += 1;
    }
};

pub const Timeline = struct {
    _t0: i64,
    _t_last: i64,

    total_s: f32,
    delta_s: f32,

    pub fn init() Timeline {
        const now = std.time.microTimestamp();
        return Timeline{
            ._t0 = now,
            ._t_last = now,
            .total_s = 0,
            .delta_s = 0.0001,
        };
    }

    pub fn update(self: *Timeline) void {
        const now = std.time.microTimestamp();

        const total = @as(f32, @floatFromInt(now - self._t0));
        const delta = @as(f32, @floatFromInt(now - self._t_last));

        self._t_last = now;
        self.total_s = total / 1000000;
        self.delta_s = delta / 1000000;
    }
};
