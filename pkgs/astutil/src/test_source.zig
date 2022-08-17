const Self = @This();

value: u32 = 0,

fn init() Self {
    return .{};
}

fn get(self: Self) u32 {
    return self.value;
}

extern fn external_func(a: c_int) c_int;

test "empty_test" {
    const allocator = std.testing.allocator;
    _ = allocator;
}
