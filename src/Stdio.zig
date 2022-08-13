const std = @import("std");
const Self = @This();

const CONTENT_LENGTH = "Content-Length: ";
const CONTENT_TYPE = "Content-Type: ";
const WRITER = std.io.BufferedWriter(4096, std.fs.File.Writer);

const Error = error{
    NoCR,
    UnknownHeader,
    NoContentLength,
};

reader: std.fs.File.Reader,
content_buffer: std.ArrayList(u8),
writer: WRITER,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .reader = std.io.getStdIn().reader(),
        .content_buffer = std.ArrayList(u8).init(allocator),
        .writer = std.io.bufferedWriter(std.io.getStdOut().writer()),
    };
}

pub fn deinit(self: Self) void {
    self.json_buffer.deinit();
}

pub fn send(self: *Self, value: []const u8) void {
    const stdout_stream = self.writer.writer();
    stdout_stream.print("Content-Length: {}\r\n\r\n", .{value.len}) catch @panic("send");
    stdout_stream.writeAll(value) catch @panic("send");
    self.writer.flush() catch @panic("send");
}

fn readUntil_CRLF(reader: std.fs.File.Reader, buffer: []u8) ![]const u8 {
    var pos: u32 = 0;
    while (true) : (pos += 1) {
        buffer[pos] = try reader.readByte();
        if (buffer[pos] == '\n') {
            break;
        }
    }
    if (pos > 0 and buffer[pos - 1] == '\r') {
        return buffer[0 .. pos - 1];
    }
    return Error.NoCR;
}

pub fn readNext(self: *Self) ![]const u8 {
    var content_length: usize = 0;
    var line_buffer: [128]u8 = undefined;
    while (true) {
        const line = try readUntil_CRLF(self.reader, &line_buffer);
        if (line.len == 0) {
            break;
        }
        if (std.mem.startsWith(u8, line, CONTENT_LENGTH)) {
            content_length = try std.fmt.parseInt(u32, line[CONTENT_LENGTH.len..], 10);
        } else if (std.mem.startsWith(u8, line, CONTENT_TYPE)) {} else {
            return Error.UnknownHeader;
        }
    }

    if (content_length == 0) {
        return Error.NoContentLength;
    }

    // read
    try self.content_buffer.resize(content_length);
    try self.reader.readNoEof(self.content_buffer.items);
    return self.content_buffer.items;
}
