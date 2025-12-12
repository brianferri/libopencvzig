const std = @import("std");

pub fn genCpuOptimizations(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    lib: *std.Build.Step.Compile,
    flags: [][]const u8,
) !void {
    for (optimization_files) |f| {
        const simd_path = try genSimdDeclarations(b, target, f);
        lib.root_module.addIncludePath(simd_path);

        var simd_files: std.ArrayList([]const u8) = .empty;
        defer simd_files.deinit(b.allocator);

        for (f.opts) |opt| {
            if (!f.force and !supportsOpt(target, opt)) continue;
            const opt_lower = try std.ascii.allocLowerString(b.allocator, @tagName(opt));
            defer b.allocator.free(opt_lower);
            try simd_files.append(b.allocator, b.fmt("{s}.{s}.cpp", .{ f.name, opt_lower }));
        }

        var all_flags: std.ArrayList([]const u8) = .empty;
        defer all_flags.deinit(b.allocator);
        const opt_flags = try collectOptFlags(b, lib.root_module, target, f);
        defer b.allocator.free(opt_flags);

        try all_flags.appendSlice(b.allocator, flags);
        try all_flags.appendSlice(b.allocator, opt_flags);

        lib.root_module.addCSourceFiles(.{
            .root = simd_path,
            .files = simd_files.items,
            .flags = all_flags.items,
        });
    }
}

fn genSimdDeclarations(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    dispatched_file: DispatchedFile,
) !std.Build.LazyPath {
    const module = dispatched_file.module;
    const simd = dispatched_file.name;
    const optimizations = dispatched_file.opts;
    const force = dispatched_file.force;

    const src_dir = try b.build_root.join(
        b.allocator,
        &.{ "opencv/modules", module, "src" },
    );

    var awf = b.addWriteFiles();

    var dispatch_blocks: std.ArrayList([]const u8) = .empty;
    defer dispatch_blocks.deinit(b.allocator);
    var dispatch_modes: std.ArrayList([]const u8) = .empty;
    defer dispatch_modes.deinit(b.allocator);

    for (optimizations) |opt| {
        const opt_lower = try std.ascii.allocLowerString(b.allocator, @tagName(opt));
        defer b.allocator.free(opt_lower);
        _ = awf.add(b.fmt("{s}.{s}.cpp", .{ simd, opt_lower }), b.fmt(
            \\#include "{s}/precomp.hpp"
            \\#include "{s}/{s}.simd.hpp"
            \\
        , .{ src_dir, src_dir, simd }));
        if (!force and !supportsOpt(target, opt)) continue;
        try dispatch_modes.append(b.allocator, @tagName(opt));
        try dispatch_blocks.append(b.allocator, b.fmt(
            \\#define CV_CPU_DISPATCH_MODE {s}
            \\#include "opencv2/core/private/cv_cpu_include_simd_declarations.hpp"
            \\
        , .{@tagName(opt)}));
    }
    try dispatch_modes.append(b.allocator, "BASELINE");

    _ = awf.add(b.fmt("{s}.simd_declarations.hpp", .{simd}), b.fmt(
        \\#define CV_CPU_SIMD_FILENAME "{s}/{s}.simd.hpp"
        \\{s}
        \\#define CV_CPU_DISPATCH_MODES_ALL {s}
        \\
        \\#undef CV_CPU_SIMD_FILENAME
        \\
    , .{
        src_dir,
        simd,
        try std.mem.join(b.allocator, "\n", dispatch_blocks.items),
        try std.mem.join(b.allocator, ", ", dispatch_modes.items),
    }));

    return awf.getDirectory();
}

const CpuOptimizations = enum {
    SSE2,
    SSE4_1,
    SSE4_2,
    AVX,
    AVX2,
    AVX512_SKX,
    AVX512_ICL,
    NEON,
    NEON_DOTPROD,
    NEON_FP16,
    LASX,
    VSX3,
    RVV,
    SVE,
};

const OptInfo = struct {
    flags: []const []const u8,
};

const DispatchedFile = struct {
    module: []const u8,
    name: []const u8,
    opts: []const CpuOptimizations,
    force: bool = false,
};

