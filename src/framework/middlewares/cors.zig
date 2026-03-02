const std = @import("std");
const Context = @import("../context.zig").Context;

/// CORS configuration options.
pub const CorsOptions = struct {
    /// Allowed origins. Use "*" for all.
    allow_origin: []const u8 = "*",
    /// Allowed HTTP methods.
    allow_methods: []const u8 = "GET, POST, PUT, DELETE, PATCH, OPTIONS",
    /// Allowed request headers.
    allow_headers: []const u8 = "Content-Type, Authorization, X-Requested-With",
    /// Max age for preflight cache (seconds).
    max_age: []const u8 = "86400",
    /// Whether to allow credentials.
    allow_credentials: bool = false,
};

/// Default CORS middleware — allows all origins.
pub fn cors(ctx: *Context) anyerror!void {
    return corsHandler(.{}, ctx);
}

/// Create a CORS middleware with custom options.
pub fn withOptions(comptime opts: CorsOptions) *const fn (*Context) anyerror!void {
    return struct {
        fn handler(ctx: *Context) anyerror!void {
            return corsHandler(opts, ctx);
        }
    }.handler;
}

fn corsHandler(comptime opts: CorsOptions, ctx: *Context) anyerror!void {
    if (ctx.request.head.method == .OPTIONS) {
        // Preflight — respond immediately with CORS headers
        const credentials_value = if (opts.allow_credentials) "true" else "false";
        try ctx.request.respond("", .{
            .status = .no_content,
            .extra_headers = &.{
                .{ .name = "access-control-allow-origin", .value = opts.allow_origin },
                .{ .name = "access-control-allow-methods", .value = opts.allow_methods },
                .{ .name = "access-control-allow-headers", .value = opts.allow_headers },
                .{ .name = "access-control-max-age", .value = opts.max_age },
                .{ .name = "access-control-allow-credentials", .value = credentials_value },
            },
        });
        ctx.responded = true;
        return;
    }

    try ctx.next();
}
