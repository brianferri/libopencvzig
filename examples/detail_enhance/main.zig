const std = @import("std");
const cv = @import("libopencvzig");

pub fn main() anyerror!void {
    // open webcam
    var webcam = try cv.videoio.VideoCapture.init();
    try webcam.openDevice(0);
    defer webcam.deinit();

    // open display window
    const window_name = "Hello";
    var window = try cv.highgui.Window.init(window_name);
    defer window.deinit();

    var img = try cv.core.Mat.init();
    defer img.deinit();

    var img2 = try cv.core.Mat.init();
    defer img2.deinit();

    while (true) {
        webcam.read(&img) catch {
            std.debug.print("capture failed", .{});
            std.process.exit(1);
        };
        cv.photo.detailEnhance(img, &img2, 100, 0.5);

        window.imShow(img2);
        if (window.waitKey(1) >= 0) {
            break;
        }
    }
}
