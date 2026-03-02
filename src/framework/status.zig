const std = @import("std");
const http = std.http;

/// Reusable HTTP status code struct with semantic names and helper methods.
pub const StatusCode = struct {
    code: http.Status,
    message: []const u8,

    // ---- 2xx Success ----
    pub const ok: StatusCode = .{ .code = .ok, .message = "OK" };
    pub const created: StatusCode = .{ .code = .created, .message = "Created" };
    pub const accepted: StatusCode = .{ .code = .accepted, .message = "Accepted" };
    pub const no_content: StatusCode = .{ .code = .no_content, .message = "No Content" };

    // ---- 3xx Redirection ----
    pub const moved_permanently: StatusCode = .{ .code = .moved_permanently, .message = "Moved Permanently" };
    pub const found: StatusCode = .{ .code = .found, .message = "Found" };
    pub const not_modified: StatusCode = .{ .code = .not_modified, .message = "Not Modified" };
    pub const temporary_redirect: StatusCode = .{ .code = .temporary_redirect, .message = "Temporary Redirect" };

    // ---- 4xx Client Error ----
    pub const bad_request: StatusCode = .{ .code = .bad_request, .message = "Bad Request" };
    pub const unauthorized: StatusCode = .{ .code = .unauthorized, .message = "Unauthorized" };
    pub const forbidden: StatusCode = .{ .code = .forbidden, .message = "Forbidden" };
    pub const not_found: StatusCode = .{ .code = .not_found, .message = "Not Found" };
    pub const method_not_allowed: StatusCode = .{ .code = .method_not_allowed, .message = "Method Not Allowed" };
    pub const conflict: StatusCode = .{ .code = .conflict, .message = "Conflict" };
    pub const gone: StatusCode = .{ .code = .gone, .message = "Gone" };
    pub const payload_too_large: StatusCode = .{ .code = .payload_too_large, .message = "Payload Too Large" };
    pub const unsupported_media_type: StatusCode = .{ .code = .unsupported_media_type, .message = "Unsupported Media Type" };
    pub const unprocessable_entity: StatusCode = .{ .code = .unprocessable_entity, .message = "Unprocessable Entity" };
    pub const too_many_requests: StatusCode = .{ .code = .too_many_requests, .message = "Too Many Requests" };

    // ---- 5xx Server Error ----
    pub const internal_server_error: StatusCode = .{ .code = .internal_server_error, .message = "Internal Server Error" };
    pub const not_implemented: StatusCode = .{ .code = .not_implemented, .message = "Not Implemented" };
    pub const bad_gateway: StatusCode = .{ .code = .bad_gateway, .message = "Bad Gateway" };
    pub const service_unavailable: StatusCode = .{ .code = .service_unavailable, .message = "Service Unavailable" };
    pub const gateway_timeout: StatusCode = .{ .code = .gateway_timeout, .message = "Gateway Timeout" };

    /// Create a custom status code.
    pub fn custom(code: http.Status, message: []const u8) StatusCode {
        return .{ .code = code, .message = message };
    }

    /// Build a JSON error body: {"error":"<message>"}
    pub fn errorBody(self: StatusCode, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{{\"error\":\"{s}\"}}", .{self.message}) catch
            "{\"error\":\"Internal Server Error\"}";
    }

    /// Build a JSON error body with a custom message.
    pub fn errorBodyMsg(buf: []u8, msg: []const u8) []const u8 {
        return std.fmt.bufPrint(buf, "{{\"error\":\"{s}\"}}", .{msg}) catch
            "{\"error\":\"Internal Server Error\"}";
    }

    /// Get the numeric status code.
    pub fn numericCode(self: StatusCode) u10 {
        return @intFromEnum(self.code);
    }

    /// Check if this is a success status (2xx).
    pub fn isSuccess(self: StatusCode) bool {
        const n = self.numericCode();
        return n >= 200 and n < 300;
    }

    /// Check if this is a client error (4xx).
    pub fn isClientError(self: StatusCode) bool {
        const n = self.numericCode();
        return n >= 400 and n < 500;
    }

    /// Check if this is a server error (5xx).
    pub fn isServerError(self: StatusCode) bool {
        const n = self.numericCode();
        return n >= 500 and n < 600;
    }
};
