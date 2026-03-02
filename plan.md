# Zig Web Server with Multipart Support — Implementation Plan

## Context

Build a Zig web server from scratch using `std.http.Server` (Zig 0.16.0-dev) that provides REST endpoints for tasks and attachments. The server must handle `multipart/form-data` uploads since `std.http` has no built-in multipart parser. All data is stored in-memory with file uploads saved to disk.

## Project Structure

```
/home/forinda/Desktop/my-basic-app/
├── build.zig              # Build configuration
├── build.zig.zon          # Package metadata
├── src/
│   ├── main.zig           # Entry point: TCP accept loop
│   ├── server.zig         # HTTP connection handler (wraps std.http.Server)
│   ├── router.zig         # Path-based routing + method dispatch
│   ├── multipart.zig      # Custom multipart/form-data parser
│   ├── models.zig         # Task and Attachment structs
│   ├── storage.zig        # In-memory store + file I/O
│   ├── response.zig       # JSON/error/file response helpers
│   └── handlers/
│       ├── tasks.zig      # Task CRUD handlers
│       └── attachments.zig # Attachment upload/list/download handlers
└── uploads/               # Created at runtime for uploaded files
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/tasks` | List all tasks |
| POST | `/api/tasks` | Create task (JSON body) |
| GET | `/api/tasks/{id}` | Get single task |
| PUT | `/api/tasks/{id}` | Update task (JSON body) |
| DELETE | `/api/tasks/{id}` | Delete task |
| POST | `/api/tasks/{id}/attachments` | Upload file (multipart/form-data) |
| GET | `/api/tasks/{id}/attachments` | List attachments for task |
| GET | `/api/attachments/{id}/download` | Download attachment file |

## Implementation Steps

### Step 1: Scaffold project
- Create `build.zig` following the template at `/home/forinda/sdk/zig/lib/init/build.zig`
- Create `build.zig.zon` with project metadata
- Use `b.createModule` / `b.addExecutable` API (Zig 0.16 style)
- Include `run` and `test` build steps

### Step 2: `src/main.zig` — Entry point
- Use `pub fn main(init: std.process.Init) !void` signature (confirmed from `/home/forinda/sdk/zig/lib/init/src/main.zig`)
- Access `init.io`, `init.gpa`, `init.arena`
- Create TCP listener: `net.IpAddress.listen(address, io, .{ .reuse_address = true })`
- Accept loop: `tcp_server.accept(io)` returns `net.Stream`
- Pass each stream to `server.handleConnection()`
- Close stream after handling

### Step 3: `src/server.zig` — HTTP connection handler
- Follow exact pattern from `/home/forinda/sdk/zig/lib/std/Build/WebServer.zig` lines 250-293:
  ```
  var send_buffer: [8192]u8 = undefined;
  var recv_buffer: [8192]u8 = undefined;
  var connection_reader = stream.reader(io, &recv_buffer);
  var connection_writer = stream.writer(io, &send_buffer);
  var server: http.Server = .init(&connection_reader.interface, &connection_writer.interface);
  ```
- Loop: `server.receiveHead()` → `router.dispatch()` → handle errors with 500 response
- Handle `error.HttpConnectionClosing` to break the loop gracefully

### Step 4: `src/models.zig` — Data models
- `Task`: id (u64), title ([]const u8), description ([]const u8), completed (bool)
- `TaskInput`: title, description (default ""), completed (default false) — for JSON deserialization
- `Attachment`: id (u64), task_id (u64), filename ([]const u8), original_filename ([]const u8), content_type ([]const u8), size (u64)

### Step 5: `src/storage.zig` — In-memory store
- Uses `std.ArrayList(Task)` and `std.ArrayList(Attachment)` (unmanaged — pass allocator to each operation)
- Auto-incrementing IDs via `next_task_id` / `next_attachment_id` counters
- String ownership: `gpa.dupe(u8, slice)` for stored strings, `gpa.free()` on deletion
- File I/O: `Dir.cwd().writeFile(io, .{ .sub_path = path, .data = content })` for saving
- File read: `Dir.cwd().readFileAlloc(io, path, gpa, .limited(50 * 1024 * 1024))`
- Creates `uploads/` directory at init via `Dir.cwd().createDirPath(io, "uploads")`

### Step 6: `src/response.zig` — Response helpers
- `sendJson()`: serialize with `std.json.Stringify.valueAlloc()`, respond with `Content-Type: application/json`
- `sendJsonRaw()`: respond with pre-built JSON string
- `sendError()`: build `{"error":"message"}` via `std.fmt.bufPrint`
- `sendNotFound()`, `sendMethodNotAllowed()`, `sendBadRequest()`
- `sendFile()`: respond with file content + `Content-Disposition: attachment` header
- All use `request.respond(content, .{ .status = ..., .extra_headers = &.{...} })`

