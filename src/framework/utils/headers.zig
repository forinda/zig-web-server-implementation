const std = @import("std");

/// Search raw HTTP head buffer for a header value by name (case-insensitive).
/// The head_buffer contains the raw HTTP request header bytes before body read invalidates them.
pub fn findHeaderValue(head_buffer: []const u8, header_name: []const u8) ?[]const u8 {
    var iter = std.mem.splitSequence(u8, head_buffer, "\r\n");
    _ = iter.next(); // skip request line
    while (iter.next()) |line| {
        if (line.len == 0) break;
        if (std.mem.indexOfScalar(u8, line, ':')) |colon| {
            const name = line[0..colon];
            if (std.ascii.eqlIgnoreCase(name, header_name)) {
                return std.mem.trim(u8, line[colon + 1 ..], " \t");
            }
        }
    }
    return null;
}

// ---- Tests ----

test "findHeaderValue" {
    const head = "GET /api/tasks HTTP/1.1\r\nHost: localhost\r\nAccept-Encoding: gzip, deflate\r\nContent-Type: application/json\r\n\r\n";
    const ae = findHeaderValue(head, "accept-encoding");
    try std.testing.expect(ae != null);
    try std.testing.expectEqualStrings("gzip, deflate", ae.?);

    const ct = findHeaderValue(head, "content-type");
    try std.testing.expect(ct != null);
    try std.testing.expectEqualStrings("application/json", ct.?);

    try std.testing.expect(findHeaderValue(head, "x-missing") == null);
}

test "findHeaderValue case insensitive" {
    const head = "GET / HTTP/1.1\r\nX-Custom-Header: my-value\r\n\r\n";
    try std.testing.expectEqualStrings("my-value", findHeaderValue(head, "x-custom-header").?);
    try std.testing.expectEqualStrings("my-value", findHeaderValue(head, "X-CUSTOM-HEADER").?);
}
