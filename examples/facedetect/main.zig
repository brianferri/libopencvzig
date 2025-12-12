const std = @import("std");
const cv = @import("libopencvzig");
const cv_c_api = cv.c_api;

/// OpenCV has an enum:
///
/// ```cpp
/// struct CV_EXPORTS UMatData
/// {
///     enum MemoryFlag { COPY_ON_MAP=1, HOST_COPY_OBSOLETE=2,
///         DEVICE_COPY_OBSOLETE=4, TEMP_UMAT=8, TEMP_COPIED_UMAT=24,
///         USER_ALLOCATED=32, DEVICE_MEM_MAPPED=64,
///         ASYNC_CLEANUP=128
///     };
///     ...
/// ```
///
/// That it uses to make a bitmask of flags that can be set on a Mat, ex:
///
/// ```cpp
/// inline void UMatData::markDeviceCopyObsolete(bool flag)
/// {
///     if(flag)
///         flags |= DEVICE_COPY_OBSOLETE;
///     else
///         flags &= ~DEVICE_COPY_OBSOLETE;
/// }
/// ```
///
/// ```cpp
/// #define __CV_ENUM_FLAGS_BITWISE_AND_EQ(EnumType, Arg1Type)                          \
/// static inline EnumType& operator&=(EnumType& _this, const Arg1Type& val)            \
/// {                                                                                   \
///     _this = static_cast<EnumType>(static_cast<int>(_this) & static_cast<int>(val)); \
///     return _this;                                                                   \
/// }                                                                                   \
/// ```
///
/// This usage of an enum is fundamentally wrong as it doesn't define all possible combinations.
/// In the event that flags `COPY_ON_MAP` and `HOST_COPY_OBSOLETE` are set at the same time we would have:
///
/// ```
/// 00000001 => COPY_ON_MAP = 1
/// 00000100 => HOST_COPY_OBSOLETE = 4
/// -------- |
/// 00000101 = 5
/// ```
///
/// But 5 isn't anywhere in that enum, so it's basically assigning a "random" value to a variable of a type which
/// is made specifically to hold precise values.
///
/// Zig, in `Debug` and `ReleaseSafe` modes, will sanitize this behavior, saying:
///
/// ```
/// thread 87361 panic: load of value 4294967291, which is not valid for type 'const UMatData::MemoryFlag'
/// ```
///
/// in our case `4294967291` is `-5`, which in 2's complement is precisely `...00000101`, which comes from:
///
/// ```
/// 00000001 => COPY_ON_MAP = -1 (2's complement)
/// 11111011 => ~HOST_COPY_OBSOLETE = ~-4 (2's complement)
/// -------- &
/// 00000101 = -5 (2's complement)
/// ```
pub fn main() !void {
    switch (@import("builtin").mode) {
        .Debug, .ReleaseSafe => @compileError("This example relies on bad C++ practices, running in `" ++
            @tagName(@import("builtin").mode) ++
            "` mode will cause a panic, please recompile using `" ++
            @tagName(std.builtin.OptimizeMode.ReleaseFast) ++
            "` or `" ++
            @tagName(std.builtin.OptimizeMode.ReleaseSafe) ++
            "`"),
        else => {},
    }

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer if (gpa.deinit() != .ok) @panic("Leak detected");

    var args = try std.process.argsWithAllocator(allocator);
    const prog = args.next();
    const device_id_char = args.next() orelse {
        std.log.err("usage: {s} [cameraID]", .{prog.?});
        std.process.exit(1);
    };
    args.deinit();

    const device_id = try std.fmt.parseUnsigned(c_int, device_id_char, 10);

    // open webcam
    var webcam = try cv.videoio.VideoCapture.init();
    try webcam.openDevice(device_id);
    defer webcam.deinit();

    // open display window
    const window_name = "Face Detect";
    var window = try cv.highgui.Window.init(window_name);
    defer window.deinit();

    // prepare image matrix
    var img = try cv.core.Mat.init();
    defer img.deinit();

    // load classifier to recognize faces
    var classifier = try cv.objdetect.CascadeClassifier.init();
    defer classifier.deinit();

    classifier.load("examples/facedetect/data/haarcascade_frontalface_default.xml") catch {
        std.debug.print("no xml", .{});
        std.process.exit(1);
    };

    const blue = cv.core.Color{ .b = 255 };
    while (true) {
        webcam.read(&img) catch {
            std.debug.print("capture failed", .{});
            std.process.exit(1);
        };
        if (img.isEmpty()) continue;

        var rects = try classifier.detectMultiScale(img, allocator);
        defer rects.deinit(allocator);
        const found_num = rects.items.len;
        std.debug.print("found {d} faces\n", .{found_num});
        for (rects.items) |r| {
            std.debug.print("x:\t{}, y:\t{}, w:\t{}, h:\t{}\n", .{ r.x, r.y, r.width, r.height });
            _ = cv.imgproc.rectangle(&img, r, blue, 3);
        }

        window.imShow(img);
        if (window.waitKey(1) >= 0) {
            break;
        }
    }
}
