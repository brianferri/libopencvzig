pub const asyncarray = @import("asyncarray.zig");
pub const core = @import("core.zig");
pub const calib3d = @import("calib3d.zig");
pub const dnn = @import("dnn.zig");
pub const features2d = @import("features2d.zig");
pub const highgui = @import("highgui.zig");
pub const objdetect = @import("objdetect.zig");
pub const imgcodecs = @import("imgcodecs.zig");
pub const imgproc = @import("imgproc.zig");
pub const photo = @import("photo.zig");
pub const svd = @import("svd.zig");
pub const version = @import("version.zig");
pub const videoio = @import("videoio.zig");
pub const video = @import("video.zig");

pub const c = @import("libopencv");
pub const utils = @import("utils.zig");

test "all" {
    @import("std").testing.refAllDecls(@This());
}
