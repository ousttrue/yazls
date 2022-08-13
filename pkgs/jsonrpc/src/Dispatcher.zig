const std = @import("std");
const TypeErasure = @import("./type_erasure.zig").TypeErasure;
const JsonRpcError = @import("./jsonrpc_error.zig").JsonRpcError;
const logger = std.log.scoped(.Dispatcher);

const RequestProto = fn (ptr: *anyopaque, arena: *std.heap.ArenaAllocator, id: i64, params: ?std.json.Value) anyerror![]const u8;
const RequestFunctor = struct {
    ptr: *anyopaque,
    proto: RequestProto,
    pub fn call(self: RequestFunctor, arena: *std.heap.ArenaAllocator, id: i64, params: ?std.json.Value) anyerror![]const u8 {
        return self.proto(self.ptr, arena, id, params);
    }
};

const NotifyProto = fn (ptr: *anyopaque, arena: *std.heap.ArenaAllocator, prams: ?std.json.Value) anyerror!void;
const NotifyFunctor = struct {
    ptr: *anyopaque,
    proto: NotifyProto,
    pub fn call(self: NotifyFunctor, arena: *std.heap.ArenaAllocator, params: ?std.json.Value) anyerror!void {
        return self.proto(self.ptr, arena, params);
    }
};

const Self = @This();

request_map: std.StringHashMap(RequestFunctor),
notify_map: std.StringHashMap(NotifyFunctor),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .request_map = std.StringHashMap(RequestFunctor).init(allocator),
        .notify_map = std.StringHashMap(NotifyFunctor).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.request_map.deinit();
    self.notify_map.deinit();
}

pub fn registerRequest(
    self: *Self,
    ptr: anytype,
    comptime method: []const u8,
) void {
    const PT = @TypeOf(ptr);
    const T = @typeInfo(PT).Pointer.child;
    self.request_map.put(method, RequestFunctor{
        .ptr = ptr,
        .proto = TypeErasure(T, method).call,
    }) catch @panic("put");
}

pub fn registerNotification(
    self: *Self,
    ptr: anytype,
    comptime method: []const u8,
) void {
    const PT = @TypeOf(ptr);
    const T = @typeInfo(PT).Pointer.child;
    self.notify_map.put(method, NotifyFunctor{
        .ptr = ptr,
        .proto = TypeErasure(T, method).call,
    }) catch @panic("put");
}

pub fn dispatchRequest(
    self: Self,
    arena: *std.heap.ArenaAllocator,
    id: i64,
    method: []const u8,
    params: ?std.json.Value,
) JsonRpcError![]const u8 {
    if (self.request_map.get(method)) |functor| {
        const start_time = std.time.milliTimestamp();
        if (functor.call(arena, id, params)) |res| {
            const end_time = std.time.milliTimestamp();
            logger.info("({}){s} => {}ms", .{ id, method, end_time - start_time });
            return res;
        } else |err| {
            logger.err("({}){s} => {s}", .{ id, method, @errorName(err) });
            return JsonRpcError.InternalError;
        }
    } else {
        // no method
        logger.err("({}){s} => unknown request", .{ id, method });
        return JsonRpcError.MethodNotFound;
    }
}

pub fn dispatchNotify(
    self: *Self,
    arena: *std.heap.ArenaAllocator,
    method: []const u8,
    params: ?std.json.Value,
) JsonRpcError!void {
    if (self.notify_map.get(method)) |functor| {
        const start_time = std.time.milliTimestamp();
        if (functor.call(arena, params)) {
            const end_time = std.time.milliTimestamp();
            logger.info("{s} => {}ms", .{ method, end_time - start_time });
        } else |err| {
            logger.err("{s} => {s}", .{ method, @errorName(err) });
            return JsonRpcError.InternalError;
        }
    } else {
        logger.err("{s} => unknown notify", .{method});
        return JsonRpcError.MethodNotFound;
    }
}
