const std = @import("std");
const Ast = std.zig.Ast;
const logger = std.log.scoped(.AstToken);

fn findTokenIndex(tree: *const Ast, byte_position: u32) ?u32 {
    const token_start = tree.tokens.items(.start);
    for (token_start) |start, i| {
        if (start == byte_position) {
            return @intCast(u32, i);
        } else if (start > byte_position) {
            if (i == 0) {
                return null;
            }
            const index = @intCast(u32, i - 1);
            const prev_text = tree.tokenSlice(index);
            const prev_start = token_start[index];
            if (prev_start + prev_text.len <= byte_position) {
                return null;
            }
            return index;
        }
    }
    return null;
}

const Self = @This();

tree: *const Ast,
index: u32,

pub fn init(tree: *const Ast, index: usize) Self {
    std.debug.assert(index < tree.tokens.len);
    return Self{
        .tree = tree,
        .index = @intCast(u32, index),
    };
}

pub fn debugPrint(self: Self) void {
    logger.debug("{}: {s}", .{self.getTag(), self.getText()});
}

pub fn fromBytePosition(tree: *const Ast, byte_position: usize) ?Self {
    return if (findTokenIndex(tree, @intCast(u32, byte_position))) |index|
        init(tree, index)
    else
        null;
}

pub fn getNext(self: Self) Self {
    return init(self.tree, self.index + 1);
}

pub fn getPrev(self: Self) ?Self {
    if (self.index == 0) return null;
    return init(self.tree, self.index - 1);
}

pub fn allocPrint(self: Self, allocator: std.mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}: {s}", .{ @tagName(self.getTag()), self.getText() });
}

pub fn getText(self: Self) []const u8 {
    return self.tree.tokenSlice(self.index);
}

pub fn getTag(self: Self) std.zig.Token.Tag {
    const token_tag = self.tree.tokens.items(.tag);
    return token_tag[self.index];
}

pub fn getStart(self: Self) u32 {
    const token_start = self.tree.tokens.items(.start);
    return token_start[self.index];
}

pub fn getLoc(self: Self) std.zig.Token.Loc {
    const start = self.getStart();
    const text = self.getText();
    return .{ .start = start, .end = start + text.len };
}

test "tokenizer" {
    const source =
        \\pub fn main() !void {
        \\    
        \\}
    ;
    var tokenizer = std.zig.Tokenizer.init(source);
    const token = tokenizer.next();
    try std.testing.expectEqual(token.loc, .{ .start = 0, .end = 3 });
}

test {
    const source =
        \\pub fn main() !void {
        \\    
        \\}
    ;

    const allocator = std.testing.allocator;

    var tree = try std.zig.parse(allocator, source);
    defer tree.deinit(allocator);

    const token = fromBytePosition(&tree, 1).?;
    try std.testing.expect(token.index == 0);
    try std.testing.expectEqualSlices(u8, token.getText(), "pub");
    try std.testing.expectEqual(token.getTag(), .keyword_pub);
    try std.testing.expectEqual(token.getLoc(), .{ .start = 0, .end = 3 });

    try std.testing.expect(fromBytePosition(&tree, 3) == null);

    // std.debug.print("\n{}\n", .{token.getTag()});
}
