const std = @import("std");
const builtin = @import("builtin");
const FixedStringBuffer = @import("./FixedStringBuffer.zig");
const logger = std.log.scoped(.FixedPath);
const Self = @This();

buffer: FixedStringBuffer = .{},

pub fn fromFullpath(fullpath: []const u8) Self {
    var self = Self{};
    self.buffer.assign(fullpath);
    var i: usize = 0;
    while (i < fullpath.len) {
        var c = fullpath[i];
        var utf8len = std.unicode.utf8ByteSequenceLength(c) catch unreachable;
        if (c == '\\') {
            self.buffer._buffer[i] = '/';
        }
        i += utf8len;
    }
    return self;
}

pub fn fromCwd() !Self {
    var self = Self{};
    self.len = (try std.os.getcwd(&self._buffer)).len;
    return self;
}

pub fn findZig(allocator: std.mem.Allocator) !Self {
    const env_path = std.process.getEnvVarOwned(allocator, "PATH") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            return error.NoPathEnv;
        },
        else => return err,
    };
    defer allocator.free(env_path);

    const exe_extension = builtin.target.exeFileExt();
    const zig_exe = try std.fmt.allocPrint(allocator, "zig{s}", .{exe_extension});
    defer allocator.free(zig_exe);

    var it = std.mem.tokenize(u8, env_path, &[_]u8{std.fs.path.delimiter});
    while (it.next()) |path| {
        if (builtin.os.tag == .windows) {
            if (std.mem.indexOfScalar(u8, path, '/') != null) continue;
        }
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, zig_exe });
        defer allocator.free(full_path);

        if (!std.fs.path.isAbsolute(full_path)) continue;

        const file = std.fs.openFileAbsolute(full_path, .{}) catch continue;
        defer file.close();
        const stat = file.stat() catch continue;
        if (stat.kind == .Directory) continue;

        return fromFullpath(full_path);
    }
    return error.ZigNotFound;
}

pub fn fromSelfExe() !Self {
    var exe_dir_bytes: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const exe_dir_path = try std.fs.selfExeDirPath(&exe_dir_bytes);
    return fromFullpath(exe_dir_path);
}

pub fn fromUri(uri: []const u8) !Self {
    var self = Self{};
    try self.parseUri(uri);
    return self;
}

// Original code: https://github.com/andersfr/zig-lsp/blob/master/uri.zig
fn parseHex(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => return error.UriBadHexChar,
    };
}

pub fn exists(self: Self) bool {
    if (std.fs.openFileAbsolute(self.slice(), .{})) |f| {
        f.close();
        return true;
    } else |_| {
        return false;
    }
}

pub fn parseUri(self: *Self, str: []const u8) !void {
    if (str.len < 7 or !std.mem.eql(u8, "file://", str[0..7])) return error.UriBadScheme;

    const path = if (std.fs.path.sep == '\\') str[8..] else str[7..];
    var i: usize = 0;
    var j: usize = 0;
    while (j < path.len) : (i += 1) {
        if (path[j] == '%') {
            if (j + 2 >= path.len) return error.UriBadEscape;
            const upper = try parseHex(path[j + 1]);
            const lower = try parseHex(path[j + 2]);
            self.buffer._buffer[i] = (upper << 4) + lower;
            j += 3;
        } else {
            self.buffer._buffer[i] = path[j];
            j += 1;
        }
    }

    // Remove trailing separator
    if (i > 0 and self.buffer._buffer[i - 1] == '/') {
        i -= 1;
    }
    self.buffer.len = i;
}

pub fn len(self: Self) usize {
    return self.buffer.len;
}

pub fn slice(self: Self) []const u8 {
    return self.buffer.slice();
}

pub fn parent(self: Self) ?Self {
    return if (std.fs.path.dirname(self.slice())) |dirname|
        fromFullpath(dirname)
    else
        null;
}

fn extends(self: *Self, text: []const u8) void {
    std.mem.copy(u8, self.buffer._buffer[self.len()..], text);
    var i: usize = self.buffer.len;
    const end = self.buffer.len + text.len;
    while (i < end) {
        const c = self.buffer._buffer[i];
        const utf8len = std.unicode.utf8ByteSequenceLength(c) catch unreachable;
        if (c == '\\') {
            self.buffer._buffer[i] = '/';
        }
        i += utf8len;
    }

    self.buffer.len = end;
}

