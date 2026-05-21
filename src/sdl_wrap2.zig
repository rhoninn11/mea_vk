const std = @import("std");

const escChar = @import("escapeChar.zig");

const sdl3 = @import("sdl3");
const SdlEvTpy = sdl3.events.Type;

const EvCapture = struct {
    const HistorySlots: u8 = 16;
    bins: std.EnumMap(SdlEvTpy, u32),
    key_history: [HistorySlots]?[:0]const u8 = .{null} ** HistorySlots,
    key_len: u8 = 0,

    fn init() EvCapture {
        return EvCapture{ .bins = .initFull(0) };
    }

    pub fn inc(self: *EvCapture, this_one: SdlEvTpy) void {
        if (self.bins.getPtr(this_one)) |counter| counter.* += 1;
    }

    pub fn key_action(self: *EvCapture, kb: sdl3.keycode.Keycode) void {
        var i = HistorySlots - 1;
        while (i > 0) {
            i -= 1;
            self.key_history[i + 1] = self.key_history[i];
        }

        self.key_history[0] = @tagName(kb);
    }

    pub fn raportKbHistory(self: *EvCapture, prefix: []const u8, sink: *std.Io.Writer) !u8 {
        try sink.print("{s}", .{prefix});
        for (self.key_history) |kb| if (kb) |txt| {
            try sink.print(" {s}", .{txt});
        };
        try sink.print("\n", .{});
        return 1;
    }

    pub fn raport(self: *EvCapture, prefix: []const u8, sink: *std.Io.Writer) !u8 {
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
                    try sink.print(" {d: >8} | {s: >32}\n", .{
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

const system: sdl3.InitFlags = .{
    .video = true,
    .gamepad = true,
};
pub const SdlContext = struct {
    window: ?sdl3.video.Window = null,
    ev_capture: EvCapture = .init(),
    should_close: bool = false,

    pub fn getWindow(self: *const SdlContext) sdl3.video.Window {
        return self.window.?;
    }

    fn init(name: [:0]const u8) !SdlContext {
        var self: SdlContext = .{};
        try sdl3.init(system);
        errdefer self.deinit();
        self.window = try sdl3.video.Window.init(name, 800, 600, .{
            .vulkan = true,
            .resizable = true,
        });
        return self;
    }
    fn deinit(self: *SdlContext) void {
        if (self.window) |win| {
            self.window = null;
            win.deinit();
        }
        sdl3.quit(system);
    }
    pub fn pollEvents(self: *SdlContext) void {
        while (sdl3.events.poll()) |ev| {
            self.ev_capture.inc(ev);
            switch (ev) {
                .quit => self.should_close = true,
                .key_up => |kb| {
                    const key = kb.key.?;
                    self.ev_capture.key_action(key);
                    if (key == .escape) self.should_close = true;
                },
                else => {},
            }
        }
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

pub fn vulkanSupported() bool {
    sdl3.vulkan.loadLibrary(null) catch return false;
    return true;
}

pub fn createWindow() !void {
    const flags: sdl3.video.Window.Flags = .{};
    sdl_state.window = try sdl3.video.Window.init("sdl window", 800, 600, flags);
}

pub fn destroyWindow() void {
    if (sdl_state.window) |win| win.deinit();
}

pub fn sdlDemoDeeper(io: std.Io) !void {
    try sdl3.init(system);
    defer sdl3.quit(system);
    std.debug.print("| inited\n", .{});

    const gamepads: []sdl3.joystick.Id = try sdl3.gamepad.getGamepads();
    defer sdl3.free(gamepads);
    std.debug.print("| counted {d} gamepads\n", .{gamepads.len});

    for (gamepads, 0..) |jid, i| {
        const name = try jid.getName();
        // const char *type_str = SDL_GetGamepadStringForType(type);
        // Uint16 vendor = SDL_GetGamepadVendorForID(id);
        // Uint16 product = SDL_GetGamepadProductForID(id);

        std.debug.print("|   Pad Id: +++ pad({d}) name: {s}\n", .{ i + 1, name });
        // std.debug.print("|      typ: +++ {s}\n", .{@tagName(g_type)});
        // printf("       vendor:  0x%04X\n", vendor);
        // printf("       product: 0x%04X\n\n", product);
    }

    const Timestamp = std.Io.Timestamp;
    const t0 = Timestamp.now(io, .real);
    while (t0.untilNow(io, .real).toSeconds() < 1) {
        while (sdl3.events.poll()) |ev| {
            std.debug.print("!+!+ sdl event type {s}\n", .{@tagName(ev)});
        }
    }
}
