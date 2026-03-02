const std = @import("std");
const Context = @import("../context.zig").Context;

/// Gzip compression middleware.
/// Checks the Accept-Encoding header for "gzip" support and enables
/// transparent compression on responses (applied in send methods).
/// Should be added early in the middleware chain.
pub fn compression(ctx: *Context) anyerror!void {
    if (ctx.getAcceptEncoding()) |encoding| {
        if (std.mem.indexOf(u8, encoding, "gzip") != null) {
            ctx._compress_response = true;
        }
    }
    try ctx.next();
}
