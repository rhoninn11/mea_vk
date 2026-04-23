const std = @import("std");
const builtin = @import("builtin");

const vkgen = @import("vulkan_zig");
const protobuf = @import("protobuf");
const Dependency = std.Build.Dependency;

var scope_target: ?std.Build.ResolvedTarget = null;
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const maybe_override_registry = b.option([]const u8, "override-registry", "Override the path to the Vulkan registry used for the examples");
    const use_zig_shaders = b.option(bool, "zig-shader", "Use Zig shaders instead of GLSL") orelse false;

    scope_target = target;
    const triangle_exe = b.addExecutable(.{
        .name = "vk_exp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .link_libc = true,
            .optimize = optimize,
        }),
        // TODO: Remove this once x86_64 is stable
        .use_llvm = true,
    });
    b.installArtifact(triangle_exe);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = true,
    });

    const pbDep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });
    protoGen(b, pbDep, target);
    triangle_exe.root_module.addImport("protobuf", pbDep.module("protobuf"));

    const glfw_lib_fmt: []const u8 = if (builtin.target.os.tag == .windows) "{s}/bin" else "{s}/lib";
    const glfw_name: []const u8 = if (builtin.target.os.tag == .windows) "glfw3" else "glfw";

    var lib_path_mem: [1024]u8 = undefined;
    var include_path_mem: [1024]u8 = undefined;
    const glfw_path = try std.process.getEnvVarOwned(b.allocator, "GLFW_LIB");
    const include_path = try std.fmt.bufPrint(&include_path_mem, "{s}/include", .{glfw_path});
    const lib_path = try std.fmt.bufPrint(&lib_path_mem, glfw_lib_fmt, .{glfw_path});

    triangle_exe.addIncludePath(.{ .cwd_relative = include_path });
    triangle_exe.addLibraryPath(.{ .cwd_relative = lib_path });

    triangle_exe.linkSystemLibrary(glfw_name);

    // const glfw_module = b.addModule("glwf", .{
    //     .root_source_file = "glfw.zig",
    //     .target = target,
    //     .optimize = optimize,
    //     .link_libc = true,
    // });
    // triangle_exe.root_module.addImport("glfw", glfw_module);

    _ = maybe_override_registry;
    // const registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    // const registry_path: std.Build.LazyPath = if (maybe_override_registry) |override_registry|
    //     .{ .cwd_relative = override_registry }
    // else
    //     registry;

    // const vulkan = b.dependency("vulkan_zig", .{
    //     .registry = registry_path,
    // }).module("vulkan-zig");

    // triangle_exe.root_module.addImport("vulkan", vulkan);

    if (use_zig_shaders) {
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
        triangle_exe.root_module.addAnonymousImport(
            "vertex_shader",
            .{ .root_source_file = vert_spv.getEmittedBin() },
        );

        const frag_spv = b.addObject(.{
            .name = "fragment_shader",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/shaders/ref_frag.zig"),
                .target = spirv_target,
            }),
            .use_llvm = false,
        });
        triangle_exe.root_module.addAnonymousImport(
            "fragment_shader",
            .{ .root_source_file = frag_spv.getEmittedBin() },
        );
    } else {
        var scope_stack: [256]u8 = undefined;
        const prefix: []const u8 = "src/shaders";
        const sdrs_map = try find_glsl_files(prefix);
        const bld_cmd: []const []const u8 = &.{
            "glslc",
            "--target-env=vulkan1.2",
            "-o",
        };
        for (0..sdrs_map.names.len) |i| {
            var alc_local = std.heap.FixedBufferAllocator.init(scope_stack[0..]);
            const alloc = alc_local.allocator();

            const basename = sdrs_map.names[i];
            const exts: [2][]const u8 = .{ "vert", "frag" };
            var units: [2]DersUnit = undefined;
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

    const test_run_cmd = b.addRunArtifact(tests);
    test_run_cmd.has_side_effects = true;
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_run_cmd.step);
}

fn find_glsl_files(prefix: []const u8) !DersMap {
    // std.fs.cwd().openDir(prefix, .{ .iterate = true });
    var for_abs_name: [std.fs.max_path_bytes]u8 = undefined;

    const prefix_abs = try std.fs.realpath(prefix, &for_abs_name);
    const shader_dir = try std.fs.openDirAbsolute(prefix_abs, .{ .iterate = true });

    var iter = shader_dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".vert")) {
            // std.debug.print("+++ found {s}\n", .{entry.name});
        }
        if (std.mem.endsWith(u8, entry.name, ".vert")) {
            // std.debug.print("+++ found {s}\n", .{entry.name});
        }
    }
    return DersMap{
        .names = &.{ "triangle", "sprite" },
        .files = &.{
            "triangle.vert",
            "triangle.frag",
            "sprite.vert",
            "sprite.frag",
        },
    };
}

const DersMap = struct {
    files: []const []const u8,
    names: []const []const u8,
};

const DersUnit = struct {
    src: []const u8,
    unit: []const u8,
    unit_spv: []const u8,
};
fn protoGen(b: *std.Build, dep: *Dependency, target: std.Build.ResolvedTarget) void {
    const gen_step = protobuf.RunProtocStep.create(
        dep.builder,
        target,
        .{
            .destination_directory = b.path("src/gen"),
            .source_files = &.{"proto/comfy.proto"},
            .include_directories = &.{},
        },
    );

    const cmdname: []const u8 = "proto_gen";
    std.debug.print("You can always call {s}! (wink, wink)\n", .{cmdname});
    const run_step = b.step(cmdname, "compilation of .proto file in proto/");
    run_step.dependOn(&gen_step.step);
}
