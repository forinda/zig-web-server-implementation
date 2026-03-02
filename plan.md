# Implementation Plan

## Phase 1: Express-like Framework Refactoring (Complete)

Refactored the monolithic web server into a layered architecture:

- **Framework layer** (`src/framework/`): Reusable App, Context, Router, utils (StatusCode, multipart, compression, headers)
- **App layer** (`src/app/`): Route definitions, handlers, models, storage
- **Koa-style middleware**: `ctx.next()` pattern — middleware and handlers share the same `HandlerFn` type
- **Resolved Zig type dependency loop**: Inlined function pointer types in Context struct fields, defined aliases after struct

### Key Technical Decisions
- `readerExpectContinue()` for body reading (handles curl's `Expect: 100-continue`)
- Content-Type cached in Context.init before head invalidation
- Unmanaged ArrayList (allocator per operation) for Zig 0.16 compatibility

## Phase 2: Framework Expansion (Current)

### Step 1: Middleware Subfolder ✓
- Moved logger and cors from `middleware.zig` to `middlewares/`
- Enhanced cors with `CorsOptions` comptime config
- Barrel re-export via `middlewares/middlewares.zig`

### Step 2: Compression Middleware ✓
- Gzip compression using `std.compress.flate.Compress.Huffman` (small memory footprint)
- Accept-Encoding parsed from raw `head_buffer` (not a standard parsed header in Zig)
- `_compress_response` flag on Context, checked in send methods
- 860-byte minimum threshold to skip tiny responses
- Transparent to handlers — just add `app.use(fw.middlewares.compression)`

### Step 3: Multer Middleware ✓
- Multipart form-data parsing middleware
- Parsed parts stored in `ctx._multer_parts`, accessed via `ctx.getParts()`
- Configurable: `multerWithConfig(.{ .max_file_size = 5 * 1024 * 1024 })`
- Non-multipart requests pass through without parsing

### Step 4: SQLite Adapter ✓
- Full C interop via `@cImport(@cInclude("sqlite3.h"))`
- Database, Statement, Row, QueryResult, Value types
- Opt-in: not auto-imported, build with `zig build -Dsqlite=true`
- Requires `libsqlite3-dev` system package

### Step 5: Utils Subfolder ✓
- Moved `status.zig` and `multipart.zig` to `utils/`
- Extracted `compression.zig` (gzipCompress) and `headers.zig` (findHeaderValue) from context.zig
- Barrel re-export via `utils/utils.zig`
- Updated all import paths across framework

### Step 6: Framework Tests ✓
- Inline tests in source files (Zig convention)
- Router: pattern parsing, matching, param extraction
- StatusCode: errorBody, numeric codes, category checks
- Multipart: full parse test, boundary extraction, edge cases
- Compression: gzip compress/decompress round-trip
- Headers: header lookup, case-insensitive matching
- Context: Params get/add

### Step 7: Documentation ✓
- `architecture.md` — full framework architecture overview
- `plan.md` — this implementation plan

### Step 8: Dev Mode (Hot Reload) ✓
- `dev.sh` shell script at project root
- Auto-detects inotifywait (event-driven) or falls back to polling (1s)
- Watches `src/` for `.zig` file changes
- On change: kills server, rebuilds, restarts
- Colored, timestamped output
- Signal-safe cleanup (Ctrl+C kills child server)
- `zig build dev` build step integration

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | /health | Health check |
| GET | /api/tasks | List all tasks |
| POST | /api/tasks | Create task |
| GET | /api/tasks/:id | Get task by ID |
| PUT | /api/tasks/:id | Update task |
| DELETE | /api/tasks/:id | Delete task |
| POST | /api/tasks/:id/attachments | Upload attachment |
| GET | /api/tasks/:id/attachments | List task attachments |
| GET | /api/attachments/:id/download | Download attachment |

## Verification

```bash
# Build
zig build

# Run tests
zig build test

# Start server
zig build run

# Test endpoints
curl -s http://localhost:8080/health
curl -s -X POST http://localhost:8080/api/tasks -H "Content-Type: application/json" -d '{"title":"Test","description":"desc"}'
curl -s http://localhost:8080/api/tasks

# Test compression
curl -s -H "Accept-Encoding: gzip" http://localhost:8080/api/tasks --output - | file -

# Build with SQLite (requires libsqlite3-dev)
zig build -Dsqlite=true
```
