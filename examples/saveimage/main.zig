const std = @import("std");
const cv = @import("libopencvzig");

pub fn main() !void {
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

    const device_id = try std.fmt.parseUnsigned(i32, device_id_char, 10);

    // open webcam
    var webcam = try cv.videoio.VideoCapture.init();
    try webcam.openDevice(device_id);
    defer webcam.deinit();

    var img = try cv.core.Mat.init();
    defer img.deinit();

    try webcam.read(&img);

    if (img.isEmpty()) return error.NoImage;

    try cv.imgcodecs.imWrite("saveimg.png", img);
}
