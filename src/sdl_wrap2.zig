const std = @import("std");

const escChar = @import("escapeChar.zig");

const DemoErrs = error{
    InitFailed,
    NoGamepad,
    OpenFailed,
    NotImplemented,
};

pub fn sdlDemo(io: std.Io) void {
    std.debug.print("---------- SDL DEMO --------\n", .{});
    sdlDemoDeeper(io) catch |err| std.debug.print("!!! error {}\n", .{err});
    std.debug.print("--------- SDL DEMO END ---------\n", .{});
}

const sdl3 = @import("sdl3");

const init_flags: sdl3.InitFlags = .{ .video = true, .gamepad = true };

const LocalState = struct {
    window: ?sdl3.video.Window = null,
};

var sdl_state: LocalState = .{};

pub fn initSDL() !void {
    return sdl3.init(init_flags);
}
pub fn exitSDL() void {
    sdl3.quit(init_flags);
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

pub fn pollEvents() void {
    while (sdl3.events.poll()) |ev| {
        std.debug.print("!+!+ sdl event type {s}\n", .{@tagName(ev)});
    }
}

pub fn sdlDemoDeeper(io: std.Io) !void {
    try sdl3.init(init_flags);
    defer sdl3.quit(init_flags);
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

    return DemoErrs.NotImplemented;
}
