const std = @import("std");
const vk = @import("vulkan-zig");
const m = @import("math.zig");

const u = @import("utils.zig");

const escChar = @import("escapeChar.zig");
const input = @import("input.zig");

const sdl3 = @import("sdl3");
const SdlEvTpy = sdl3.events.Type;

const EvCapture = struct {
    const HistorySlots: u8 = 16;
    bins: std.EnumMap(SdlEvTpy, u32),

    key_u_history: [HistorySlots]?[:0]const u8 = .{null} ** HistorySlots,
    key_d_history: [HistorySlots]?[:0]const u8 = .{null} ** HistorySlots,

    fn init() EvCapture {
        return EvCapture{ .bins = .initFull(0) };
    }

    pub fn inc(self: *EvCapture, this_one: SdlEvTpy) void {
        if (self.bins.getPtr(this_one)) |counter| counter.* += 1;
    }

    pub fn key_u_action(self: *EvCapture, kb: sdl3.keycode.Keycode) void {
        var i = HistorySlots - 1;
        while (i > 0) {
            i -= 1;
            self.key_u_history[i + 1] = self.key_u_history[i];
        }

        self.key_u_history[0] = @tagName(kb);
    }

    pub fn key_d_action(self: *EvCapture, kb: sdl3.keycode.Keycode) void {
        var i = HistorySlots - 1;
        while (i > 0) {
            i -= 1;
            self.key_d_history[i + 1] = self.key_d_history[i];
        }

        self.key_d_history[0] = @tagName(kb);
    }

    pub fn raportKbHistory(self: *EvCapture, prefix: []const u8, sink: *std.Io.Writer) !u8 {
        try sink.print("{s} KEY_UP   |", .{prefix});
        for (self.key_u_history) |kb| if (kb) |txt| {
            try sink.print(" {s}", .{txt});
        };
        try sink.print("\n", .{});
        try sink.print("{s} KEY_DOWN |", .{prefix});
        for (self.key_d_history) |kb| if (kb) |txt| {
            try sink.print(" {s}", .{txt});
        };
        try sink.print("\n", .{});
        return 2;
    }

    pub fn info(self: *EvCapture, prefix: []const u8, sink: *std.Io.Writer) !u8 {
        var ev_num: u32 = 0;
        var it = self.bins.iterator();
        while (it.next()) |entry| ev_num += entry.value.*;

        try sink.print("{s}event_bins({d}) > event_counted({d})\n", .{
            prefix,
            self.bins.count(),
            ev_num,
        });
        var baseline: u8 = 1;
        try sink.print("{s}additional info\n", .{prefix});
        baseline += 1;
        {
            var it2 = self.bins.iterator();
            var flip: bool = true;
            while (it2.next()) |entry| {
                if (entry.value.* == 0) continue;
                defer flip = !flip;
                if (flip) {
                    try sink.print("{s}{d: >8} | {s: <32} |", .{
                        prefix,
                        entry.value.*,
                        @tagName(entry.key),
                    });
                    baseline += 1;
                } else {
                    try sink.print(" {d: >8} | {s: <32}\n", .{
                        entry.value.*,
                        @tagName(entry.key),
                    });
                }
            }
            if (!flip) try sink.print("\n", .{});
        }
        baseline += try self.raportKbHistory(prefix, sink);
        return baseline;
    }
};

const Pointer = struct {
    x: f32,
    y: f32,
    xr: f32,
    yr: f32,

    const default: Pointer = .{ .x = 0, .y = 0, .xr = 0, .yr = 0 };

    pub fn update(self: *Pointer, mm: *const sdl3.events.MouseMotion) void {
        self.* = .{ .x = mm.x, .y = mm.y, .xr = mm.x_rel, .yr = mm.y_rel };
    }

    pub fn info(self: *const Pointer, prefix: []const u8, iowriter: *std.Io.Writer) !u8 {
        try iowriter.print(
            "{s} x:{d:>8.2} y:{d:>8.2} | xr:{d:>8.2} yr:{d:>8.2}\n",
            .{ prefix, self.x, self.y, self.xr, self.yr },
        );
        return 1;
    }
};

const Scroll = struct {
    const Self = Scroll;
    const ActFn = *const fn (*u.Slider) void;
    const Resonse = struct { a: *u.Slider, f: ActFn };
    up: ?Resonse = null,
    down: ?Resonse = null,

    pub fn update(self: *Self, mw: *const sdl3.events.MouseWheel) void {
        const delta = mw.scroll_y;

        if (delta > 0) {
            if (self.up) |up| up.f(up.a);
        } else {
            if (self.down) |down| down.f(down.a);
        }
    }

    const default: Self = .{};
};

var pointer: Pointer = .default;
pub var wheel: Scroll = .default;
pub fn peekPointer() m.vec2 {
    return .{
        pointer.x,
        -pointer.y,
    };
}
pub fn pointerInfo(prefix: []const u8, iowriter: *std.Io.Writer) !u8 {
    return pointer.info(prefix, iowriter);
}

