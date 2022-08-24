const std = @import("std");
const AstContext = @import("./AstContext.zig");
const AstToken = @import("./AstToken.zig");
const AstNode = @import("./AstNode.zig");
const Utf8Buffer = @import("./Utf8Buffer.zig");

pub const AstIdentifierKind = enum {
    reference,
    var_decl,
    field_decl,
    if_payload,
    while_payload,
    switch_case_ppayload,
    function_param,
};

const Self = @This();

token: AstToken,
kind: AstIdentifierKind,

pub fn init(context: *const AstContext, token: AstToken) Self {
    const node = AstNode.fromTokenIndex(context, token.index);
    var buf: [2]u32 = undefined;
    switch (node.getChildren(&buf)) {
        .@"if" => {
            return Self{
                .token = token,
                .kind = .if_payload,
            };
        },
        else => {
            unreachable;
        },
    }
}

test {
    const source = @embedFile("test_source.zig");
    const allocator = std.testing.allocator;
    const text: [:0]const u8 = try allocator.dupeZ(u8, source);
    defer allocator.free(text);
    const line_heads = try Utf8Buffer.allocLineHeads(allocator, text);
    defer allocator.free(line_heads);
    const context = try AstContext.new(allocator, .{}, text, line_heads);
    defer context.delete();

    const value = context.getToken(9, 28).?;
    try std.testing.expectEqualStrings("value", value.getText());

    const id = init(context, value);
    try std.testing.expectEqual(AstIdentifierKind.if_payload, id.kind);
}
