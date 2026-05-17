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

pub fn sdlDemoDeeper(io: std.Io) !void {
    const init_flags: sdl3.InitFlags = .{ .video = true, .gamepad = true };
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

    // const g_pad = SDL_OpenGamepad(selected);
    // if (g_pad == null) return DemoErrs.OpenFailed;
    // const _g_pad: *SDL_Gamepad = if (g_pad) |p| p else unreachable;
    // defer _g_pad.close();

    // std.debug.print("| connected to {s}\n", .{_g_pad.SDL_GetGamepadName()});
    // var cond = true;
    // var first = true;

    // const t0 = std.Io.Timestamp.now(io, .real);
    // var ev: SDL_Event = undefined;
    // var i: u16 = 0;
    // while (cond) {
    //     defer if (t0.untilNow(io, .real).toSeconds() > 3) {
    //         cond = false;
    //     };
    //     defer first = false;

    //     // const lx: i16 = _g_pad.SDL_GetGamepadAxis(.SDL_GAMEPAD_AXIS_LEFTX);
    //     // const ly: i16 = _g_pad.SDL_GetGamepadAxis(.SDL_GAMEPAD_AXIS_LEFTY);
    //     // const rx: i16 = _g_pad.SDL_GetGamepadAxis(.SDL_GAMEPAD_AXIS_RIGHTX);
    //     // const ry: i16 = _g_pad.SDL_GetGamepadAxis(.SDL_GAMEPAD_AXIS_RIGHTY);
    //     if (!first) {
    //         for (0..i) |_| std.debug.print("{s}", .{escChar.clear_line});
    //         for (0..i) |_| std.debug.print("{s}", .{escChar.goup_line});
    //     }
    //     i = 0;
    //     while (SDL_PollEvent(&ev)) {
    //         // const hmm = ev.type;
    //         // std.debug.print("|{d}| event type is: {d} {s}\n", .{ i, hmm, @tagName(hmm) });
    //         i += 1;
    //     }
    // }

    _ = io;
    return DemoErrs.NotImplemented;
}
