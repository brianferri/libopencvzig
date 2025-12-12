const std = @import("std");
const cl2cpp = @import("build.opencl_kernels.zig").cl2cpp;
const genCpuOptimizations = @import("build.cv_cpu_opts.zig").genCpuOptimizations;

const Target = struct {
    include: [][]const u8,
    files: [][]const u8,
    flags: [][]const u8,
    modules: [][]const u8,
};

const Module = struct {
    include: [][]const u8,
    files: [][]const u8,
    headers: []struct {
        source: []const u8,
        dest: []const u8,
    },
};

pub fn linkLibOpenCV(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
) !void {
    const target = lib.root_module.resolved_target.?;
    const optimize = lib.root_module.optimize.?;

    const target_config = try std.fmt.allocPrint(b.allocator, "{s}-{s}", .{
        @tagName(target.result.cpu.arch),
        @tagName(target.result.os.tag),
    });

    const opencv = b.dependency("opencv", .{});

    const libopencv = b.addLibrary(.{
        .name = "opencv",
        .linkage = .static,
        .root_module = b.createModule(.{
            .link_libc = true,
            .link_libcpp = true,
            .target = target,
            .optimize = optimize,
        }),
    });


    const base = try getConfig(Target, b, "targets", "base");
    const target_os = getConfig(Target, b, "targets", target_config) catch return error.InvalidTarget;

    const include = try std.mem.concat(b.allocator, []const u8, &.{ base.include, target_os.include });
    const files = try std.mem.concat(b.allocator, []const u8, &.{ base.files, target_os.files });
    const flags = try std.mem.concat(b.allocator, []const u8, &.{ base.flags, target_os.flags });
    const modules = try std.mem.concat(b.allocator, []const u8, &.{ base.modules, target_os.modules });

    genConfigHeaders(b, libopencv, opencv);
    try genCpuOptimizations(b, target, libopencv, flags);

    for (include) |include_path| libopencv.root_module.addIncludePath(opencv.path(include_path));
    for (&[_][]const u8{
        "dnn",     "imgproc",
        "core",    "objdetect",
        "video",   "stitching",
        "photo",   "features2d",
        "calib3d",
    }) |module| {
        const kernel_path = try cl2cpp(b, module);
        libopencv.root_module.addIncludePath(kernel_path);
        libopencv.root_module.addCSourceFile(.{
            .file = kernel_path.path(b, b.fmt("opencl_kernels_{s}.cpp", .{module})),
            .flags = flags,
        });
    }

    libopencv.root_module.addCSourceFiles(.{
        .root = opencv.path(""),
        .files = files,
        .flags = flags,
    });

    for (modules) |module| {
        const module_config = try getConfig(Module, b, "targets/modules", module);
        addModule(libopencv, opencv, module_config, flags);
    }

    if (target.result.os.tag == .macos) for (&[_][]const u8{
        "Cocoa",        "Accelerate",
        "AVFoundation", "CoreGraphics",
        "CoreMedia",    "CoreVideo",
        "QuartzCore",
    }) |framework| libopencv.root_module.linkFramework(framework, .{ .needed = true });

    linkAde(b, libopencv);
    libopencv.root_module.linkSystemLibrary("z", .{ .preferred_link_mode = .static });

    lib.root_module.linkLibrary(libopencv);
}

fn linkAde(b: *std.Build, lib: *std.Build.Step.Compile) void {
    const ade = b.dependency("ade", .{});
    lib.root_module.addIncludePath(ade.path("sources/ade/include"));
    lib.root_module.addCSourceFiles(.{
        .root = ade.path("sources/ade/source"),
        .files = &.{
            "assert.cpp",            "memory_descriptor_view.cpp",
            "graph.cpp",             "metatypes.cpp",
            "search.cpp",            "metadata.cpp",
            "node.cpp",              "subgraphs.cpp",
            "execution_engine.cpp",  "alloc.cpp",
            "memory_accessor.cpp",   "topological_sort.cpp",
            "edge.cpp",              "check_cycles.cpp",
            "memory_descriptor.cpp", "memory_descriptor_ref.cpp",
        },
    });
}