// try std.fs.path.resolve(allocator, &[_][]const u8{ exe_dir_path,  name});
pub fn child(self: Self, name: []const u8) Self {
    var copy = fromFullpath(self.slice());
    copy.buffer.pushChar('/');

    if (std.mem.startsWith(u8, name, "./")) {
        copy.extends(name[2..]);
    } else if (name[0] == '/') {
        copy.extends(name[1..]);
    } else {
        copy.extends(name);
    }

    return copy;
}

pub fn isAbsoluteExists(self: Self) bool {
    if (!std.fs.path.isAbsolute(self.slice())) {
        return false;
    }
    std.fs.cwd().access(self.slice(), .{}) catch {
        return false;
    };
    return true;
}

pub fn exec(self: Self, allocator: std.mem.Allocator, args: []const []const u8) !std.ChildProcess.ExecResult {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    var _args = std.ArrayList([]const u8).init(allocator);
    defer _args.deinit();

    var w = buffer.writer();
    try w.print("{s}", .{self.slice()});
    try _args.append(self.slice());
    for (args) |arg| {
        try w.print(" {s}", .{arg});
        try _args.append(arg);
    }

    logger.debug("{s}", .{buffer.items});
    return std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = _args.items,
        .max_output_bytes = 1024 * 1024 * 50,
    });
}

pub fn allocReadContents(self: Self, allocator: std.mem.Allocator) ![]const u8 {
    var file = try std.fs.cwd().openFile(self.slice(), .{});
    defer file.close();

    return try file.readToEndAlloc(
        allocator,
        std.math.maxInt(usize),
    );
    // return try file.readToEndAllocOptions(
    //     allocator,
    //     std.math.maxInt(usize),
    //     null,
    //     @alignOf(u8),
    //     0,
    // );
}

pub const FileIterator = struct {
    base: Self,
    dir: std.fs.IterableDir,
    it: std.fs.IterableDir.Iterator = undefined,
    pub fn deinit(self: *@This()) void {
        self.dir.close();
    }

    pub fn next(self: *@This()) !?std.fs.IterableDir.Entry {
        if (try self.it.next()) |entry| {
            return entry;
        } else {
            return null;
        }
    }
};

pub fn iterateChildren(self: Self) !FileIterator {
    var it = FileIterator{
        .base = self,
        .dir = try std.fs.openIterableDirAbsolute(self.slice(), .{}),
    };
    it.it = it.dir.iterate();
    return it;
}

// http://tools.ietf.org/html/rfc3986#section-2.2
const reserved_chars = &[_]u8{
    '!', '#', '$', '%', '&', '\'',
    '(', ')', '*', '+', ',', ':',
    ';', '=', '?', '@', '[', ']',
};

const reserved_escapes = blk: {
    var escapes: [reserved_chars.len][3]u8 = [_][3]u8{[_]u8{undefined} ** 3} ** reserved_chars.len;

    for (reserved_chars) |c, i| {
        escapes[i][0] = '%';
        _ = std.fmt.bufPrint(escapes[i][1..], "{X}", .{c}) catch unreachable;
    }
    break :blk &escapes;
};

pub fn allocToUri(self: Self, allocator: std.mem.Allocator) ![]const u8 {
    if (self.len() == 0) return "";
    const prefix = if (builtin.os.tag == .windows) "file:///" else "file://";

    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice(prefix);

    for (self.slice()) |char| {
        if (char == std.fs.path.sep) {
            try buf.append('/');
        } else if (std.mem.indexOfScalar(u8, reserved_chars, char)) |reserved| {
            try buf.appendSlice(&reserved_escapes[reserved]);
        } else {
            try buf.append(char);
        }
    }

    // On windows, we need to lowercase the drive name.
    if (builtin.os.tag == .windows) {
        if (buf.items.len > prefix.len + 1 and
            std.ascii.isAlpha(buf.items[prefix.len]) and
            std.mem.startsWith(u8, buf.items[prefix.len + 1 ..], "%3A"))
        {
            buf.items[prefix.len] = std.ascii.toLower(buf.items[prefix.len]);
        }
    }

    return buf.toOwnedSlice();
}

pub fn getName(self: Self) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, self.slice(), '/')) |pos| {
        return self.slice()[pos + 1 ..];
    } else {
        return self.slice();
    }
}

pub fn contains(self: Self, path: Self) bool {
    var current = path;
    while (current.parent()) |p| {
        if (std.mem.eql(u8, self.slice(), p.slice())) {
            return true;
        }
        current = p;
    }
    return false;
}
