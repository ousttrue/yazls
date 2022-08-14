const std = @import("std");
const types = @import("./types.zig");
const string = []const u8;

// request
pub const CompletionParams = struct {
    textDocument: types.TextDocumentIdentifier,
    position: types.Position,
    context: CompletionContext,
};

pub const CompletionContext = struct {
    triggerKind: CompletionTriggerKind,
    triggerCharacter: ?[]const u8,
};

pub const CompletionTriggerKind = enum(u8) {
    Invoked = 1,
    TriggerCharacter = 2,
    TriggerForIncompleteCompletions = 3,
};

// response
pub const CompletionList = struct {
    isIncomplete: bool,
    items: []const CompletionItem,
};

pub const CompletionItem = struct {
    label: string,
    kind: CompletionItemKind = .Text,
    textEdit: ?types.TextEdit = null,
    filterText: ?string = null,
    insertText: string = "",
    insertTextFormat: ?types.InsertTextFormat = .PlainText,
    detail: ?string = null,
    documentation: ?types.MarkupContent = null,
};

const CompletionItemKind = enum(i64) {
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
    Struct = 22,
    Event = 23,
    Operator = 24,
    TypeParameter = 25,

    pub fn jsonStringify(value: @This(), options: std.json.StringifyOptions, out_stream: anytype) !void {
        try std.json.stringify(@enumToInt(value), options, out_stream);
    }
};
