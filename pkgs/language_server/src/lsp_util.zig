const std = @import("std");
const lsp = @import("language_server_protocol");
const astutil = @import("astutil");
const Document = astutil.Document;
const Line = astutil.Line;

pub fn getRange(doc: *Document, loc: std.zig.Token.Loc, encoding: Line.Encoding) !lsp.types.Range {
    var start_loc = try doc.utf8_buffer.getPositionFromBytePosition(loc.start, encoding);
    var end_loc = try doc.utf8_buffer.getPositionFromBytePosition(loc.end, encoding);
    var range = lsp.types.Range{
        .start = .{
            .line = @intCast(i64, start_loc.line),
            .character = @intCast(i64, start_loc.x),
        },
        .end = .{
            .line = @intCast(i64, end_loc.line),
            .character = @intCast(i64, end_loc.x),
        },
    };
    return range;
}
