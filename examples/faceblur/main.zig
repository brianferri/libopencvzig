const std = @import("std");
const cv = @import("libopencvzig");
const cv_c_api = cv.c_api;

pub fn main() anyerror!void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer if (gpa.deinit() != .ok) @panic("Leak detected");

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
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

    const size = cv.core.Size{ .width = 75, .height = 75 };
    while (true) {
        webcam.read(&img) catch {
            std.debug.print("capture failed", .{});
            std.process.exit(1);
        };
        if (img.isEmpty()) {
            continue;
        }
        var rects = try classifier.detectMultiScale(img, allocator);
        defer rects.deinit(allocator);
        const found_num = rects.items.len;
        std.debug.print("found {d} faces\n", .{found_num});
        for (rects.items) |r| {
            std.debug.print("x:\t{}, y:\t{}, w:\t{}, h:\t{}\n", .{ r.x, r.y, r.width, r.height });
            _ = cv.imgproc.gaussianBlur(img, &img, size, 0, 0, .{});
        }

        window.imShow(img);
        if (window.waitKey(1) >= 0) {
            break;
        }
    }
}