const optimization_files = [_]DispatchedFile{
    .{ .module = "core", .name = "stat", .opts = &.{ .SSE4_2, .AVX2, .LASX } },
    .{ .module = "core", .name = "convert_scale", .opts = &.{ .SSE2, .AVX2, .LASX } },
    .{ .module = "core", .name = "count_non_zero", .opts = &.{ .SSE2, .AVX2, .LASX } },
    .{ .module = "core", .name = "has_non_zero", .opts = &.{ .SSE2, .AVX2, .LASX } },
    .{ .module = "core", .name = "mean", .opts = &.{ .SSE2, .AVX2, .LASX } },
    .{ .module = "core", .name = "merge", .opts = &.{ .SSE2, .AVX2, .LASX } },
    .{ .module = "core", .name = "split", .opts = &.{ .SSE2, .AVX2, .LASX } },
    .{ .module = "core", .name = "sum", .opts = &.{ .SSE2, .AVX2, .LASX } },
    .{ .module = "core", .name = "mathfuncs_core", .opts = &.{ .SSE2, .AVX, .AVX2, .LASX } },
    .{ .module = "core", .name = "arithm", .opts = &.{ .SSE2, .SSE4_1, .AVX2, .VSX3, .LASX } },
    .{ .module = "core", .name = "convert", .opts = &.{ .SSE2, .AVX2, .VSX3, .LASX } },
    .{ .module = "core", .name = "matmul", .opts = &.{ .SSE2, .SSE4_1, .AVX2, .AVX512_SKX, .NEON_DOTPROD, .LASX } },
    .{ .module = "core", .name = "norm", .opts = &.{ .SSE2, .SSE4_1, .AVX, .AVX2, .NEON_DOTPROD, .LASX } },
    .{ .module = "calib3d", .name = "undistort", .opts = &.{ .SSE2, .AVX2 } },
    .{ .module = "features2d", .name = "sift", .opts = &.{ .SSE4_1, .AVX2, .AVX512_SKX } },
    .{ .module = "imgproc", .name = "accum", .opts = &.{ .SSE4_1, .AVX, .AVX2 } },
    .{ .module = "imgproc", .name = "bilateral_filter", .opts = &.{ .SSE2, .AVX2 } },
    .{ .module = "imgproc", .name = "box_filter", .opts = &.{ .SSE2, .SSE4_1, .AVX2, .AVX512_SKX } },
    .{ .module = "imgproc", .name = "filter", .opts = &.{ .SSE2, .SSE4_1, .AVX2 } },
    .{ .module = "imgproc", .name = "color_hsv", .opts = &.{ .SSE2, .SSE4_1, .AVX2 } },
    .{ .module = "imgproc", .name = "color_rgb", .opts = &.{ .SSE2, .SSE4_1, .AVX2 } },
    .{ .module = "imgproc", .name = "color_yuv", .opts = &.{ .SSE2, .SSE4_1, .AVX2 } },
    .{ .module = "imgproc", .name = "median_blur", .opts = &.{ .SSE2, .SSE4_1, .AVX2, .AVX512_SKX } },
    .{ .module = "imgproc", .name = "morph", .opts = &.{ .SSE2, .SSE4_1, .AVX2 } },
    .{ .module = "imgproc", .name = "smooth", .opts = &.{ .SSE2, .SSE4_1, .AVX2, .AVX512_ICL } },
    .{ .module = "imgproc", .name = "sumpixels", .opts = &.{ .SSE2, .AVX2, .AVX512_SKX } },
    .{ .module = "gapi", .name = "backends/fluid/gfluidimgproc_func", .opts = &.{ .SSE4_1, .AVX2 } },
    .{ .module = "gapi", .name = "backends/fluid/gfluidcore_func", .opts = &.{ .SSE4_1, .AVX2 } },
    .{ .module = "dnn", .name = "layers/layers_common", .opts = &.{ .AVX, .AVX2, .AVX512_SKX, .RVV, .LASX, .NEON, .SVE }, .force = false },
    .{ .module = "dnn", .name = "int8layers/layers_common", .opts = &.{ .AVX2, .AVX512_SKX, .RVV, .LASX, .NEON }, .force = false },
    .{ .module = "dnn", .name = "layers/cpu_kernels/conv_block", .opts = &.{ .AVX, .AVX2, .NEON, .NEON_FP16 }, .force = false },
    .{ .module = "dnn", .name = "layers/cpu_kernels/conv_depthwise", .opts = &.{ .AVX, .AVX2, .RVV, .LASX }, .force = false },
    .{ .module = "dnn", .name = "layers/cpu_kernels/conv_winograd_f63", .opts = &.{ .AVX, .AVX2, .NEON, .NEON_FP16 } },
    .{ .module = "dnn", .name = "layers/cpu_kernels/fast_gemm_kernels", .opts = &.{ .AVX, .AVX2, .NEON, .LASX }, .force = false },
};

