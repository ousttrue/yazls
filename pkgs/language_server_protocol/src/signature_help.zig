//! https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_signatureHelp
const types = @import("./types.zig");
const string = []const u8;

// server capabilities
pub const SignatureHelpOptions = struct {
    triggerCharacters: []const string,
    retriggerCharacters: []const string,
};

// request
pub const SignatureHelpParams = struct {
    textDocument: types.TextDocumentIdentifier,
    position: types.Position,
    context: ?SignatureHelpContext,
};

pub const SignatureHelpContext = struct {
    triggerKind: enum(u32) {
        invoked = 1,
        trigger_character = 2,
        content_change = 3,
    },
    triggerCharacter: ?[]const u8,
    isRetrigger: bool,
    activeSignatureHelp: ?SignatureHelp,
};

// response
pub const SignatureHelp = struct {
    signatures: ?[]const SignatureInformation,
    activeSignature: ?u32 = 0,
    activeParameter: ?u32 = null,
};

pub const SignatureInformation = struct {
    label: string,
    documentation: types.MarkupContent,
    parameters: ?[]const ParameterInformation = null,
    activeParameter: ?u32 = null,
};

pub const ParameterInformation = struct {
    label: string,
    documentation: types.MarkupContent,
};
