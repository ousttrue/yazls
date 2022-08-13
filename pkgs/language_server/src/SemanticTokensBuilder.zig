const std = @import("std");
const astutil = @import("astutil");
const semantic_tokens = @import("./semantic_tokens.zig");
const SemanticTokenType = semantic_tokens.SemanticTokenType;
const SemanticTokenModifiers = semantic_tokens.SemanticTokenModifiers;
const Document = astutil.Document;
const AstNodeIterator = astutil.AstNodeIterator;
const logger = std.log.scoped(.SemanticTokens);
const Self = @This();

pub const SemanticToken = struct {
    start: usize,
    end: usize,
    token_type: SemanticTokenType,
    token_modifiers: SemanticTokenModifiers,
};

array: std.ArrayList(SemanticToken),
document: *Document,

fn init(allocator: std.mem.Allocator, document: *Document) Self {
    return Self{
        .array = std.ArrayList(SemanticToken).init(allocator),
        .document = document,
    };
}

fn push(self: *Self, token_idx: u32, token: std.zig.Token) !void {
    switch (token.tag) {
        .eof => unreachable,
        // string literal
        .string_literal, .multiline_string_literal_line, .char_literal => {
            try self.push_semantic_token(token.loc, .string, .{});
        },
        // number literal
        .integer_literal, .float_literal => {
            try self.push_semantic_token(token.loc, .number, .{});
        },
        // identifier
        .identifier => {
            try self.push_identifier(token_idx, token.loc);
        },
        // @builtin
        .builtin => {
            try self.push_semantic_token(token.loc, .function, .{
                .defaultLibrary = true,
            });
        },
        // invalid
        .invalid, .invalid_periodasterisks => {},
        // operator
        .bang, .pipe, .pipe_pipe, .pipe_equal, .equal, .equal_equal, .equal_angle_bracket_right, .bang_equal, .l_paren, .r_paren, .semicolon, .percent, .percent_equal, .l_brace, .r_brace, .l_bracket, .r_bracket, .period, .period_asterisk, .ellipsis2, .ellipsis3, .caret, .caret_equal, .plus, .plus_plus, .plus_equal, .plus_percent, .plus_percent_equal, .plus_pipe, .plus_pipe_equal, .minus, .minus_equal, .minus_percent, .minus_percent_equal, .minus_pipe, .minus_pipe_equal, .asterisk, .asterisk_equal, .asterisk_asterisk, .asterisk_percent, .asterisk_percent_equal, .asterisk_pipe, .asterisk_pipe_equal, .arrow, .colon, .slash, .slash_equal, .comma, .ampersand, .ampersand_equal, .question_mark, .angle_bracket_left, .angle_bracket_left_equal, .angle_bracket_angle_bracket_left, .angle_bracket_angle_bracket_left_equal, .angle_bracket_angle_bracket_left_pipe, .angle_bracket_angle_bracket_left_pipe_equal, .angle_bracket_right, .angle_bracket_right_equal, .angle_bracket_angle_bracket_right, .angle_bracket_angle_bracket_right_equal, .tilde => {
            try self.push_semantic_token(token.loc, .operator, .{});
        },
        // document
        .doc_comment, .container_doc_comment => {
            try self.push_semantic_token(token.loc, .comment, .{ .documentation = true });
        },
        // keywoard
        .keyword_addrspace, .keyword_align, .keyword_allowzero, .keyword_and, .keyword_anyframe, .keyword_anytype, .keyword_asm, .keyword_async, .keyword_await, .keyword_break, .keyword_callconv, .keyword_catch, .keyword_comptime, .keyword_const, .keyword_continue, .keyword_defer, .keyword_else, .keyword_enum, .keyword_errdefer, .keyword_error, .keyword_export, .keyword_extern, .keyword_fn, .keyword_for, .keyword_if, .keyword_inline, .keyword_noalias, .keyword_noinline, .keyword_nosuspend, .keyword_opaque, .keyword_or, .keyword_orelse, .keyword_packed, .keyword_pub, .keyword_resume, .keyword_return, .keyword_linksection, .keyword_struct, .keyword_suspend, .keyword_switch, .keyword_test, .keyword_threadlocal, .keyword_try, .keyword_union, .keyword_unreachable, .keyword_usingnamespace, .keyword_var, .keyword_volatile, .keyword_while => {
            try self.push_semantic_token(token.loc, .keyword, .{});
        },
    }
}

fn is_operator(node_tag: std.zig.Ast.Node.Tag) bool {
    return switch (node_tag) {
        .@"errdefer",
        .@"defer",
        .@"catch",
        // .field_access,
        .unwrap_optional,
        .equal_equal,
        .bang_equal,
        .less_than,
        .greater_than,
        .less_or_equal,
        .greater_or_equal,
        .assign_mul,
        .assign_div,
        .assign_mod,
        .assign_add,
        .assign_sub,
        .assign_shl,
        .assign_shl_sat,
        .assign_shr,
        .assign_bit_and,
        .assign_bit_xor,
        .assign_bit_or,
        .assign_mul_wrap,
        .assign_add_wrap,
        .assign_sub_wrap,
        .assign_mul_sat,
        .assign_add_sat,
        .assign_sub_sat,
        .assign,
        .merge_error_sets,
        .mul,
        .div,
        .mod,
        .array_mult,
        .mul_wrap,
        .mul_sat,
        .add,
        .sub,
        .array_cat,
        .add_wrap,
        .sub_wrap,
        .add_sat,
        .sub_sat,
        .shl,
        .shl_sat,
        .shr,
        .bit_and,
        .bit_xor,
        .bit_or,
        .@"orelse",
        .bool_and,
        .bool_or,
        .bool_not,
        .negation,
        .bit_not,
        .negation_wrap,
        .address_of,
        .@"try",
        => true,
        else => false,
    };
}

