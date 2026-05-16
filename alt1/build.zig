const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage: std.builtin.LinkMode = .dynamic;
    const c_exe = b.addExecutable(.{
        .name = "c_sample",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .linkage = linkage,
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
            "-std=c89", "-Wall", "-Wextra", //
        },
    });
    b.installArtifact(c_exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(c_exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
