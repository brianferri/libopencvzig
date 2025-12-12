const std = @import("std");

pub fn cl2cpp(b: *std.Build, namespace: []const u8) !std.Build.LazyPath {
    const dir = try b.build_root.handle.openDir(
        b.fmt("opencv/modules/{s}/src/opencl/", .{namespace}),
        .{ .iterate = true },
    );
    var template_walker = try dir.walk(b.allocator);
    defer template_walker.deinit();

    var hpp_entries: std.ArrayList(u8) = .empty;
    defer hpp_entries.deinit(b.allocator);
    var cpp_entries: std.ArrayList(u8) = .empty;
    defer cpp_entries.deinit(b.allocator);

    while (try template_walker.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.basename, ".cl")) {
            const file = try entry.dir.openFile(entry.basename, .{});
            defer file.close();

            const file_contents = try entry.dir.readFileAlloc(b.allocator, entry.basename, (try file.stat()).size);
            defer b.allocator.free(file_contents);

            const no_returns = try std.mem.replaceOwned(u8, b.allocator, file_contents, "\r", "");
            defer b.allocator.free(no_returns);

            const input_expanded_tabs = try std.mem.replaceOwned(u8, b.allocator, no_returns, "\t", "  ");
            defer b.allocator.free(input_expanded_tabs);

            const stripped_content = try stripCommentsAndWhitespace(b.allocator, input_expanded_tabs);
            defer b.allocator.free(stripped_content);

            const escaped_slashes = try std.mem.replaceOwned(u8, b.allocator, stripped_content, "\\", "\\\\");
            defer b.allocator.free(escaped_slashes);

            const escaped_quotes = try std.mem.replaceOwned(u8, b.allocator, escaped_slashes, "\"", "\\\"");
            defer b.allocator.free(escaped_quotes);

            const replaced_newlines = try std.mem.replaceOwned(u8, b.allocator, escaped_quotes, "\n", "\\n\"\n\"");
            defer b.allocator.free(replaced_newlines);

            const cpp_struct = std.mem.trimEnd(u8, replaced_newlines, "\"");
            defer b.allocator.free(cpp_struct);

            var hash: [16]u8 = undefined;
            std.crypto.hash.Md5.hash(cpp_struct, &hash, .{});

            const module_name = entry.basename[0..std.mem.indexOfScalar(u8, entry.basename, '.').?];
            try cpp_entries.appendSlice(b.allocator, b.fmt(
                "struct cv::ocl::internal::ProgramEntry {s}_oclsrc={{moduleName, \"{s}\",\n\"{s}, \"{x}\", NULL}};\n",
                .{ module_name, module_name, cpp_struct, hash },
            ));
            try hpp_entries.appendSlice(b.allocator, b.fmt(
                "extern struct cv::ocl::internal::ProgramEntry {s}_oclsrc;\n",
                .{module_name},
            ));
        }
    }

    const cpp = b.fmt(
        \\// This file is auto-generated. Do not edit!
        \\
        \\#include "opencv2/core.hpp"
        \\#include "cvconfig.h"
        \\#include "opencl_kernels_{s}.hpp"
        \\
        \\#ifdef HAVE_OPENCL
        \\namespace cv
        \\{{
        \\namespace ocl
        \\{{
        \\namespace {s}
        \\{{
        \\
        \\static const char* const moduleName = "{s}";
        \\
        \\{s}
        \\}}}}}}
        \\#endif
    , .{ namespace, namespace, namespace, try cpp_entries.toOwnedSlice(b.allocator) });

    const hpp = b.fmt(
        \\// This file is auto-generated. Do not edit!
        \\
        \\#include "opencv2/core/ocl.hpp"
        \\#include "opencv2/core/ocl_genbase.hpp"
        \\#include "opencv2/core/opencl/ocl_defs.hpp"
        \\
        \\#ifdef HAVE_OPENCL
        \\
        \\namespace cv
        \\{{
        \\namespace ocl
        \\{{
        \\namespace {s}
        \\{{
        \\
        \\{s}
        \\}}}}}}
        \\#endif
    , .{ namespace, hpp_entries.items });

    var awf = b.addWriteFiles();

    _ = awf.add(b.fmt("opencl_kernels_{s}.hpp", .{namespace}), hpp);
    _ = awf.add(b.fmt("opencl_kernels_{s}.cpp", .{namespace}), cpp);

    return awf.getDirectory();
}

fn stripCommentsAndWhitespace(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var clean_buffer: std.ArrayList(u8) = .empty;
    defer clean_buffer.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        const remaining = input[i..];

        if (std.mem.startsWith(u8, remaining, "/*")) {
            i += 2;
            while (i < input.len) {
                if (std.mem.startsWith(u8, input[i..], "*/")) {
                    i += 2;
                    break;
                }
                i += 1;
            }
            continue;
        }

        if (std.mem.startsWith(u8, remaining, "//")) {
            while (i < input.len and input[i] != '\n') i += 1;
            continue;
        }

        try clean_buffer.append(allocator, input[i]);
        i += 1;
    }

    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var line_tokenizer = std.mem.tokenizeScalar(u8, clean_buffer.items, '\n');
    var first_line = true;

    while (line_tokenizer.next()) |raw_line| {
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");
        if (trimmed.len == 0) continue;

        if (!first_line) try result.append(allocator, '\n');
        first_line = false;

        try result.appendSlice(allocator, trimmed);
    }

    if (result.items[result.items.len - 1] != '\n') try result.append(allocator, '\n');
    return result.toOwnedSlice(allocator);
}
