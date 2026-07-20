const std = @import("std");
const builtin = @import("builtin");
const bt = @import("src/build/t.zig");

const files = @import("src/files.zig");

const vkgen = @import("vulkan_zig");
const protobuf = @import("protobuf");
const Dependency = std.Build.Dependency;

var scope_target: ?std.Build.ResolvedTarget = null;

pub const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    pub fn read(b: *std.Build) Options {
        return .{
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
        };
    }
};

pub fn cmdsBuild(b: *std.Build, o: Options) !void {
    const triangle_exe = b.addExecutable(.{
        .name = "shader_reader",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cmd/shader_reader.zig"),
            .target = o.target,
            .link_libc = true,
            .optimize = o.optimize,
        }),
        // TODO: Remove this once x86_64 is stable
        .use_llvm = true,
    });
    b.installArtifact(triangle_exe);

    const triangle_run_cmd = b.addRunArtifact(triangle_exe);
    triangle_run_cmd.step.dependOn(b.getInstallStep());
}

const BuildPaths = enum(u8) {
    path_patchApplyer,
    path_vulkan,
};

pub fn testInit(b: *std.Build, o: *const Options, libs_from_c: *const LibsFromC) *std.Build.Step.Compile {
    return b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = o.target,
            .optimize = o.optimize,
            .imports = &.{
                .{ .name = "rmath", .module = libs_from_c.raymath_module },
            },
        }),
        .use_llvm = switch (builtin.os.tag) {
            .windows => true,
            else => false,
        },
    });
}

const LibsFromC = struct {
    stb_tt_module: *std.Build.Module,
    raymath_module: *std.Build.Module,
    api_module: *std.Build.Module,
    compile: *std.Build.Step.Compile,
};
pub fn libsFromC(b: *std.Build, o: *const Options) LibsFromC {
    // need to be compile as library because there are
    // some errors in cTranslate for lib implementation
    const stb_truetype_build = b.addLibrary(.{
        .name = "stb_truetype",
        .root_module = b.createModule(.{
            .target = o.target,
            .optimize = o.optimize,
            .link_libc = true,
        }),
        .linkage = .static,
        .version = .{
            .major = 1,
            .minor = 26,
            .patch = 0,
        },
    });

    const inclued = b.path("src/third_party");

    const tt_header = b.path("src/third_party/stb_truetype.h");
    const raymath_header = b.path("src/third_party/raymath.h");
    const api = b.path("src/third_party/api/array.h");

    const main = b.path("src/third_party/main.c");

    stb_truetype_build.root_module.addCSourceFile(.{
        .language = .c,
        .file = main,
        .flags = &.{
            "-std=c99", "-Wall", //
        },
    });
    stb_truetype_build.root_module.addIncludePath(inclued);
    // stb_truetype_build.root_module.link_libc

    const tt_translate = b.addTranslateC(.{
        .target = o.target,
        .optimize = o.optimize,
        .root_source_file = tt_header,
    });
    const rm_translate = b.addTranslateC(.{
        .target = o.target,
        .optimize = o.optimize,
        .root_source_file = raymath_header,
    });
    const api_translate = b.addTranslateC(.{
        .target = o.target,
        .optimize = o.optimize,
        .root_source_file = api,
    });
    return .{
        .stb_tt_module = tt_translate.createModule(),
        .raymath_module = rm_translate.createModule(),
        .api_module = api_translate.createModule(),
        .compile = stb_truetype_build,
    };
}

