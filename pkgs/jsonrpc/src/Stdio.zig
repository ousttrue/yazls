const std = @import("std");
const JsonRpcError = @import("./jsonrpc_error.zig").JsonRpcError;
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

pub fn sendLogMessage(self: *Self, allocator: std.mem.Allocator, message_level: i32, message: []const u8) void {
    // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#messageType
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var w = std.json.writeStream(buffer.writer(), 10);
    {
        w.beginObject() catch unreachable;
        defer w.endObject() catch unreachable;

        w.objectField("method") catch unreachable;
        w.emitString("window/logMessage") catch unreachable;

        w.objectField("params") catch unreachable;
        {
            w.beginObject() catch unreachable;
            defer w.endObject() catch unreachable;

            w.objectField("type") catch unreachable;
            w.emitNumber(message_level) catch unreachable;

            w.objectField("message") catch unreachable;
            w.emitString(message) catch unreachable;
        }
    }

    self.sendRpcBody(buffer.items);
}

pub fn sendErrorResponse(
    self: *Self,
    allocator: std.mem.Allocator,
    id: ?i64,
    err: JsonRpcError,
    message: ?[]const u8,
) void {
    // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#responseMessage
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    var w = std.json.writeStream(buffer.writer(), 10);
    {
        w.beginObject() catch unreachable;
        defer w.endObject() catch unreachable;

        if (id) |value| {
            w.objectField("id") catch unreachable;
            w.emitNumber(value) catch unreachable;
        }

        w.objectField("error") catch unreachable;
        {
            w.beginObject() catch unreachable;
            defer w.endObject() catch unreachable;

            w.objectField("code") catch unreachable;
            w.emitNumber(switch (err) {
                JsonRpcError.ParseError => @as(i64, -32700),
                JsonRpcError.InvalidRequest => @as(i64, -32600),
                JsonRpcError.MethodNotFound => @as(i64, -32601),
                JsonRpcError.InvalidParams => @as(i64, -32602),
                JsonRpcError.InternalError => @as(i64, -32603),
            }) catch unreachable;

            w.objectField("message") catch unreachable;
            if (message) |text| {
                w.emitString(text) catch unreachable;
            } else {
                w.emitString(@errorName(err)) catch unreachable;
            }
        }
    }

    self.sendRpcBody(buffer.items);
}

pub fn sendRpcBody(self: *Self, value: []const u8) void {
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
