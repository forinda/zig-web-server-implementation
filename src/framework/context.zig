const std = @import("std");
const http = std.http;
const Io = std.Io;
const StatusCode = @import("utils/status.zig").StatusCode;
const multipart = @import("utils/multipart.zig");
const gzipCompress = @import("utils/compression.zig").gzipCompress;
const findHeaderValue = @import("utils/headers.zig").findHeaderValue;

pub const MAX_PARAMS = 8;

/// Extracted route parameters (e.g., :id → "42").
pub const Params = struct {
    keys: [MAX_PARAMS][]const u8 = undefined,
    values: [MAX_PARAMS][]const u8 = undefined,
    len: usize = 0,

    pub fn get(self: *const Params, name: []const u8) ?[]const u8 {
        for (0..self.len) |i| {
            if (std.mem.eql(u8, self.keys[i], name)) {
                return self.values[i];
            }
        }
        return null;
    }

    pub fn add(self: *Params, key: []const u8, value: []const u8) void {
        if (self.len < MAX_PARAMS) {
            self.keys[self.len] = key;
            self.values[self.len] = value;
            self.len += 1;
        }
    }

    /// Copy param values into allocator-owned memory so they survive head invalidation.
    pub fn copyValues(self: *Params, allocator: std.mem.Allocator) !void {
        for (0..self.len) |i| {
            self.values[i] = try allocator.dupe(u8, self.values[i]);
        }
    }
};

