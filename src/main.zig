const std = @import("std");
const Stdio = @import("./Stdio.zig");
const logger = std.log.scoped(.main);

var transport: Stdio = undefined;

var keep_running = true;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // After shutdown, pipe output to stderr
    if (!keep_running) {
        std.debug.print("[{s}-{s}] " ++ format ++ "\n", .{ @tagName(message_level), @tagName(scope) } ++ args);
        return;
    }

    const allocator = std.heap.page_allocator;
    const message = std.fmt.allocPrint(allocator, "{s}> " ++ format, .{@tagName(scope)} ++ args) catch {
        std.debug.print("Failed to allocPrint message.\n", .{});
        return;
    };
    defer allocator.free(message);

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
            w.emitNumber(switch (message_level) {
                .debug => 4,
                .info => 3,
                .warn => 2,
                .err => 1,
            }) catch unreachable;

            w.objectField("message") catch unreachable;
            w.emitString(message) catch unreachable;
        }
    }

    transport.send(buffer.items);
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(!gpa.deinit());

    transport = Stdio.init(allocator);
    logger.info("######## [YAZLS] ########", .{});
}
