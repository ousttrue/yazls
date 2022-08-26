const std = @import("std");

pub const PrimitiveType = enum {
    const Self = @This();

    i8,
    u8,
    i16,
    u16,
    i32,
    u32,
    i64,    
    u64,    
    i128,
    u128,
    isize,
    usize,
    u29,
    c_short,
    c_ushort,
    c_int,
    c_uint,
    c_long,
    c_ulong,
    c_longlong,
    c_ulonglong,
    c_longdouble,
    f16,
    f32,
    f64,
    f128,
    bool,
    anyopaque,
    void,
    noreturn,
    type,
    anyerror,
    comptime_int,
    comptime_float,

    pub fn fromName(symbol: []const u8) ?Self {
        const info = @typeInfo(Self);
        inline for (info.Enum.fields) |field| {
            if (std.mem.eql(u8, field.name, symbol)) {
                return @intToEnum(Self, field.value);
            }
        }
        return null;
    }
};
