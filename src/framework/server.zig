const std = @import("std");
const http = std.http;
const net = std.Io.net;
const Io = std.Io;
const context_mod = @import("context.zig");
const Context = context_mod.Context;
const Params = context_mod.Params;
const HandlerFn = context_mod.HandlerFn;
const MiddlewareFn = context_mod.MiddlewareFn;
const Router = @import("router.zig").Router;
const StatusCode = @import("status.zig").StatusCode;

/// Handle a single TCP connection — processes HTTP requests in a keep-alive loop.
pub fn handleConnection(
    stream: net.Stream,
    io: Io,
    gpa: std.mem.Allocator,
    router: *const Router,
    middlewares: []const MiddlewareFn,
    app_ctx: ?*anyopaque,
) void {
    var send_buffer: [8192]u8 = undefined;
    var recv_buffer: [8192]u8 = undefined;
    var connection_reader = stream.reader(io, &recv_buffer);
    var connection_writer = stream.writer(io, &send_buffer);
    var server: http.Server = .init(&connection_reader.interface, &connection_writer.interface);

    while (true) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                std.debug.print("Error receiving request: {s}\n", .{@errorName(err)});
                return;
            },
        };

        handleRequest(&request, gpa, io, router, middlewares, app_ctx) catch |err| {
            std.debug.print("Handler error: {s}\n", .{@errorName(err)});
            // Try to send a 500 error
            var err_buf: [64]u8 = undefined;
            const err_body = StatusCode.internal_server_error.errorBody(&err_buf);
            request.respond(err_body, .{
                .status = .internal_server_error,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "application/json" },
                },
            }) catch return;
        };
    }
}

fn handleRequest(
    request: *http.Server.Request,
    gpa: std.mem.Allocator,
    io: Io,
    router: *const Router,
    middlewares: []const MiddlewareFn,
    app_ctx: ?*anyopaque,
) !void {
    const target = request.head.target;
    const method = request.head.method;

    // Strip query string
    const path = if (std.mem.indexOfScalar(u8, target, '?')) |i| target[0..i] else target;

    // Match route
    const match_result = router.match(method, path) orelse {
        // No matching route — send 404
        var buf: [64]u8 = undefined;
        const not_found_body = StatusCode.not_found.errorBody(&buf);
        try request.respond(not_found_body, .{
            .status = .not_found,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        });
        return;
    };

    // Copy param values into allocator-owned memory before head invalidation
    var params = match_result.params;
    try params.copyValues(gpa);

    // Build Context with middleware chain state
    var ctx = Context.init(request, gpa, io, params, app_ctx, middlewares, match_result.handler);
    defer ctx.deinit();

    // Start the middleware chain (which ends by calling the handler)
    try ctx.next();
}
