const std = @import("std");
const jsonrpc = @import("jsonrpc");
const ls = @import("language_server");
const logger = std.log.scoped(.main);

var transport: jsonrpc.Stdio = undefined;

pub var keep_running = true;

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

    transport.sendLogMessage(allocator, message_level, message);
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(!gpa.deinit());

    transport = jsonrpc.Stdio.init(allocator);
    logger.info("######## [YAZLS] ########", .{});

    var dispatcher = jsonrpc.Dispatcher.init(allocator);
    defer dispatcher.deinit();

    var zigenv = try ls.ZigEnv.init(allocator);

    var language_server = ls.LanguageServer.init(allocator, zigenv);
    dispatcher.registerRequest(&language_server, "initialize");
    dispatcher.registerNotification(&language_server, "initialized");
    dispatcher.registerRequest(&language_server, "shutdown");

    jsonrpc.readloop(allocator, &transport, &dispatcher);
}
