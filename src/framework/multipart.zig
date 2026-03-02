const std = @import("std");

pub const Part = struct {
    name: []const u8,
    filename: ?[]const u8,
    content_type: []const u8,
    data: []const u8,
};

pub const MultipartError = error{
    InvalidBoundary,
    MalformedPart,
    OutOfMemory,
};

/// Extract boundary string from Content-Type header value.
/// Input: "multipart/form-data; boundary=----WebKitFormBoundary..."
/// Output: "----WebKitFormBoundary..."
pub fn extractBoundary(content_type: []const u8) ?[]const u8 {
    const needle = "boundary=";
    const idx = std.mem.indexOf(u8, content_type, needle) orelse return null;
    var boundary = content_type[idx + needle.len ..];

    // Strip quotes if present
    if (boundary.len >= 2 and boundary[0] == '"') {
        boundary = boundary[1..];
        if (std.mem.indexOfScalar(u8, boundary, '"')) |end| {
            boundary = boundary[0..end];
        }
    }

    // Trim trailing whitespace/semicolons
    boundary = std.mem.trimEnd(u8, boundary, " \t;\r\n");
    if (boundary.len == 0) return null;
    return boundary;
}

/// Parse multipart/form-data body into parts.
pub fn parse(
    allocator: std.mem.Allocator,
    body: []const u8,
    boundary: []const u8,
) MultipartError![]Part {
    var parts: std.ArrayList(Part) = .empty;
    errdefer parts.deinit(allocator);

    // Build delimiter: "\r\n--" + boundary
    var delim_buf: [512]u8 = undefined;
    const delim = std.fmt.bufPrint(&delim_buf, "\r\n--{s}", .{boundary}) catch return error.InvalidBoundary;

    // Build first delimiter: "--" + boundary
    var first_delim_buf: [512]u8 = undefined;
    const first_delim = std.fmt.bufPrint(&first_delim_buf, "--{s}", .{boundary}) catch return error.InvalidBoundary;

    // Find first boundary
    var pos: usize = 0;
    if (std.mem.startsWith(u8, body, first_delim)) {
        pos = first_delim.len;
    } else if (std.mem.indexOf(u8, body, first_delim)) |idx| {
        pos = idx + first_delim.len;
    } else {
        return error.MalformedPart;
    }

    while (pos < body.len) {
        // Check for closing boundary "--"
        if (pos + 2 <= body.len and std.mem.eql(u8, body[pos .. pos + 2], "--")) {
            break;
        }

        // Skip \r\n after boundary
        if (pos + 2 <= body.len and std.mem.eql(u8, body[pos .. pos + 2], "\r\n")) {
            pos += 2;
        }

        // Find end of headers (double \r\n)
        const remaining = body[pos..];
        const headers_end = std.mem.indexOf(u8, remaining, "\r\n\r\n") orelse return error.MalformedPart;
        const headers_slice = remaining[0..headers_end];
        pos = pos + headers_end + 4; // skip past \r\n\r\n

        // Find next boundary
        const data_remaining = body[pos..];
        const next_boundary = std.mem.indexOf(u8, data_remaining, delim);
        const data_end = if (next_boundary) |nb| nb else data_remaining.len;
        const data = data_remaining[0..data_end];

        // Parse headers for Content-Disposition and Content-Type
        var name: []const u8 = "";
        var filename: ?[]const u8 = null;
        var part_content_type: []const u8 = "application/octet-stream";

        var header_iter = std.mem.splitSequence(u8, headers_slice, "\r\n");
        while (header_iter.next()) |header_line| {
            if (header_line.len == 0) continue;

            // Split on first ':'
            if (std.mem.indexOfScalar(u8, header_line, ':')) |colon_idx| {
                const hdr_name = header_line[0..colon_idx];
                const hdr_value = std.mem.trim(u8, header_line[colon_idx + 1 ..], " \t");

                if (std.ascii.eqlIgnoreCase(hdr_name, "content-disposition")) {
                    name = extractParam(hdr_value, "name") orelse "";
                    filename = extractParam(hdr_value, "filename");
                } else if (std.ascii.eqlIgnoreCase(hdr_name, "content-type")) {
                    part_content_type = hdr_value;
                }
            }
        }

        parts.append(allocator, .{
            .name = name,
            .filename = filename,
            .content_type = part_content_type,
            .data = data,
        }) catch return error.OutOfMemory;

        if (next_boundary) |nb| {
            pos = pos + nb + delim.len;
        } else {
            break;
        }
    }

    return parts.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

/// Extract a parameter value from a header value string.
/// e.g., extractParam("form-data; name=\"file\"; filename=\"test.txt\"", "name")
/// returns "file"
fn extractParam(header_value: []const u8, param_name: []const u8) ?[]const u8 {
    // Look for: param_name="value"
    var search_buf: [64]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "{s}=\"", .{param_name}) catch return null;

    if (std.mem.indexOf(u8, header_value, search)) |start| {
        const val_start = start + search.len;
        if (val_start < header_value.len) {
            if (std.mem.indexOfScalarPos(u8, header_value, val_start, '"')) |end| {
                return header_value[val_start..end];
            }
        }
    }

    // Try without quotes: param_name=value
    const search_nq = std.fmt.bufPrint(&search_buf, "{s}=", .{param_name}) catch return null;
    if (std.mem.indexOf(u8, header_value, search_nq)) |start| {
        const val_start = start + search_nq.len;
        if (val_start < header_value.len and header_value[val_start] != '"') {
            const rest = header_value[val_start..];
            const end = std.mem.indexOfAny(u8, rest, "; \t\r\n") orelse rest.len;
            return rest[0..end];
        }
    }

    return null;
}

test "extractBoundary" {
    const ct = "multipart/form-data; boundary=----WebKitFormBoundaryABC123";
    const boundary = extractBoundary(ct);
    try std.testing.expect(boundary != null);
    try std.testing.expectEqualStrings("----WebKitFormBoundaryABC123", boundary.?);
}

test "extractParam" {
    const value = "form-data; name=\"file\"; filename=\"test.txt\"";
    const name = extractParam(value, "name");
    try std.testing.expect(name != null);
    try std.testing.expectEqualStrings("file", name.?);

    const fname = extractParam(value, "filename");
    try std.testing.expect(fname != null);
    try std.testing.expectEqualStrings("test.txt", fname.?);
}
