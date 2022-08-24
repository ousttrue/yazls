const std = @import("std");
const Self = @This();

value: ?u32 = 0,

fn init() Self {
    std.debug.print("", .{});
    return .{};
}

fn get(self: Self) u32 {
    return if (self.value) |value|
        value
    else
        0;
}

extern fn external_func(a: c_int) c_int;

test "empty_test" {
    const allocator = std.testing.allocator;
    _ = allocator;
}
