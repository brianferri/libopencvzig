const std = @import("std");
const cv = @import("libopencvzig").version;

pub fn main() anyerror!void {
    std.debug.print("version:\t{s}\n", .{cv.openCVVersion()});
}
