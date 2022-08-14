//! https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_publishDiagnostics
const std = @import("std");
const types = @import("./types.zig");
// const reqeusts = @import("./requests.zig");
const string = []const u8;

// // request
// pub const DocumentDiagnosticParams = struct {
//     textDocument: reqeusts.TextDocumentIdentifier,
//     identifier: ?string,
//     previousResultId: ?string,
// };

// // response
// export interface FullDocumentDiagnosticReport {
// 	/**
// 	 * A full document diagnostic report.
// 	 */
// 	kind: DocumentDiagnosticReportKind.Full;

// 	/**
// 	 * An optional result id. If provided it will
// 	 * be sent on the next diagnostic request for the
// 	 * same document.
// 	 */
// 	resultId?: string;

// 	/**
// 	 * The actual items.
// 	 */
// 	items: Diagnostic[];
// }

// notification
pub const PublishDiagnosticsParams = struct {
    uri: string,
    diagnostics: []Diagnostic,
};

pub const Diagnostic = struct {
    range: types.Range,
    severity: ?DiagnosticSeverity,
    code: ?string,
    source: ?string,
    message: string,
};

pub const DiagnosticSeverity = enum(i64) {
    Error = 1,
    Warning = 2,
    Information = 3,
    Hint = 4,

    pub fn jsonStringify(value: DiagnosticSeverity, options: std.json.StringifyOptions, out_stream: anytype) !void {
        try std.json.stringify(@enumToInt(value), options, out_stream);
    }
};
