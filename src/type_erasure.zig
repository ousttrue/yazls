const std = @import("std");

pub fn TypeErasure(comptime T: type, comptime name: []const u8) type {
    const field = @field(T, name);
    const info = @typeInfo(@TypeOf(field));
    const alignment = @typeInfo(*T).Pointer.alignment;

    switch (info) {
        .Fn => |f| {
            switch (f.args.len) {
                1 => {
                    return struct {
                        pub fn call(ptr: *anyopaque) (f.return_type orelse void) {
                            const self = @ptrCast(f.args[0].arg_type.?, @alignCast(alignment, ptr));
                            return @call(.{}, field, .{self});
                        }
                    };
                },
                2 => {
                    return struct {
                        pub fn call(ptr: *anyopaque, a0: f.args[1].arg_type.?) (f.return_type orelse void) {
                            const self = @ptrCast(f.args[0].arg_type.?, @alignCast(alignment, ptr));
                            return @call(.{}, field, .{ self, a0 });
                        }
                    };
                },
                3 => {
                    return struct {
                        pub fn call(ptr: *anyopaque, a0: f.args[1].arg_type.?, a1: f.args[2].arg_type.?) (f.return_type orelse void) {
                            const self = @ptrCast(f.args[0].arg_type.?, @alignCast(alignment, ptr));
                            return @call(.{}, field, .{ self, a0, a1 });
                        }
                    };
                },
                4 => {
                    return struct {
                        pub fn call(ptr: *anyopaque, a0: f.args[1].arg_type.?, a1: f.args[2].arg_type.?, a2: f.args[3].arg_type.?) (f.return_type orelse void) {
                            const self = @ptrCast(f.args[0].arg_type.?, @alignCast(alignment, ptr));
                            return @call(.{}, field, .{ self, a0, a1, a2 });
                        }
                    };
                },
                else => {
                    @compileError("not implemted: args.len > 4");
                },
            }
        },
        else => {
            @compileError("not Fn");
        },
    }
}
