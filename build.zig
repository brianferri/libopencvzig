const std = @import("std");
const linkLibOpenCV = @import("build.libopencv.zig").linkLibOpenCV;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libopencvbindings = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("bindings/libopencv.h"),
    });

    const opencv = b.addLibrary(.{
        .name = "libopencv",
        .linkage = .static,
        .root_module = libopencvbindings.createModule(),
    });
    try linkLibOpenCV(b, opencv);
    opencv.root_module.addCSourceFiles(.{
        .root = b.path("bindings"),
        .files = &.{
            "imgcodecs.cpp",
            "dnn.cpp",
            "videoio.cpp",
            "svd.cpp",
            "core.cpp",
            "aruco.cpp",
            "asyncarray.cpp",
            "version.cpp",
            "persistence_filestorage.cpp",
            "photo.cpp",
            "objdetect.cpp",
            "video.cpp",
            "features2d.cpp",
            "highgui.cpp",
            "persistence_filenode.cpp",
            "imgproc.cpp",
            "calib3d.cpp",
            // "openvino/ie/inference_engine.cpp",
            // "cuda/core.cpp",
            // "cuda/bgsegm.cpp",
            // "cuda/objdetect.cpp",
            // "cuda/warping.cpp",
            // "cuda/optflow.cpp",
            // "cuda/arithm.cpp",
            // "cuda/cuda.cpp",
            // "cuda/imgproc.cpp",
            // "cuda/filters.cpp",
            // "contrib/bgsegm.cpp",
            // "contrib/freetype.cpp",
            // "contrib/xfeatures2d.cpp",
            // "contrib/wechat_qrcode.cpp",
            // "contrib/xphoto.cpp",
            // "contrib/tracking.cpp",
            // "contrib/xobjdetect.cpp",
            // "contrib/img_hash.cpp",
            // "contrib/face.cpp",
            // "contrib/ximgproc.cpp",
        },
    });

    const libopencvzig = b.addLibrary(.{
        .name = "libopencvzig",
        .root_module = b.addModule("libopencvzig", .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "libopencv", .module = opencv.root_module },
            },
        }),
    });

    b.installArtifact(libopencvzig);

    for ((try getExamples(b)).items) |example|
        try createExampleRunStep(b, example, libopencvzig);

    const lib_unit_tests = b.addTest(.{ .root_module = libopencvzig.root_module });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

const ExamplePath = struct {
    dir: []const u8,
    path: []const u8,
};
const Examples = std.ArrayListUnmanaged(ExamplePath);

fn getExamples(b: *std.Build) !Examples {
    var examples: Examples = .empty;

    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.eql(u8, entry.basename, "main.zig")) {
            const parent_dir = std.fs.path.dirname(entry.path) orelse continue;
            try examples.append(b.allocator, .{
                .dir = try b.allocator.dupe(u8, parent_dir),
                .path = try b.allocator.dupe(u8, entry.path),
            });
        }
    }

    return examples;
}

fn createExampleRunStep(
    b: *std.Build,
    example: ExamplePath,
    lib: *std.Build.Step.Compile,
) !void {
    const example_name = std.fs.path.basename(example.dir);
    const exe = b.addExecutable(.{
        .name = example_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = lib.root_module.resolved_target.?,
            .optimize = lib.root_module.optimize.?,
            .imports = &.{
                .{ .name = "libopencvzig", .module = lib.root_module },
            },
        }),
    });

    const exe_install = b.addInstallArtifact(exe, .{});
    const run_example = b.addRunArtifact(exe);
    run_example.step.dependOn(&exe_install.step);

    const run_description = try std.fmt.allocPrint(b.allocator, "Run the {s} example", .{example_name});
    const example_step = b.step(example_name, run_description);
    example_step.dependOn(&run_example.step);

    const add_source = b.addUpdateSourceFiles();
    add_source.addCopyFileToSource(exe.getEmittedAsm(), "zig-out/asm/main.asm");
    add_source.step.dependOn(b.getInstallStep());

    const asm_description = try std.fmt.allocPrint(b.allocator, "Emit the {s} example ASM file", .{example_name});
    const asm_step_name = try std.fmt.allocPrint(b.allocator, "{s}-asm", .{example_name});
    const example_asm_step = b.step(asm_step_name, asm_description);
    example_asm_step.dependOn(&add_source.step);
}
