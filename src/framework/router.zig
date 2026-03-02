const std = @import("std");
const http = std.http;
const context_mod = @import("context.zig");
const Params = context_mod.Params;
pub const HandlerFn = context_mod.HandlerFn;

pub const MAX_SEGMENTS = 16;

/// A segment of a route pattern — either a literal string or a :param placeholder.
pub const Segment = union(enum) {
    literal: []const u8,
    param: []const u8,
};

/// A registered route.
pub const Route = struct {
    method: http.Method,
    pattern: []const u8,
    segments: []const Segment,
    handler: HandlerFn,
};

/// Route table with pattern matching and parameter extraction.
pub const Router = struct {
    routes: std.ArrayList(Route),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Router {
        return .{
            .routes = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Router) void {
        for (self.routes.items) |route| {
            self.allocator.free(route.segments);
        }
        self.routes.deinit(self.allocator);
    }

    /// Register a route with a pattern like "/api/tasks/:id/attachments".
    pub fn addRoute(self: *Router, method: http.Method, pattern: []const u8, handler: HandlerFn) !void {
        const segments = try parsePattern(self.allocator, pattern);
        try self.routes.append(self.allocator, .{
            .method = method,
            .pattern = pattern,
            .segments = segments,
            .handler = handler,
        });
    }

    /// Find a matching route for the given method and path, extracting parameters.
    pub fn match(self: *const Router, method: http.Method, path: []const u8) ?MatchResult {
        for (self.routes.items) |route| {
            if (route.method != method) continue;
            var params: Params = .{};
            if (matchPattern(route.segments, path, &params)) {
                return .{ .handler = route.handler, .params = params };
            }
        }
        return null;
    }

    pub const MatchResult = struct {
        handler: HandlerFn,
        params: Params,
    };
};

/// Parse a route pattern into segments.
/// "/api/tasks/:id/attachments" → [literal("api"), literal("tasks"), param("id"), literal("attachments")]
fn parsePattern(allocator: std.mem.Allocator, pattern: []const u8) ![]const Segment {
    var segments_list: std.ArrayList(Segment) = .empty;
    errdefer segments_list.deinit(allocator);

    // Skip leading '/'
    const trimmed = if (pattern.len > 0 and pattern[0] == '/') pattern[1..] else pattern;
    if (trimmed.len == 0) {
        return try segments_list.toOwnedSlice(allocator);
    }

    var iter = std.mem.splitScalar(u8, trimmed, '/');
    while (iter.next()) |segment| {
        if (segment.len == 0) continue;
        if (segment[0] == ':') {
            try segments_list.append(allocator, .{ .param = segment[1..] });
        } else {
            try segments_list.append(allocator, .{ .literal = segment });
        }
    }

    return try segments_list.toOwnedSlice(allocator);
}

/// Match a path against parsed route segments, extracting params.
fn matchPattern(segments: []const Segment, path: []const u8, params: *Params) bool {
    const trimmed = if (path.len > 0 and path[0] == '/') path[1..] else path;

    var path_iter = std.mem.splitScalar(u8, trimmed, '/');
    var seg_idx: usize = 0;

    while (seg_idx < segments.len) : (seg_idx += 1) {
        const path_segment = path_iter.next() orelse return false;
        if (path_segment.len == 0) {
            seg_idx -|= 1;
            continue;
        }

        switch (segments[seg_idx]) {
            .literal => |lit| {
                if (!std.mem.eql(u8, path_segment, lit)) return false;
            },
            .param => |name| {
                params.add(name, path_segment);
            },
        }
    }

    // Ensure no leftover path segments
    while (path_iter.next()) |remaining| {
        if (remaining.len > 0) return false;
    }

    return true;
}

test "parsePattern and matchPattern" {
    const allocator = std.testing.allocator;

    const segments = try parsePattern(allocator, "/api/tasks/:id/attachments");
    defer allocator.free(segments);

    try std.testing.expectEqual(4, segments.len);
    try std.testing.expectEqualStrings("api", segments[0].literal);
    try std.testing.expectEqualStrings("tasks", segments[1].literal);
    try std.testing.expectEqualStrings("id", segments[2].param);
    try std.testing.expectEqualStrings("attachments", segments[3].literal);

    var params: Params = .{};
    try std.testing.expect(matchPattern(segments, "/api/tasks/42/attachments", &params));
    try std.testing.expectEqual(1, params.len);
    try std.testing.expectEqualStrings("42", params.get("id").?);

    var params2: Params = .{};
    try std.testing.expect(!matchPattern(segments, "/api/tasks/42", &params2));
}
