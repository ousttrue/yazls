const std = @import("std");
const root = @import("root");
const Dispatcher = @import("./Dispatcher.zig");
const Stdio = @import("./Stdio.zig");
const JsonRpcError = @import("./jsonrpc_error.zig").JsonRpcError;
const logger = std.log.scoped(.jsonrpc);

fn getId(tree: std.json.ValueTree) ?i64 {
    if (tree.root.Object.get("id")) |child| {
        switch (child) {
            .Integer => |int| return int,
            else => {},
        }
    }
    return null;
}

fn getMethod(tree: std.json.ValueTree) ?[]const u8 {
    if (tree.root.Object.get("method")) |child| {
        switch (child) {
            .String => |str| return str,
            else => {},
        }
    }
    return null;
}

fn getParams(tree: std.json.ValueTree) ?std.json.Value {
    return tree.root.Object.get("params");
}

pub fn readloop(allocator: std.mem.Allocator, transport: *Stdio, dispatcher: *Dispatcher) void {
    // This JSON parser is passed to processJsonRpc and reset.
    var json_parser = std.json.Parser.init(allocator, false);
    defer json_parser.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);

    while (root.keep_running) {
        if (transport.readNext()) |content| {
            defer {
                arena.deinit();
                arena.state = .{};
            }

            // parse
            json_parser.reset();
            var tree = json_parser.parse(content) catch |err| {
                logger.err("{s}", .{@errorName(err)});
                // transport.sendToJson(lsp.Response.createInvalidRequest(null));
                continue;
            };
            defer tree.deinit();

            // request: id, method, ?params
            // reponse: id, ?result, ?error
            // notify: method, ?params
            if (getId(tree)) |id| {
                if (getMethod(tree)) |method| {
                    // request
                    if (dispatcher.dispatchRequest(&arena, id, method, getParams(tree))) |res| {
                        transport.sendRpcBody(res);
                    } else |err| {
                        transport.sendErrorResponse(arena.allocator(), id, err, null);
                    }
                } else {
                    // response
                    @panic("jsonrpc response is not implemented(not send request)");
                }
            } else {
                if (getMethod(tree)) |method| {
                    // notify
                    dispatcher.dispatchNotify(&arena, method, getParams(tree)) catch |err| {
                        transport.sendErrorResponse(arena.allocator(), null, err, null);
                    };
                } else {
                    // invalid
                    transport.sendErrorResponse(arena.allocator(), null, JsonRpcError.ParseError, null);
                }
            }

            // dequeue and send notifications
            // for (queue.items) |notification| {
            //     transport.sendToJson(notification);
            // }
            // queue.resize(0) catch unreachable;
        } else |err| {
            logger.err("{s}", .{@errorName(err)});
            root.keep_running = false;
            break;
        }
    }
}
