const std = @import("std");
const Ast = std.zig.Ast;
const FixedPath = @import("./FixedPath.zig");
const AstNodeIterator = @import("./AstNodeIterator.zig");
const AstNode = @import("./AstNode.zig");
const AstToken = @import("./AstToken.zig");
const Self = @This();

fn getAllTokensAlloc(allocator: std.mem.Allocator, source: [:0]const u8) []std.zig.Token {
    var tokens = std.ArrayList(std.zig.Token).init(allocator);
    defer tokens.deinit();

    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) {
            break;
        }
        tokens.append(token) catch unreachable;
    }

    return tokens.toOwnedSlice();
}

pub fn traverse(context: *Self, parent_idx: Ast.Node.Index, idx: Ast.Node.Index) void {
    const tree = context.tree;

    context.nodes_parent[idx] = parent_idx;
    const token_start = tree.firstToken(idx);
    const token_last = tree.lastToken(idx);
    var token_idx = token_start;
    while (token_idx <= token_last) : (token_idx += 1) {
        context.tokens_node[token_idx] = idx;
    }

    var it = AstNodeIterator.init(idx);
    _ = async it.iterateAsync(context.tree);
    while (it.value) |child| : (it.next()) {
        if (child >= context.nodes_parent.len) {
            const tags = tree.nodes.items(.tag);
            const node_tag = tags[idx];
            std.log.err("{}: {}>=nodes_parent.len", .{ node_tag, child });
            unreachable;
        }
        traverse(context, idx, child);
    }
}

pub const AstPath = struct {};

allocator: std.mem.Allocator,
path: FixedPath,
tree: std.zig.Ast,
nodes_parent: []u32,
tokens: []std.zig.Token,
tokens_node: []u32,

pub fn new(allocator: std.mem.Allocator, path: FixedPath, text: [:0]const u8) !*Self {
    const tree = try std.zig.parse(allocator, text);
    var self = allocator.create(Self) catch unreachable;
    self.* = Self{
        .path = path,
        .allocator = allocator,
        .tree = tree,
        .nodes_parent = allocator.alloc(u32, tree.nodes.len) catch unreachable,
        .tokens = getAllTokensAlloc(allocator, tree.source),
        .tokens_node = allocator.alloc(u32, tree.tokens.len) catch unreachable,
    };
    for (self.nodes_parent) |*x| {
        x.* = 0;
    }
    for (self.tokens_node) |*x| {
        x.* = 0;
    }

    // root
    for (tree.rootDecls()) |decl| {
        // top level
        traverse(self, 0, decl);
    }

    return self;
}

pub fn delete(self: *Self) void {
    self.allocator.free(self.tokens_node);
    self.allocator.free(self.nodes_parent);
    self.allocator.free(self.tokens);
    self.tree.deinit(self.allocator);
    self.allocator.destroy(self);
}

pub fn getText(self: Self, loc: std.zig.Token.Loc) []const u8 {
    return self.tree.source[loc.start..loc.end];
}

pub fn getTokens(self: Self, start: usize, last: usize) []const std.zig.Token {
    var end = last;
    if (end < self.tokens.len) {
        end += 1;
    }
    return self.tokens[start..end];
}

pub fn getNodeTokens(self: Self, idx: u32) []const std.zig.Token {
    return self.getTokens(self.tree.firstToken(idx), self.tree.lastToken(idx));
}

pub fn getParentNode(self: Self, idx: u32) ?u32 {
    if (idx == 0) {
        return null;
    }
    return self.nodes_parent[idx];
}

pub fn getNodeTag(self: Self, idx: u32) std.zig.Ast.Node.Tag {
    const tag = self.tree.nodes.items(.tag);
    return tag[idx];
}

pub fn getMainToken(self: Self, idx: u32) std.zig.Token {
    const main_token = self.tree.nodes.items(.main_token);
    const token_idx = main_token[idx];
    return self.tokens[token_idx];
}

pub fn getAstPath(self: Self, token_idx: usize) ?AstPath {
    const tag = self.tree.nodes.items(.tag);
    var idx = self.tokens_node[token_idx];
    while (self.getParentNode(idx)) |parent| : (idx = parent) {
        std.debug.print(", {}[{s}]", .{ idx, @tagName(tag[idx]) });
    }
    std.debug.print("\n", .{});

    return null;
}

pub fn findAncestor(self: Self, idx: u32, target: u32) bool {
    var current = self.nodes_parent[idx];
    while (current != 0) : (current = self.nodes_parent[current]) {
        if (current == target) {
            return true;
        }
    }
    return false;
}

pub fn isInToken(pos: usize, token: std.zig.Token) bool {
    return pos >= token.loc.start and pos <= token.loc.end - 1;
}

pub const TokenWithIndex = struct { token: std.zig.Token, index: u32 };

pub fn tokenFromBytePos(self: Self, byte_pos: usize) ?TokenWithIndex {
    for (self.tokens) |token, i| {
        if (isInToken(byte_pos, token)) {
            return TokenWithIndex{ .token = token, .index = @intCast(u32, i) };
        }
    }
    return null;
}

pub fn prevTokenFromBytePos(self: Self, byte_pos: usize) ?TokenWithIndex {
    for (self.tokens) |token, i| {
        if (byte_pos <= token.loc.start) {
            if (i == 0) {
                return null;
            } else {
                // if(std.)
                //        ^
                return TokenWithIndex{ .token = self.tokens[i - 1], .index = @intCast(u32, i - 1) };
            }
        }
    }
    return null;
}

pub fn getRootIdentifier(self: Self, node_idx: u32) u32 {
    var tag = self.tree.nodes.items(.tag);
    if (tag[node_idx] != .field_access) {
        return node_idx;
    }

    var current = node_idx;
    while (true) {
        var it = AstNodeIterator.init(current);
        _ = async it.iterateAsync(self.tree);
        const child = it.value.?;
        var child_tag = tag[child];
        switch (child_tag) {
            .identifier => {
                return child;
            },
            .field_access, .call_one, .call => {
                current = child;
                continue;
            },
            else => {
                return child;
            },
        }
    }
    unreachable;
}

fn isSymbolChar(char: u8) bool {
    return std.ascii.isAlNum(char) or char == '_';
}

/// Collects all imports we can find into a slice of import paths (without quotes).
pub fn collectImports(self: Self, import_arr: *std.ArrayList([]const u8)) !void {
    const tags = self.tree.tokens.items(.tag);

    var i: usize = 0;
    while (i < tags.len) : (i += 1) {
        if (tags[i] != .builtin)
            continue;
        const text = self.tree.tokenSlice(@intCast(u32, i));

        if (std.mem.eql(u8, text, "@import")) {
            if (i + 3 >= tags.len)
                break;
            if (tags[i + 1] != .l_paren)
                continue;
            if (tags[i + 2] != .string_literal)
                continue;
            if (tags[i + 3] != .r_paren)
                continue;

            const str = self.tree.tokenSlice(@intCast(u32, i + 2));
            try import_arr.append(str[1 .. str.len - 1]);
        }
    }
}