pub const SdlContext = struct {
    const Self = SdlContext;

    const system: sdl3.InitFlags = .{
        .video = true,
        .gamepad = true,
        .sensor = true,
        .haptic = true,
    };

    window: ?sdl3.video.Window = null,
    gamepad: ?sdl3.gamepad.Gamepad = null,
    ev_capture: EvCapture = .init(),
    should_close: bool = false,

    pub fn getWindow(self: *const Self) sdl3.video.Window {
        return self.window.?;
    }

    fn init(name: [:0]const u8) !Self {
        var self: Self = .{};

        // sdl3.log.setAllPriorities(.verbose);

        try sdl3.init(system);
        errdefer self.deinit();

        sdl3.vulkan.loadLibrary(null) catch return error.vkloadfailed;

        self.window = try sdl3.video.Window.init(name, 1600, 900, .{
            .vulkan = true,
            .resizable = true,
        });

        try input.initS();
        return self;
    }
    fn deinit(self: *Self) void {
        std.debug.print("+++ sdl deinit\n", .{});
        if (self.window) |win| {
            self.window = null;
            win.deinit();
        }
        if (self.gamepad) |gpad| {
            self.gamepad = null;
            gpad.deinit();
        }
        sdl3.quit(system);
    }
    pub fn pollEvents(self: *Self) void {
        while (sdl3.events.poll()) |ev| {
            self.ev_capture.inc(ev);
            var key: sdl3.keycode.Keycode = undefined;

            switch (ev) {
                .key_up, .key_down => |kb| key = kb.key.?,
                .mouse_button_down => |mbtn| {
                    // TODO: mouse hold for dragging
                    input.sample_tirg.activated = true;
                    _ = mbtn;
                },
                .mouse_motion => |*mm| pointer.update(mm),
                .mouse_wheel => |*mw| wheel.update(mw),
                else => {},
            }

            switch (ev) {
                .key_up => {
                    self.ev_capture.key_u_action(key);
                    input.sdlKeyUp(key);
                },
                .key_down => {
                    if (key == .escape) self.should_close = true;
                    if (key == .one) {
                        self._gamepadProbe() catch |err| {
                            std.debug.print("!!! gamepad probe failed |> {s}\n", .{@errorName(err)});
                        };
                    }
                    self.ev_capture.key_d_action(key);
                    input.sdlKeyDown(key);
                },
                else => {},
            }

            switch (ev) {
                .quit => self.should_close = true,
                else => {},
            }
        }
    }
    fn _gamepadProbe(self: *Self) !void {
        const gamepads: []sdl3.joystick.Id = try sdl3.gamepad.getGamepads();
        defer sdl3.free(gamepads);

        std.debug.print("+++ SDL | gamepads found ({d})\n", .{gamepads.len});
        var selected_id: sdl3.joystick.Id = undefined;
        var guid: [33:0]u8 = undefined;

        for (gamepads) |jid| {
            const name = try jid.getName();
            jid.getGuid().toString(&guid);
            std.debug.print("|   Pad Id: +++ pad {d} | {s} | name: {s}\n", .{ jid.value, guid, name });

            if (std.mem.count(u8, name, "Steam Deck") > 0) {
                selected_id = jid;
            }
        }

        const gamepad = sdl3.gamepad.Gamepad.init(selected_id) catch {
            std.debug.print("| !!! no gamepad at the moment\n", .{});
            const err_info = sdl3.errors.get();
            if (err_info) |err| std.debug.print("| error was: {s}\n", .{err});
            return;
        };

        if (self.gamepad) |gepad| gepad.deinit();
        self.gamepad = gamepad;

        const name_str = try gamepad.getName();
        std.debug.print("+++ connected to gamepad: {s}\n", .{name_str});

        const props = try gamepad.getProperties();
        inline for (@typeInfo(@TypeOf(props)).@"struct".fields) |field| {
            const val = @field(props, field.name);
            std.debug.print("+++ property: {s:20} | {any}\n", .{ field.name, val });
        }

        const touchpad_num = gamepad.getNumTouchpads();
        std.debug.print("+++ has {d} touchpads\n", .{touchpad_num});

        const SensorType = sdl3.sensor.Type;
        inline for (std.meta.fields(SensorType)) |field| {
            const key = @field(SensorType, field.name);
            const presence = gamepad.sensorEnabled(key);
            std.debug.print("+++ pad has sensor {s:20} | {any}\n", .{ field.name, presence });
        }

        const mapping_what = try gamepad.getMapping();
        std.debug.print("+++ connected to gamepad: {s}\n", .{mapping_what});
    }
};

var sdl_state: SdlContext = .{};

pub fn getEvCounter() *EvCapture {
    return &sdl_state.ev_capture;
}
pub fn getContext() *SdlContext {
    return &sdl_state;
}

pub fn initSDL() !void {
    sdl_state = try SdlContext.init("somebody once told me...");
}
pub fn exitSDL() void {
    sdl_state.deinit();
}

pub fn vulkanSupported() !void {
    return sdl3.vulkan.loadLibrary(null);
}