fn genConfigHeaders(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    src: *std.Build.Dependency,
) void {
    const cv_modules = b.addConfigHeader(.{
        .style = .{ .cmake = src.path("cmake/templates/opencv_modules.hpp.in") },
        .include_path = "opencv2/opencv_modules.hpp",
    }, .{
        .OPENCV_MODULE_DEFINITIONS_CONFIGMAKE =
        \\#define HAVE_OPENCV_CALIB3D
        \\#define HAVE_OPENCV_FEATURES2D
        \\#define HAVE_OPENCV_DNN
        \\#define HAVE_OPENCV_FLANN
        \\#define HAVE_OPENCV_HIGHGUI
        \\#define HAVE_OPENCV_IMGCODECS
        \\#define HAVE_OPENCV_IMGPROC
        \\#define HAVE_OPENCV_ML
        \\#define HAVE_OPENCV_OBJDETECT
        \\#define HAVE_OPENCV_PHOTO
        \\#define HAVE_OPENCV_STITCHING
        \\#define HAVE_OPENCV_VIDEO
        \\#define HAVE_OPENCV_VIDEOIO
        \\
        ,
    });
    const cvconfig = b.addConfigHeader(.{
        .style = .{ .cmake = src.path("cmake/templates/cvconfig.h.in") },
        .include_path = "opencv/cvconfig.h",
    }, .{
        .OPENCV_CUDA_ARCH_BIN = "",
        .OPENCV_CUDA_ARCH_FEATURES = "",
        .OPENCV_CUDA_ARCH_PTX = "",
    });
    var cvconfig2 = cvconfig;
    cvconfig2.include_path = "cvconfig.h";
    const custom_hal = b.addConfigHeader(.{
        .style = .{ .cmake = src.path("cmake/templates/custom_hal.hpp.in") },
        .include_path = "custom_hal.hpp",
    }, .{ ._hal_includes = "" });
    const cv_cpu_config = b.addConfigHeader(.{
        .style = .{ .cmake = src.path("cmake/templates/cv_cpu_config.h.in") },
        .include_path = "cv_cpu_config.h",
    }, .{
        .OPENCV_CPU_BASELINE_DEFINITIONS_CONFIGMAKE =
        \\#define CV_CPU_BASELINE_FEATURES 0
        ,
        .OPENCV_CPU_DISPATCH_DEFINITIONS_CONFIGMAKE =
        \\#define CV_CPU_DISPATCH_FEATURES 0
        ,
    });

    lib.root_module.addConfigHeader(cvconfig);
    lib.root_module.addConfigHeader(cvconfig2);
    lib.root_module.addConfigHeader(cv_modules);
    lib.root_module.addConfigHeader(custom_hal);
    lib.root_module.addConfigHeader(cv_cpu_config);
    lib.installHeader(cv_modules.getOutputFile(), "opencv2/opencv_modules.hpp");

    var awf = b.addWriteFiles();
    _ = awf.add("version_string.inc",
        \\"Generated with ZIG\n"
    );
    _ = awf.add("opencv_highgui_config.hpp",
        \\#define OPENCV_HIGHGUI_BUILTIN_BACKEND_STR "NONE"
        \\#define OPENCV_HIGHGUI_WITHOUT_BUILTIN_BACKEND 1
    );
    _ = awf.add("opencv_data_config.hpp",
        \\#define OPENCV_BUILD_DIR ""
        \\#define OPENCV_DATA_BUILD_DIR_SEARCH_PATHS ""
    );
    lib.root_module.addIncludePath(awf.getDirectory());
}

fn getConfig(comptime T: type, b: *std.Build, dir: []const u8, name: []const u8) !T {
    const alloc = b.allocator;

    const config_path = try b.build_root.handle.realpathAlloc(alloc, b.fmt("{s}/{s}.zon", .{ dir, name }));
    defer alloc.free(config_path);

    const config_file = try std.fs.openFileAbsolute(config_path, .{});
    defer config_file.close();

    const file = try config_file.stat();
    var buffer = try alloc.allocSentinel(u8, file.size, 0);
    errdefer alloc.destroy(&buffer);

    var reader = config_file.reader(buffer);
    try reader.interface.readSliceAll(buffer);

    return try std.zon.parse.fromSlice(T, alloc, buffer, null, .{});
}

pub fn addModule(
    lib: *std.Build.Step.Compile,
    dependency: *std.Build.Dependency,
    module: Module,
    flags: [][]const u8,
) void {
    for (module.include) |include| {
        lib.root_module.addIncludePath(dependency.path(include));
    }

    for (module.headers) |header| {
        lib.installHeader(dependency.path(header.source), header.dest);
    }

    lib.root_module.addCSourceFiles(.{
        .root = dependency.path(""),
        .files = module.files,
        .flags = flags,
    });
}
