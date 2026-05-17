const std = @import("std");

const TarOpt = struct {
    t: std.Build.ResolvedTarget,
    o: std.builtin.OptimizeMode,
};

pub fn dependencies(b: *std.Build, teo: *const TarOpt) *std.Build.Dependency {
    const raylib_dep = b.dependency("raylib", .{
        .target = teo.t,
        .optimize = teo.o,
        .linkage = .dynamic,
    });

    return raylib_dep;
}

pub fn build(b: *std.Build) void {
    const teo = TarOpt{
        .t = b.standardTargetOptions(.{}),
        .o = b.standardOptimizeOption(.{}),
    };

    const c_exe = b.addExecutable(.{
        .name = "c_sample",
        .root_module = b.createModule(.{
            .target = teo.t,
            .optimize = teo.o,
        }),
        .linkage = .dynamic,
        .version = .{
            .major = 0,
            .minor = 0,
            .patch = 0,
            .build = "some_build_hash_mayby",
        },
    });
    c_exe.root_module.addIncludePath(b.path("src"));
    c_exe.root_module.addCSourceFile(.{
        .language = .c,
        .file = b.path("src/main.c"),
        .flags = &.{
            "-std=c99", "-Wall", "-Wextra", //
        },
    });

    const raylib_dep = dependencies(b, &teo);
    const raylib_build = raylib_dep.artifact("raylib");

    c_exe.root_module.link_libc = true;
    c_exe.root_module.linkLibrary(raylib_build);

    b.installArtifact(c_exe);
    b.installArtifact(raylib_build);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(c_exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
