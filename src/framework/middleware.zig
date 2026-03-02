const std = @import("std");
const context_mod = @import("context.zig");
const Context = context_mod.Context;
pub const HandlerFn = context_mod.HandlerFn;
pub const MiddlewareFn = context_mod.MiddlewareFn;

// ---- Built-in Middleware ----

/// Logs each request method and path to stderr.
pub fn logger(ctx: *Context) anyerror!void {
    const method = @tagName(ctx.request.head.method);
    const target = ctx.request.head.target;
    std.debug.print("[{s}] {s}\n", .{ method, target });
    try ctx.next();
}

/// Adds CORS headers to allow cross-origin requests.
/// For preflight OPTIONS, responds immediately. For other requests, continues the chain.
pub fn cors(ctx: *Context) anyerror!void {
    if (ctx.request.head.method == .OPTIONS) {
        try ctx.request.respond("", .{
            .status = .no_content,
            .extra_headers = &.{
                .{ .name = "access-control-allow-origin", .value = "*" },
                .{ .name = "access-control-allow-methods", .value = "GET, POST, PUT, DELETE, OPTIONS" },
                .{ .name = "access-control-allow-headers", .value = "Content-Type, Authorization" },
                .{ .name = "access-control-max-age", .value = "86400" },
            },
        });
        ctx.responded = true;
        return;
    }

    try ctx.next();
}