fn is_variable(node_tag: std.zig.Ast.Node.Tag) bool {
    if (is_operator(node_tag)) {
        return true;
    }
    return switch (node_tag) {
        .switch_comma => true,
        else => false,
    };
}

fn is_literal(name: []const u8) bool {
    for ([_][]const u8{ "true", "false", "null", "undefined" }) |value| {
        if (std.mem.eql(u8, name, value)) {
            return true;
        }
    }
    return false;
}

fn is_type(name: []const u8) bool {
    for ([_][]const u8{ "void", "type", "bool", "f16", "f32", "f64", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "usize" }) |value| {
        if (std.mem.eql(u8, name, value)) {
            return true;
        }
    }
    return false;
}

fn push_identifier(self: *Self, token_idx: u32, loc: std.zig.Token.Loc) !void {
    const ast_context = self.document.ast_context;
    const idx = ast_context.tokens_node[token_idx];
    const tag = ast_context.tree.nodes.items(.tag);
    const node_tag = tag[idx];
    const name = ast_context.getText(loc);
    var buffer: [2]u32 = undefined;
    const children = AstNodeIterator.NodeChildren.init(ast_context.tree, idx, &buffer);
    switch (children) {
        .var_decl => {
            if (std.ascii.isUpper(name[0])) {
                try self.push_semantic_token(loc, .type, .{});
            } else {
                try self.push_semantic_token(loc, .variable, .{});
            }
        },
        .array_type => {},
        .ptr_type => {
            try self.push_semantic_token(loc, .type, .{});
        },
        .slice => {},
        .array_init => {},
        .struct_init => {
            try self.push_semantic_token(loc, .property, .{});
        },
        .call => {},
        .@"switch" => {},
        .switch_case => |switch_case| {
            if (token_idx == switch_case.payload_token) {
                try self.push_semantic_token(loc, .variable, .{});
            }
        },
        .@"while" => {
            try self.push_semantic_token(loc, .variable, .{});
        },
        .@"if" => {
            try self.push_semantic_token(loc, .variable, .{});
        },
        .fn_proto => |fn_proto| {
            if (token_idx == fn_proto.name_token) {
                try self.push_semantic_token(loc, .function, .{});
            } else {
                try self.push_semantic_token(loc, .parameter, .{});
            }
        },
        .container_decl => {},
        .container_field => {
            try self.push_semantic_token(loc, .property, .{});
        },
        .@"asm" => {},
        else => {
            switch (node_tag) {
                .enum_literal, .error_value => {
                    try self.push_semantic_token(loc, .enumMember, .{});
                },
                .identifier, .field_access => {
                    if (is_literal(name)) {
                        try self.push_semantic_token(loc, .number, .{});
                    } else if (std.ascii.isUpper(name[0])) {
                        try self.push_semantic_token(loc, .type, .{});
                    } else if (is_type(name)) {
                        try self.push_semantic_token(loc, .type, .{});
                    } else {
                        try self.push_semantic_token(loc, .variable, .{});
                    }
                },
                .@"break", .block_semicolon => {
                    try self.push_semantic_token(loc, .event, .{});
                },
                else => {
                    // try self.push_semantic_token(loc, .variable, .{});
                },
            }
        },
    }
}

fn push_semantic_token(
    self: *Self,
    loc: std.zig.Token.Loc,
    token_type: SemanticTokenType,
    modifiers: SemanticTokenModifiers,
) !void {
    if (self.array.items.len > 0) {
        std.debug.assert(loc.start > self.array.items[self.array.items.len - 1].start);
    }
    try self.array.append(SemanticToken{
        .start = loc.start,
        .end = loc.end,
        .token_type = token_type,
        .token_modifiers = modifiers,
    });
}

fn pushLineCommments(self: *Self, text:[]const u8, start: usize, end: usize) !void
{
    var j = start;
    var in_comment: ?usize = null;
    while (j < end) {
        if (in_comment) |comment_start| {
            if (text[j] == '\n') {
                // logger.debug("push comment: {} = {}", .{comment_start, j});
                try self.push_semantic_token(.{ .start = @intCast(u32, comment_start), .end = @intCast(u32, j) }, .comment, .{});
                in_comment = null;
            }
        } else {
            if (std.ascii.isSpace(text[j])) {
                // skip
            } else if (text[j] == '/' and text[j + 1] == '/') {
                // line comment to eol
                in_comment = j;
            } else {
                // next token
                break;
            }
        }

        const len = try std.unicode.utf8CodepointSequenceLength(text[j]);
        j += len;
    }
}

pub fn writeAllSemanticTokens(arena: *std.heap.ArenaAllocator, document: *Document) ![]SemanticToken {
    const allocator = arena.allocator();

    var text = document.utf8_buffer.text;
    var self = init(allocator, document);
    var last: usize = 0;
    for (document.ast_context.tokens) |token, i| {
        try self.pushLineCommments(text, last, token.loc.start);

        try self.push(@intCast(u32, i), token);
        last = token.loc.end + 1;
    }
    try self.pushLineCommments(text, last, text.len);

    return self.array.items;
}
