/// https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize
const std = @import("std");
const types = @import("./types.zig");
const SignatureHelpOptions = @import("./signature_help.zig").SignatureHelpOptions;
const Default = types.Default;
const Exists = types.Exists;
const string = types.string;
const MaybeStringArray = types.MaybeStringArray;

pub const ClientCapabilities = struct {
    workspace: ?struct {
        workspaceFolders: Default(bool, false),
    },
    textDocument: ?struct {
        semanticTokens: Exists,
        hover: ?struct {
            contentFormat: MaybeStringArray,
        },
        completion: ?struct {
            completionItem: ?struct {
                snippetSupport: Default(bool, false),
                documentationFormat: MaybeStringArray,
            },
        },
    },
    offsetEncoding: MaybeStringArray,
};

pub const WorkspaceFolder = struct {
    uri: string,
    name: string,
};

pub const InitializeParams = struct {
    processId: ?i64,
    clientInfo: ?struct {
        name: string,
        version: ?string,
    },
    locale: ?string,
    rootPath: ?string,
    rootUri: ?string,
    capabilities: ClientCapabilities,
    trace: ?string,
    workspaceFolders: ?[]const WorkspaceFolder,
};

pub const SemanticTokensProvider = struct {
    full: bool,
    range: bool,
    legend: struct {
        tokenTypes: []const string,
        tokenModifiers: []const string,
    },
};

// Only includes options we set in our initialize result.
pub const ServerCapabilities = struct {
    signatureHelpProvider: ?SignatureHelpOptions = null,
    textDocumentSync: ?enum(u32) {
        None = 0,
        Full = 1,
        Incremental = 2,

        pub fn jsonStringify(value: @This(), options: std.json.StringifyOptions, out_stream: anytype) !void {
            try std.json.stringify(@enumToInt(value), options, out_stream);
        }
    } = null,
    renameProvider: bool = false,
    completionProvider: ?struct {
        resolveProvider: bool,
        triggerCharacters: []const string,
    } = null,
    documentHighlightProvider: bool = false,
    hoverProvider: bool = false,
    codeActionProvider: bool = false,
    codeLensProvider: ?struct {
        resolveProvider: ?bool,
    } = null,
    declarationProvider: bool = false,
    definitionProvider: bool = false,
    typeDefinitionProvider: bool = false,
    implementationProvider: bool = false,
    referencesProvider: bool = false,
    documentSymbolProvider: bool = false,
    colorProvider: bool = false,
    documentFormattingProvider: bool = false,
    documentRangeFormattingProvider: bool = false,
    foldingRangeProvider: bool = false,
    selectionRangeProvider: bool = false,
    workspaceSymbolProvider: bool = false,
    rangeProvider: bool = false,
    documentProvider: bool = false,
    workspace: ?struct {
        workspaceFolders: ?struct {
            supported: bool,
            changeNotifications: bool,
        },
    } = null,
    semanticTokensProvider: ?SemanticTokensProvider = null,
};

pub const InitializeResult = struct {
    offsetEncoding: string,
    capabilities: ServerCapabilities,
    serverInfo: struct {
        name: string,
        version: ?string = null,
    },
};