### Step 7: `src/router.zig` — Routing
- Extract path from `request.head.target` (strip query string)
- Match routes using `std.mem.startsWith`, `std.mem.eql`
- Route ordering: most specific first (nested paths before parent paths)
- `matchPath()` helper to extract path parameters between prefix/suffix
- Dispatch to handler functions with extracted path parameters

### Step 8: `src/handlers/tasks.zig` — Task CRUD
- **CRITICAL**: Copy `request.head.target` and `request.head.content_type` BEFORE calling `readerExpectNone()` (it invalidates Head string pointers — documented in Server.zig line 590-594)
- Read body: `request.readerExpectNone(&buffer)` → `reader.readAlloc(gpa, content_length)`
- Parse JSON: `std.json.parseFromSlice(TaskInput, gpa, body, .{ .ignore_unknown_fields = true })`
- Create: allocate + store task, respond 201
- Update: find task, free old strings, dupe new strings
- Delete: find + remove from ArrayList, free strings

### Step 9: `src/multipart.zig` — Multipart parser
- `extractBoundary()`: parse `boundary=...` from Content-Type header value
- `parse()`: split body by `\r\n--{boundary}` delimiters, parse each part's headers
- `extractParam()`: extract `name="value"` from Content-Disposition header
- Returns `[]Part` where Part = { name, filename, content_type, data }
- Handle edge cases: quoted boundaries, first boundary without leading `\r\n`, closing `--boundary--`

### Step 10: `src/handlers/attachments.zig` — Attachment handlers
- Upload: verify task exists → extract boundary → read body → parse multipart → save file parts to disk → record metadata
- List: filter `storage.attachments` by task_id, serialize as JSON array
- Download: find attachment by id → read file from disk → respond with file content

## Key API References (verified from source)

| API | Location |
|-----|----------|
| `std.process.Init` (main signature) | `/home/forinda/sdk/zig/lib/std/process.zig:30` |
| `net.IpAddress.listen()` | `/home/forinda/sdk/zig/lib/std/Io/net.zig:240` |
| `net.Server.accept()` | `/home/forinda/sdk/zig/lib/std/Io/net.zig:1418` |
| `stream.reader()` / `stream.writer()` | `/home/forinda/sdk/zig/lib/std/Io/net.zig:1375-1381` |
| `http.Server.init(reader, writer)` | `/home/forinda/sdk/zig/lib/std/http/Server.zig:25` |
| `server.receiveHead()` → `Request` | `/home/forinda/sdk/zig/lib/std/http/Server.zig:46` |
| `request.respond(content, options)` | `/home/forinda/sdk/zig/lib/std/http/Server.zig:323` |
| `request.readerExpectNone(buffer)` | `/home/forinda/sdk/zig/lib/std/http/Server.zig:591` |
| `request.head.{method,target,content_type,content_length}` | `/home/forinda/sdk/zig/lib/std/http/Server.zig:70-77` |
| `Dir.cwd().writeFile(io, options)` | `/home/forinda/sdk/zig/lib/std/Io/Dir.zig:543` |
| `Dir.cwd().readFileAlloc(io, path, gpa, limit)` | `/home/forinda/sdk/zig/lib/std/Io/Dir.zig:1211` |
| `Dir.cwd().createDirPath(io, path)` | `/home/forinda/sdk/zig/lib/std/Io/Dir.zig:728` |
| `std.json.parseFromSlice(T, gpa, bytes, options)` | `/home/forinda/sdk/zig/lib/std/json/static.zig:73` |
| `std.json.Stringify.valueAlloc(gpa, value, options)` | `/home/forinda/sdk/zig/lib/std/json/Stringify.zig:618` |
| Example HTTP server usage | `/home/forinda/sdk/zig/lib/std/Build/WebServer.zig:250-293` |

## Verification

1. **Build**: `zig build` — should compile without errors
2. **Run**: `zig build run` — server starts on port 8080
3. **Test tasks**:
   ```bash
   # Create task
   curl -X POST http://localhost:8080/api/tasks -H "Content-Type: application/json" -d '{"title":"My Task","description":"Test"}'
   # List tasks
   curl http://localhost:8080/api/tasks
   # Get task
   curl http://localhost:8080/api/tasks/1
   # Update task
   curl -X PUT http://localhost:8080/api/tasks/1 -H "Content-Type: application/json" -d '{"title":"Updated","description":"New desc","completed":true}'
   # Delete task
   curl -X DELETE http://localhost:8080/api/tasks/1
   ```
4. **Test attachments**:
   ```bash
   # Upload file
   curl -X POST http://localhost:8080/api/tasks/1/attachments -F "file=@test.txt"
   # List attachments
   curl http://localhost:8080/api/tasks/1/attachments
   # Download attachment
   curl http://localhost:8080/api/attachments/1/download -o downloaded.txt
   ```
