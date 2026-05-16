const c = @cImport({
    @cInclude("SDL3/SDL.h");
});
const std = @import("std");
const SDL_JoystickID = u32;
extern fn SDL_free(mem: ?*anyopaque) void;
extern fn SDL_GetGamepads(count: *c_int) [*]SDL_JoystickID;

const SDL_GamepadType = enum(c_int) {
    SDL_GAMEPAD_TYPE_UNKNOWN = 0,
    SDL_GAMEPAD_TYPE_STANDARD = 1,
    SDL_GAMEPAD_TYPE_XBOX360 = 2,
    SDL_GAMEPAD_TYPE_XBOXONE = 3,
    SDL_GAMEPAD_TYPE_PS3 = 4,
    SDL_GAMEPAD_TYPE_PS4 = 5,
    SDL_GAMEPAD_TYPE_PS5 = 6,
    SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_PRO = 7,
    SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT = 8,
    SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT = 9,
    SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR = 10,
    SDL_GAMEPAD_TYPE_GAMECUBE = 11,
    SDL_GAMEPAD_TYPE_COUNT = 12,
};

extern fn SDL_GetGamepadNameForID(instance_id: SDL_JoystickID) [*c]const u8;
extern fn SDL_GetGamepadPathForID(instance_id: SDL_JoystickID) [*c]const u8;
extern fn SDL_GetGamepadPlayerIndexForID(instance_id: SDL_JoystickID) c_int;
// extern fn SDL_GetGamepadGUIDForID(instance_id: SDL_JoystickID) SDL_GUID;
extern fn SDL_GetGamepadVendorForID(instance_id: SDL_JoystickID) u16;
extern fn SDL_GetGamepadProductForID(instance_id: SDL_JoystickID) u16;
extern fn SDL_GetGamepadProductVersionForID(instance_id: SDL_JoystickID) u8;
extern fn SDL_GetGamepadTypeForID(instance_id: SDL_JoystickID) SDL_GamepadType;
extern fn SDL_GetRealGamepadTypeForID(instance_id: SDL_JoystickID) SDL_GamepadType;

extern fn SDL_OpenGamepad(instance_id: SDL_JoystickID) ?*SDL_Gamepad;

const SDL_Gamepad = struct {
    extern fn SDL_GetGamepadName(self: *SDL_Gamepad) [*c]const u8;
    extern fn SDL_CloseGamepad(gamepad: *SDL_Gamepad) void;

    fn close(self: *SDL_Gamepad) void {
        self.SDL_CloseGamepad();
        std.debug.print("| + close was called\n", .{});
    }
};

const DemoErrs = error{
    InitFailed,
    NoGamepad,
    OpenFailed,
    NotImplemented,
};

pub fn sdlDemo() void {
    std.debug.print("---------- SDL DEMO --------\n", .{});
    sdlDemoDeeper() catch |err| std.debug.print("!!! error {}\n", .{err});
    std.debug.print("--------- SDL DEMO END ---------\n", .{});
}

pub fn sdlDemoDeeper() !void {
    const resutl = c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_GAMEPAD);
    if (!resutl) return DemoErrs.InitFailed;
    defer c.SDL_Quit();

    std.debug.print("| inited\n", .{});

    var count: c_int = 0;
    const gamepads: [*]SDL_JoystickID = SDL_GetGamepads(&count);
    if (count == 0) return DemoErrs.NoGamepad;
    defer SDL_free(gamepads);

    std.debug.print("| counted {d} gamepads\n", .{count});
    var latch = true;
    var selected: SDL_JoystickID = undefined;
    for (0..@intCast(count)) |i| {
        const id: SDL_JoystickID = gamepads[i];
        if (latch) {
            latch = !latch;
            selected = id;
        }

        const name = SDL_GetGamepadNameForID(id);
        const g_type: SDL_GamepadType = SDL_GetGamepadTypeForID(id);
        // const char *type_str = SDL_GetGamepadStringForType(type);
        // Uint16 vendor = SDL_GetGamepadVendorForID(id);
        // Uint16 product = SDL_GetGamepadProductForID(id);

        std.debug.print("|   Pad Id: +++ pad({d}) name: {s}\n", .{ i + 1, name });
        std.debug.print("|      typ: +++ {s}\n", .{@tagName(g_type)});
        // printf("       vendor:  0x%04X\n", vendor);
        // printf("       product: 0x%04X\n\n", product);
    }

    const g_pad = SDL_OpenGamepad(selected);
    if (g_pad == null) return DemoErrs.OpenFailed;
    defer g_pad.?.close();

    std.debug.print("| haveing connection to gamepad\n", .{});

    return DemoErrs.NotImplemented;
}
