const std = @import("std");
const Context = @import("../context.zig").Context;

/// Logs each request method and path to stderr.
pub fn logger(ctx: *Context) anyerror!void {
    const method = @tagName(ctx.request.head.method);
    const target = ctx.request.head.target;
    std.debug.print("[{s}] {s}\n", .{ method, target });
    try ctx.next();
}
