const std = @import("std");
const Stdio = @import("./Stdio.zig");
const Dispatcher = @import("./Dispatcher.zig");
const jsonrpc = @import("./jsonrpc.zig");
const logger = std.log.scoped(.main);

var transport: Stdio = undefined;

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

    transport.sendLogMessage(allocator, switch (message_level) {
        .debug => 4,
        .info => 3,
        .warn => 2,
        .err => 1,
    }, message);
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(!gpa.deinit());

    transport = Stdio.init(allocator);
    logger.info("######## [YAZLS] ########", .{});

    var dispatcher = Dispatcher.init(allocator);
    defer dispatcher.deinit();

    jsonrpc.readloop(allocator, &transport, &dispatcher);
}