/// Context passed to every handler and middleware — combines request, response, params, and app state.
/// Middleware calls ctx.next() to proceed through the chain.
pub const Context = struct {
    request: *http.Server.Request,
    allocator: std.mem.Allocator,
    io: Io,
    params: Params,
    app_context_ptr: ?*anyopaque,
    response_status: StatusCode,
    body_cache: ?[]u8,
    responded: bool,

    // Cache content-type before head invalidation
    content_type_buf: [256]u8,
    content_type_len: usize,

    // Cache accept-encoding before head invalidation
    _accept_encoding_buf: [128]u8,
    _accept_encoding_len: usize,

    // Compression flag — set by compression middleware
    _compress_response: bool,

    // Multer — parsed multipart parts, set by multer middleware
    _multer_parts: ?[]const multipart.Part,

    // Middleware chain state — function pointers inlined to avoid dependency loop
    _chain_middlewares: []const *const fn (ctx: *Context) anyerror!void,
    _chain_handler: *const fn (ctx: *Context) anyerror!void,
    _chain_index: usize,

    pub fn init(
        request: *http.Server.Request,
        allocator: std.mem.Allocator,
        io: Io,
        params: Params,
        app_ctx: ?*anyopaque,
        middlewares: []const *const fn (ctx: *Context) anyerror!void,
        handler: *const fn (ctx: *Context) anyerror!void,
    ) Context {
        var ctx: Context = .{
            .request = request,
            .allocator = allocator,
            .io = io,
            .params = params,
            .app_context_ptr = app_ctx,
            .response_status = StatusCode.ok,
            .body_cache = null,
            .responded = false,
            .content_type_buf = undefined,
            .content_type_len = 0,
            ._accept_encoding_buf = undefined,
            ._accept_encoding_len = 0,
            ._compress_response = false,
            ._multer_parts = null,
            ._chain_middlewares = middlewares,
            ._chain_handler = handler,
            ._chain_index = 0,
        };

        // Cache content-type string before it can be invalidated
        if (request.head.content_type) |ct| {
            const len = @min(ct.len, ctx.content_type_buf.len);
            @memcpy(ctx.content_type_buf[0..len], ct[0..len]);
            ctx.content_type_len = len;
        }

        // Cache accept-encoding from raw head buffer before body read invalidates it
        if (findHeaderValue(request.head_buffer, "accept-encoding")) |ae| {
            const len = @min(ae.len, ctx._accept_encoding_buf.len);
            @memcpy(ctx._accept_encoding_buf[0..len], ae[0..len]);
            ctx._accept_encoding_len = len;
        }

        return ctx;
    }

    pub fn deinit(self: *Context) void {
        if (self.body_cache) |cached| {
            self.allocator.free(cached);
            self.body_cache = null;
        }
        if (self._multer_parts) |parts| {
            self.allocator.free(parts);
            self._multer_parts = null;
        }
        // Free copied param values
        for (0..self.params.len) |i| {
            self.allocator.free(self.params.values[i]);
        }
    }

    // ---- Middleware chain ----

    /// Proceed to the next middleware or final handler in the chain.
    /// Middleware should call this to pass control forward.
    pub fn next(self: *Context) !void {
        if (self._chain_index < self._chain_middlewares.len) {
            const mw = self._chain_middlewares[self._chain_index];
            self._chain_index += 1;
            return mw(self);
        }
        return self._chain_handler(self);
    }

    // ---- Request helpers ----

    /// Get a route parameter by name (e.g., ctx.param("id")).
    pub fn param(self: *const Context, name: []const u8) ?[]const u8 {
        return self.params.get(name);
    }

    /// Get the cached content-type header value.
    pub fn getContentType(self: *const Context) ?[]const u8 {
        if (self.content_type_len == 0) return null;
        return self.content_type_buf[0..self.content_type_len];
    }

    /// Get the cached accept-encoding header value.
    pub fn getAcceptEncoding(self: *const Context) ?[]const u8 {
        if (self._accept_encoding_len == 0) return null;
        return self._accept_encoding_buf[0..self._accept_encoding_len];
    }

    /// Get parsed multipart parts (set by multer middleware).
    pub fn getParts(self: *const Context) ?[]const multipart.Part {
        return self._multer_parts;
    }

    /// Read and cache the raw request body.
    /// Uses readerExpectContinue to handle Expect: 100-continue (sent by curl for multipart).
    pub fn body(self: *Context) ![]u8 {
        if (self.body_cache) |cached| return cached;

        const content_length = self.request.head.content_length orelse return error.MissingContentLength;
        if (content_length > 50 * 1024 * 1024) return error.PayloadTooLarge;

        var buf: [8192]u8 = undefined;
        // Use readerExpectContinue to handle both regular and Expect: 100-continue requests.
        // This sends "100 Continue" if needed, then reads the body.
        const body_reader = try self.request.readerExpectContinue(&buf);
        const data = try body_reader.readAlloc(self.allocator, @intCast(content_length));
        self.body_cache = data;
        return data;
    }

    /// Parse the request body as JSON into the given type.
    pub fn json(self: *Context, comptime T: type) !std.json.Parsed(T) {
        const raw = try self.body();
        return std.json.parseFromSlice(T, self.allocator, raw, .{
            .ignore_unknown_fields = true,
        });
    }

    // ---- Response helpers ----

    /// Set the response status (chainable).
    pub fn setStatus(self: *Context, s: StatusCode) *Context {
        self.response_status = s;
        return self;
    }

    /// Send a JSON-serialized response (with optional gzip compression).
    pub fn sendJson(self: *Context, value: anytype) !void {
        const json_body = try std.json.Stringify.valueAlloc(self.allocator, value, .{});
        defer self.allocator.free(json_body);
        try self.respondMaybeCompressed(json_body, "application/json");
    }

    /// Send a raw string response (with optional gzip compression).
    pub fn send(self: *Context, content: []const u8) !void {
        try self.respondMaybeCompressed(content, "text/plain");
    }

    /// Send a pre-built JSON string response (with optional gzip compression).
    pub fn sendRawJson(self: *Context, json_str: []const u8) !void {
        try self.respondMaybeCompressed(json_str, "application/json");
    }

    /// Send a JSON error response with the given status and message.
    pub fn sendError(self: *Context, status: StatusCode, msg: []const u8) !void {
        var err_buf: [512]u8 = undefined;
        const error_body = StatusCode.errorBodyMsg(&err_buf, msg);
        try self.request.respond(error_body, .{
            .keep_alive = false,
            .status = status.code,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        });
        self.responded = true;
    }

    /// Send a file download response.
    pub fn sendFile(self: *Context, data: []const u8, filename: []const u8, content_type: []const u8) !void {
        var disp_buf: [512]u8 = undefined;
        const disposition = std.fmt.bufPrint(&disp_buf, "attachment; filename=\"{s}\"", .{filename}) catch "attachment";

        try self.request.respond(data, .{
            .keep_alive = false,
            .status = self.response_status.code,
            .extra_headers = &.{
                .{ .name = "content-type", .value = content_type },
                .{ .name = "content-disposition", .value = disposition },
            },
        });
        self.responded = true;
    }

    // ---- App state ----

    /// Get the typed application context (e.g., *Storage).
    pub fn appContext(self: *Context, comptime T: type) *T {
        return @ptrCast(@alignCast(self.app_context_ptr.?));
    }

    // ---- Internal: compression ----

    /// Respond with optional gzip compression. If _compress_response is set and body
    /// is large enough (>= 860 bytes), compresses with gzip. Otherwise sends as-is.
    fn respondMaybeCompressed(self: *Context, body_data: []const u8, content_type: []const u8) !void {
        if (self._compress_response and body_data.len >= 860) {
            const compressed = gzipCompress(self.allocator, body_data) catch {
                // Fallback to uncompressed on compression error
                try self.request.respond(body_data, .{
                    .keep_alive = false,
                    .status = self.response_status.code,
                    .extra_headers = &.{
                        .{ .name = "content-type", .value = content_type },
                    },
                });
                self.responded = true;
                return;
            };
            defer self.allocator.free(compressed);
            try self.request.respond(compressed, .{
                .keep_alive = false,
                .status = self.response_status.code,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = content_type },
                    .{ .name = "content-encoding", .value = "gzip" },
                    .{ .name = "vary", .value = "Accept-Encoding" },
                },
            });
        } else {
            try self.request.respond(body_data, .{
                .keep_alive = false,
                .status = self.response_status.code,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = content_type },
                },
            });
        }
        self.responded = true;
    }
};

/// Handler function type — alias for the function pointer used by handlers and middleware.
pub const HandlerFn = *const fn (ctx: *Context) anyerror!void;

/// Middleware function type — same as HandlerFn. Call ctx.next() to proceed.
pub const MiddlewareFn = *const fn (ctx: *Context) anyerror!void;

// ---- Tests ----

test "Params.get and add" {
    var p: Params = .{};
    p.add("id", "42");
    p.add("name", "hello");

    try std.testing.expectEqualStrings("42", p.get("id").?);
    try std.testing.expectEqualStrings("hello", p.get("name").?);
    try std.testing.expect(p.get("missing") == null);
}