pub fn build(b: *std.Build) !void {
    const o = Options.read(b);
    //zig to spirv is not finished IMO -> TODO: remove this option
    // TODO: EEE yooo, in 0.17 bedą dostępne samplery, co prawda, użyteczność może tak być oganiczona
    // ale, ale na przykład do np. prostych compute shaderów wystarczająca:)
    const use_zig_shaders = b.option(
        bool,
        "zig-shader",
        "Use Zig shaders instead of GLSL",
    ) orelse false;

    // try cmdsBuild(b, o);
    const libs_from_c = libsFromC(b, &o);

    const vk_registry_path = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    const vulkan_bind = b.dependency("vulkan_zig", .{ .registry = vk_registry_path }) //
        .module("vulkan-zig");

    const triangle_exe = b.addExecutable(.{
        .name = "main_app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = o.target,
            .optimize = o.optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "stbtt", .module = libs_from_c.stb_tt_module },
                .{ .name = "rmath", .module = libs_from_c.raymath_module },
                .{ .name = "oct", .module = libs_from_c.api_module },
                .{ .name = "vulkan-zig", .module = vulkan_bind },
            },
        }),
        .use_llvm = switch (builtin.os.tag) {
            .windows => true,
            else => false,
        },
    });

    triangle_exe.root_module.addIncludePath(b.path("src/third_party/"));
    triangle_exe.root_module.linkLibrary(libs_from_c.compile);

    b.installArtifact(triangle_exe);
    b.installArtifact(libs_from_c.compile);

    const sdl3_lib = b.dependency("sdl", .{
        .target = o.target,
        .optimize = o.optimize,
        .linkage = .static,
    });
    const sdl3_bind = b.dependency("sdl3", .{
        .target = o.target,
        .optimize = o.optimize,
    });

    const pbDep = b.dependency("protobuf", o);
    protoGen(b, pbDep, o.target);
    triangle_exe.root_module.addImport("protobuf", pbDep.module("protobuf"));
    triangle_exe.root_module.addImport("sdl3", sdl3_bind.module("sdl3"));

    const sdl_artifact = sdl3_lib.artifact("SDL3");
    triangle_exe.root_module.linkLibrary(sdl_artifact);
    b.installArtifact(sdl_artifact);

    if (use_zig_shaders) zig2spirv(b, triangle_exe) //back here while we using 0.17:D
    else {
        var scope_stack: [256]u8 = undefined;
        const prefix: []const u8 = "src/shaders";
        const sdrs_map = try find_glsl_files(b, prefix);
        const bld_cmd: []const []const u8 = &.{
            "glslc",
            "--target-env=vulkan1.2",
            "-g",
            "-o",
        };
        for (0..sdrs_map.names.len) |i| {
            var alc_local = std.heap.FixedBufferAllocator.init(scope_stack[0..]);
            const alloc = alc_local.allocator();

            const basename = sdrs_map.names[i];
            const exts: [2][]const u8 = .{ "vert", "frag" };
            var units: [2]bt.ShdrUnit = undefined;
            for (exts, 0..) |ext, jj| {
                units[jj].unit = try std.fmt.allocPrint(alloc, "{s}_{s}", .{ basename, ext });
                units[jj].unit_spv = try std.fmt.allocPrint(alloc, "{s}.spv", .{units[jj].unit});
                units[jj].src = try std.fmt.allocPrint(alloc, "{s}/{s}.{s}", .{ prefix, basename, ext });
            }

            for (units) |shader| {
                const spirv_bld_cmd = b.addSystemCommand(bld_cmd);
                const spv_out = spirv_bld_cmd.addOutputFileArg(shader.unit_spv);
                spirv_bld_cmd.addFileArg(b.path(shader.src));
                triangle_exe.root_module.addAnonymousImport(shader.unit, .{
                    .root_source_file = spv_out,
                });
                std.debug.print("+++ buiding {s} from {s}\n", .{ basename, shader.src });
            }
        }

        // const vert_cmd = b.addSystemCommand(bld_cmd);
        // const vert_spv = vert_cmd.addOutputFileArg("vert.spv");
        // vert_cmd.addFileArg(b.path("src/shaders/triangle.vert"));
        // triangle_exe.root_module.addAnonymousImport("triangle_vert", .{
        //     .root_source_file = vert_spv,
        // });
    }

    const triangle_run_cmd = b.addRunArtifact(triangle_exe);
    triangle_run_cmd.step.dependOn(b.getInstallStep());
    // triangle_run_cmd.skip_foreign_checks = true;

    const triangle_run_step = b.step("main", "Run the triangle example");
    triangle_run_step.dependOn(&triangle_run_cmd.step);

    const tests = testInit(b, &o, &libs_from_c);
    const test_run_cmd = b.addRunArtifact(tests);
    test_run_cmd.has_side_effects = true;
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_run_cmd.step);
}

fn zig2spirv(b: *std.Build, user_exe: *std.Build.Step.Compile) void {
    // https://claude.ai/chat/77a20a99-779d-4ab5-9b05-55416f09f559
    const spirv_target = b.resolveTargetQuery(.{
        .cpu_arch = .spirv32,
        .os_tag = .vulkan,
        .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
        .ofmt = .spirv,
    });

    const vert_spv = b.addObject(.{
        .name = "vertex_shader",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/shaders/ref_vert.zig"),
            .target = spirv_target,
        }),
        .use_llvm = false,
    });
    const frag_spv = b.addObject(.{
        .name = "fragment_shader",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/shaders/ref_frag.zig"),
            .target = spirv_target,
        }),
        .use_llvm = false,
    });

    user_exe.root_module.addAnonymousImport(
        "vertex_shader",
        .{ .root_source_file = vert_spv.getEmittedBin() },
    );

    user_exe.root_module.addAnonymousImport(
        "fragment_shader",
        .{ .root_source_file = frag_spv.getEmittedBin() },
    );
}

fn find_glsl_files(b: *std.Build, prefix: []const u8) !bt.DersMap {
    const io = b.graph.io;
    const arena = b.graph.arena;

    const glsl_shaders = try files.zipSearch(io, arena, prefix, &.{ ".vert", ".frag" });
    for (glsl_shaders.file_paths) |path| {
        std.debug.print("+++ ||| {s}\n", .{path});
    }

    return bt.DersMap{
        .names = &.{ "triangle", "sprite", "sdf" },
        .files = &.{
            "triangle.vert",
            "triangle.frag",
            "sprite.vert",
            "sprite.frag",
            "sdf.vert",
            "sdf.frag",
        },
    };
}

fn protoGen(b: *std.Build, dep: *Dependency, target: std.Build.ResolvedTarget) void {
    const gen_step = protobuf.RunProtocStep.create(
        dep.builder,
        target,
        .{
            .destination_directory = b.path("src/gen"),
            .source_files = &.{
                b.path("./proto/comfy.proto"),
                b.path("./proto/cache.proto"),
            },
            .include_directories = &.{b.path("./proto")},
        },
    );
    const cmdname: []const u8 = "proto";
    std.debug.print("You can always call {s}! (wink, wink)\n", .{cmdname});
    const run_step = b.step(cmdname, "compilation of .proto file in proto/");
    run_step.dependOn(&gen_step.step);
}
