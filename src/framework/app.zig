const std = @import("std");
const http = std.http;
const Io = std.Io;
const net = std.Io.net;
const Router = @import("router.zig").Router;
const context_mod = @import("context.zig");
const HandlerFn = context_mod.HandlerFn;
const MiddlewareFn = context_mod.MiddlewareFn;
const server_mod = @import("server.zig");

/// Express.js-like application struct.
/// Generic over AppState so handlers get typed access via ctx.appContext(T).
pub fn App(comptime AppState: type) type {
    return struct {
        const Self = @This();

        router: Router,
        middlewares: std.ArrayList(MiddlewareFn),
        allocator: std.mem.Allocator,
        io: Io,
        state: *AppState,

        pub fn init(allocator: std.mem.Allocator, io: Io, state: *AppState) Self {
            return .{
                .router = Router.init(allocator),
                .middlewares = .empty,
                .allocator = allocator,
                .io = io,
                .state = state,
            };
        }

        pub fn deinit(self: *Self) void {
            self.router.deinit();
            self.middlewares.deinit(self.allocator);
        }

        // ---- Route Registration ----

        pub fn get(self: *Self, pattern: []const u8, handler: HandlerFn) !void {
            try self.router.addRoute(.GET, pattern, handler);
        }

        pub fn post(self: *Self, pattern: []const u8, handler: HandlerFn) !void {
            try self.router.addRoute(.POST, pattern, handler);
        }

        pub fn put(self: *Self, pattern: []const u8, handler: HandlerFn) !void {
            try self.router.addRoute(.PUT, pattern, handler);
        }

        pub fn delete(self: *Self, pattern: []const u8, handler: HandlerFn) !void {
            try self.router.addRoute(.DELETE, pattern, handler);
        }

        pub fn options(self: *Self, pattern: []const u8, handler: HandlerFn) !void {
            try self.router.addRoute(.OPTIONS, pattern, handler);
        }

        pub fn route(self: *Self, method: http.Method, pattern: []const u8, handler: HandlerFn) !void {
            try self.router.addRoute(method, pattern, handler);
        }

        // ---- Middleware ----

        pub fn use(self: *Self, mw: MiddlewareFn) !void {
            try self.middlewares.append(self.allocator, mw);
        }

        // ---- Server ----

        /// Start listening on the given port. Blocks forever, accepting connections.
        pub fn listen(self: *Self, port: u16, app_name: []const u8) !void {
            const address: net.IpAddress = .{ .ip4 = net.Ip4Address.loopback(port) };

            var tcp_server = address.listen(self.io, .{ .reuse_address = true }) catch |err| {
                std.debug.print("Failed to listen on port {d}: {s}\n", .{ port, @errorName(err) });
                return err;
            };
            defer tcp_server.deinit(self.io);

            std.debug.print(
                \\
                \\===========================================
                \\  {s} running on port {d}
                \\  http://127.0.0.1:{d}
                \\===========================================
                \\
                \\
            , .{ app_name, port, port });

            std.debug.print("  {d} routes registered\n\n", .{self.router.routes.items.len});

            const mw_slice = self.middlewares.items;

            while (true) {
                const stream = tcp_server.accept(self.io) catch |err| {
                    std.debug.print("Accept error: {s}\n", .{@errorName(err)});
                    continue;
                };
                defer {
                    var copy = stream;
                    copy.close(self.io);
                }

                server_mod.handleConnection(
                    stream,
                    self.io,
                    self.allocator,
                    &self.router,
                    mw_slice,
                    @ptrCast(self.state),
                );
            }
        }
    };
}