const opt_table: std.EnumMap(CpuOptimizations, OptInfo) = .init(.{
    .SSE2 = .{ .flags = &.{"-msse2"} },
    .SSE4_1 = .{ .flags = &.{"-msse4.1"} },
    .SSE4_2 = .{ .flags = &.{"-msse4.2"} },
    .AVX = .{ .flags = &.{"-mavx"} },
    .AVX2 = .{ .flags = &.{"-mavx2"} },
    .AVX512_SKX = .{ .flags = &.{ "-mavx512f", "-mavx512dq", "-mavx512bw", "-mavx512vl" } },
    .AVX512_ICL = .{ .flags = &.{ "-mavx512f", "-mavx512dq", "-mavx512bw", "-mavx512vl", "-mavx512vnni" } },
    .NEON = .{ .flags = &.{"-march=armv8-a+simd"} },
    .NEON_DOTPROD = .{ .flags = &.{"-march=armv8.2-a+dotprod"} },
    .NEON_FP16 = .{ .flags = &.{"-march=armv8.2-a+fp16"} },
    .RVV = .{ .flags = &.{"-march=rv64gcv"} },
    .SVE = .{ .flags = &.{"-march=armv8-a+sve"} },
    .LASX = .{ .flags = &.{"-mlasx"} },
    .VSX3 = .{ .flags = &.{"-mcpu=power9"} },
});

fn supportsOpt(target: std.Build.ResolvedTarget, opt: CpuOptimizations) bool {
    const cpu = target.result.cpu;
    const arch = cpu.arch;
    const features = cpu.features;

    return switch (arch) {
        .x86_64 => switch (opt) {
            .SSE2 => std.Target.x86.featureSetHas(features, .sse2),
            .SSE4_1 => std.Target.x86.featureSetHas(features, .sse4_1),
            .SSE4_2 => std.Target.x86.featureSetHas(features, .sse4_2),
            .AVX => std.Target.x86.featureSetHas(features, .avx),
            .AVX2 => std.Target.x86.featureSetHas(features, .avx2),
            .AVX512_SKX => std.Target.x86.featureSetHasAll(features, .{ .avx512f, .avx512cd, .avx512bw, .avx512dq, .avx512vl }),
            .AVX512_ICL => std.Target.x86.featureSetHasAll(features, .{ .avx512f, .avx512cd, .avx512bw, .avx512dq, .avx512vl, .avx512vnni }),
            else => false,
        },

        .aarch64 => switch (opt) {
            .NEON => std.Target.aarch64.featureSetHas(features, .neon),
            .NEON_DOTPROD => std.Target.aarch64.featureSetHasAll(features, .{ .neon, .dotprod }),

            //? Exclude NEON_FP16 on macOS
            .NEON_FP16 => !target.result.os.tag.isDarwin() and
                std.Target.aarch64.featureSetHasAll(features, .{ .neon, .fullfp16 }),

            .SVE => std.Target.aarch64.featureSetHas(features, .sve),
            else => false,
        },

        .riscv64 => switch (opt) {
            .RVV => std.Target.riscv.featureSetHas(features, .v),
            else => false,
        },

        .loongarch64 => switch (opt) {
            .LASX => std.Target.loongarch.featureSetHas(features, .lasx),
            else => false,
        },

        .powerpc64le => switch (opt) {
            .VSX3 => std.Target.powerpc.featureSetHas(features, .vsx),
            else => false,
        },

        else => false,
    };
}

fn collectOptFlags(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    dispatched_file: DispatchedFile,
) ![][]const u8 {
    var result: std.ArrayList([]const u8) = .empty;

    const opts = dispatched_file.opts;
    const force = dispatched_file.force;
    for (opts) |opt| {
        if (!force and !supportsOpt(target, opt)) continue;
        if (opt_table.get(opt)) |info| {
            module.addCMacro(b.fmt("CV_CPU_COMPILE_{s}", .{@tagName(opt)}), "1");
            module.addCMacro(b.fmt("CV_CPU_BASELINE_COMPILE_{s}", .{@tagName(opt)}), "1");
            for (info.flags) |flag| try result.append(b.allocator, flag);
        }
    }

    return result.toOwnedSlice(b.allocator);
}
