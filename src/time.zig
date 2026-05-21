const std = @import("std");
pub const IntervalInfo = struct {
    _t_interval: i64,
    interval: i64,
};

pub const Timeline = struct {
    _t0: i64,
    _t_last: i64,
    interval: ?IntervalInfo = null,

    total_s: f32,
    delta_ms: f32,

    time_passage: bool = true,

    pub fn init(io: std.Io) Timeline {
        const ts = std.Io.Timestamp.now(io, .real);
        const now = std.Io.Timestamp.toMicroseconds(ts);
        return Timeline{
            ._t0 = now,
            ._t_last = now,
            .total_s = 0,
            .delta_ms = 0.0001,
        };
    }

    pub fn update(self: *Timeline, io: std.Io) void {
        const ts = std.Io.Timestamp.now(io, .real);
        const now = std.Io.Timestamp.toMicroseconds(ts);

        const delta = @as(f32, @floatFromInt(now - self._t_last));

        self._t_last = now;
        self.delta_ms = if (self.time_passage) delta / 1000 else 0;
        self.total_s += self.delta_ms / 1000;
    }

    pub fn arm(self: *Timeline, us: i32) void {
        self.interval = IntervalInfo{
            ._t_interval = self._t_last,
            .interval = us,
        };
    }

    pub fn triggerd(self: *Timeline) bool {
        var intv: *IntervalInfo = undefined;
        if (self.interval) |_| {
            intv = &self.interval.?;
        } else {
            return false;
        }

        const delta = self._t_last - intv._t_interval;
        if (delta > intv.interval) {
            intv._t_interval += intv.interval;
            return true;
        }

        return false;
    }

    pub fn deltaS(self: *Timeline) f32 {
        return self.delta_ms / 1000;
    }

    pub fn passageToggle(self: *Timeline) void {
        self.time_passage = !self.time_passage;
    }
};
