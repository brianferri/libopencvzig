const std = @import("std");
const c = @import("root.zig").c;

/// Return OpenCV version as a string.
pub fn openCVVersion() []const u8 {
    return std.mem.span(c.openCVVersion());
}

//*    implementation done
//*    pub extern fn openCVVersion(...) [*c]const u8;
