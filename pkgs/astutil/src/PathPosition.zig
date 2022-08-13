const std = @import("std");
const FixedPath = @import("./FixedPath.zig");
const Self = @This();

path: FixedPath,
loc: std.zig.Token.Loc,
