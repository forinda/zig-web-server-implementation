# Architecture

## Overview

An Express.js-inspired HTTP web framework written in Zig 0.16.0-dev. The framework provides route registration, a Koa-style middleware chain, rich request/response context, optional gzip compression, multipart form-data parsing, and a SQLite database adapter.

## Folder Structure

```
src/
  main.zig                          Entry point — creates Storage, sets up app, listens

  framework/                        Reusable web framework library
    framework.zig                   Public barrel re-exports (App, Context, StatusCode, etc.)
    app.zig                         App(comptime AppState) — route registration + server loop
    context.zig                     Context — request/response, params, middleware chain, compression
    router.zig                      Router — pattern matching with :param extraction
    server.zig                      TCP connection handler — HTTP keep-alive loop

    utils/                          Reusable helpers and utilities
      utils.zig                     Barrel re-export for all utilities
      status.zig                    StatusCode — semantic HTTP status codes with helpers
      multipart.zig                 Multipart/form-data parser
      compression.zig               Gzip compression function (std.compress.flate.Huffman)
      headers.zig                   Raw HTTP header parsing (findHeaderValue)

    middlewares/                    Built-in middleware
      middlewares.zig               Barrel re-export for all middleware
      logger.zig                    Request logging to stderr
      cors.zig                      CORS headers (configurable via CorsOptions)
      compression.zig               Gzip response compression middleware (transparent)
      multer.zig                    Multipart form-data parsing middleware

    adapters/                       Database & service adapters (opt-in)
      adapters.zig                  Barrel re-export
      sqlite.zig                    SQLite3 adapter via @cImport

  app/                              Application layer (uses the framework)
    app.zig                         Route definitions and middleware setup
    models.zig                      Data models (Task, TaskInput, Attachment)
    storage.zig                     In-memory storage with file I/O
    handlers/
      tasks.zig                     Task CRUD handlers
      attachments.zig               Attachment upload/download handlers
```

## Key Types

### App(comptime AppState)
Generic application struct. `AppState` is the type of the application context (e.g., `Storage`). Provides Express-like route registration methods (`get`, `post`, `put`, `delete`, `use`) and a blocking `listen(port)` method.

### Context
Central type passed to every handler and middleware. Contains:
- `request` — raw HTTP server request
- `allocator` — per-request allocator
- `params` — extracted route parameters (e.g., `:id` → `"42"`)
- `app_context_ptr` — typed access to app state via `ctx.appContext(T)`
- Response helpers: `sendJson`, `send`, `sendRawJson`, `sendError`, `sendFile`
- `body()` / `json(T)` — request body parsing
- `next()` — proceed through middleware chain
- `_compress_response` — flag set by compression middleware
- `_multer_parts` — parsed multipart parts from multer middleware

### Router
Route table with segment-based pattern matching. Supports literal segments and `:param` placeholders. Returns a `MatchResult` with the handler and extracted params.

### StatusCode
Semantic HTTP status codes with helpers: `errorBody()`, `errorBodyMsg()`, `isSuccess()`, `isClientError()`, `isServerError()`, `numericCode()`, `custom()`.

## Middleware Pattern

Middleware follows the Koa-style `ctx.next()` pattern. Both middleware and handlers share the same `HandlerFn` signature:

```zig
pub const HandlerFn = *const fn (ctx: *Context) anyerror!void;
```

Middleware calls `ctx.next()` to pass control to the next middleware or handler:

```zig
pub fn logger(ctx: *Context) anyerror!void {
    std.debug.print("[{s}] {s}\n", .{ @tagName(ctx.request.head.method), ctx.request.head.target });
    try ctx.next();
}
```

### Configurable Middleware

For middleware that accepts options, use `comptime` struct parameters with anonymous struct closures:

```zig
pub fn withOptions(comptime opts: CorsOptions) *const fn (*Context) anyerror!void {
    return struct {
        fn handler(ctx: *Context) anyerror!void {
            // use opts at comptime
            try ctx.next();
        }
    }.handler;
}
```

## Compression

The compression middleware (`middlewares.compression`) checks the `Accept-Encoding` request header for gzip support and sets a flag on the Context. The `sendJson`, `send`, and `sendRawJson` methods automatically compress the response when the flag is set and the body exceeds 860 bytes.

Compression uses Zig's built-in `std.compress.flate.Compress.Huffman` with the gzip container format for a small memory footprint.

## Adapter Pattern (SQLite)

Adapters are NOT auto-imported to avoid mandatory dependencies. Import explicitly:

```zig
const sqlite = @import("framework/adapters/sqlite.zig");
var db = try sqlite.Database.open(":memory:");
defer db.close();
try db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)");
```

Build with SQLite enabled: `zig build -Dsqlite=true`

Requires `libsqlite3-dev` system package.

## Request Lifecycle

1. TCP connection accepted by `App.listen()`
2. `server.handleConnection()` reads HTTP head in a keep-alive loop
3. `server.handleRequest()` strips query string, matches route via `Router.match()`
4. `Context.init()` caches headers (content-type, accept-encoding) and builds the middleware chain
5. `ctx.next()` starts the middleware chain → each middleware calls `ctx.next()` → final handler runs
6. Handler calls `ctx.sendJson()` / `ctx.send()` etc. → response sent (with optional gzip)
7. `Context.deinit()` frees body cache, multer parts, and copied params

## Testing

Tests are inline in source files (Zig convention). Run with:

```bash
zig build test
```

Test coverage:
- `router.zig` — pattern parsing, route matching, param extraction
- `utils/status.zig` — error body formatting, numeric codes, category checks
- `utils/multipart.zig` — boundary extraction, param extraction, full multipart parsing
- `utils/compression.zig` — gzip compress/decompress round-trip
- `utils/headers.zig` — header lookup, case-insensitive matching
- `context.zig` — Params get/add

## Development

### Hot Reload

Run the development server with automatic rebuild on file changes:

```bash
./dev.sh
```

Or via the build system:

```bash
zig build dev
```

The dev script watches `src/` for `.zig` file modifications. When a change is detected, it:
1. Kills the running server
2. Runs `zig build`
3. Starts the new binary

If `inotify-tools` is installed (`sudo apt install inotify-tools`), file changes are detected instantly via Linux inotify events. Otherwise, the script polls every 1 second using `find -newer`.
