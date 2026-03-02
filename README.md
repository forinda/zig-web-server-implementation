# Zig Web Server

A task management REST API built from scratch with Zig 0.16, featuring a custom Express.js-inspired HTTP framework and SQLite persistence.

> **Disclaimer:** This project is an experimental learning exercise and is **not intended for production use**. It is meant to explore Zig's capabilities for building web servers and HTTP frameworks. Use at your own risk.

## Prerequisites

- [Zig 0.16.0-dev](https://ziglang.org/download/) (nightly)

SQLite is bundled as an amalgamation — no system libraries required.

## Quick Start

```bash
zig build run
```

The server starts at `http://127.0.0.1:8080`.

## Configuration

Configuration is done via environment variables:

| Variable   | Default            | Description              |
|------------|--------------------|--------------------------|
| `PORT`     | `8080`             | Server listen port       |
| `DB_NAME`  | `data.db`          | SQLite database filename |
| `APP_NAME` | `Zig Web Server`   | Name shown at startup    |

```bash
PORT=3000 DB_NAME=myapp.db zig build run
```

You can also create a `.env` file in the project root for local development. The `dev.sh` hot reload script and standard shell usage will pick these up:

```bash
# .env
PORT=4000
DB_NAME=dev.db
APP_NAME=My App
```

Then source it before running:

```bash
source .env && zig build run
```

The `.env` file is git-ignored by default.

## Development (Hot Reload)

```bash
zig build dev
```

Watches `src/` for `.zig` file changes and automatically rebuilds and restarts. Uses `inotifywait` if available, otherwise polls every 1s.

## Framework Features

This project includes a custom HTTP framework built on Zig's `std.http` and async `std.Io`. Key features:

- **Pattern Router** — Routes support `:param` segments (e.g., `/api/tasks/:id`). Parameters are captured and accessible via `ctx.param("id")` in handlers. Matching is exact — no wildcards or trailing slash ambiguity.

- **Middleware Chaining** — Middlewares run sequentially via `ctx.next()`. Each middleware can run logic before and after the handler, or short-circuit the chain entirely (e.g., CORS preflight).

- **Typed App State** — `App(Storage)` is generic over your state type. Handlers access it via `ctx.appContext(Storage)` with full type safety — no casting needed in user code.

- **Multipart Upload Parsing** — Built-in RFC 2046 parser extracts form fields and file uploads from `multipart/form-data` requests, returning structured `Part` values with name, filename, content type, and raw data.

### Built-in Middleware

| Middleware      | Behavior                                                                 |
|-----------------|--------------------------------------------------------------------------|
| **Logger**      | Prints `[METHOD] /path` for every request to stderr                      |
| **CORS**        | Sets `Access-Control-Allow-Origin: *`, handles OPTIONS preflight (204)   |
| **Compression** | Gzip-compresses responses >= 860 bytes when client sends `Accept-Encoding: gzip` |

Middleware is registered in `src/app/app.zig`:

```zig
try app.use(fw.middlewares.compression);
try app.use(fw.middlewares.cors);
try app.use(fw.middlewares.logger);
```

## API Endpoints

### Tasks

| Method   | Path               | Description       |
|----------|--------------------|-------------------|
| `GET`    | `/api/tasks`       | List all tasks    |
| `POST`   | `/api/tasks`       | Create a task     |
| `GET`    | `/api/tasks/:id`   | Get a task        |
| `PUT`    | `/api/tasks/:id`   | Update a task     |
| `DELETE` | `/api/tasks/:id`   | Delete a task     |

### Attachments

| Method | Path                           | Description                  |
|--------|--------------------------------|------------------------------|
| `POST` | `/api/tasks/:id/attachments`   | Upload a file to a task      |
| `GET`  | `/api/tasks/:id/attachments`   | List attachments for a task  |
| `GET`  | `/api/attachments/:id/download`| Download an attachment       |

### Health

| Method | Path      | Description  |
|--------|-----------|--------------|
| `GET`  | `/health` | Health check |

## Examples

```bash
# Create a task
curl -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Buy groceries", "description": "Milk, eggs, bread"}'

# List tasks
curl http://localhost:8080/api/tasks

# Update a task
curl -X PUT http://localhost:8080/api/tasks/1 \
  -H "Content-Type: application/json" \
  -d '{"title": "Buy groceries", "description": "Milk, eggs, bread", "completed": true}'

# Delete a task
curl -X DELETE http://localhost:8080/api/tasks/1

# Upload an attachment
curl -X POST http://localhost:8080/api/tasks/1/attachments \
  -F "file=@document.pdf"
```

## Project Structure

```
src/
  main.zig              Entry point
  app/
    app.zig             Route and middleware setup
    models.zig          Task and Attachment structs
    storage.zig         SQLite-backed data layer
    handlers/
      tasks.zig         Task CRUD handlers
      attachments.zig   Attachment handlers
  framework/
    framework.zig       Public API re-exports
    app.zig             Generic App(State) with router and listener
    server.zig          HTTP connection handling
    context.zig         Request context (params, body, response helpers)
    router.zig          Pattern-matching router with :param support
    middlewares/        Logger, CORS, compression
    utils/             Status codes, multipart parsing, gzip, headers, env
    adapters/          SQLite C interop wrapper
deps/                  Bundled SQLite amalgamation
dev.sh                 Hot reload script
```

## Known Limitations

- **Single-threaded** — The server processes one request at a time. Under concurrent load, requests queue at the TCP accept level. A slow handler (e.g., large file upload) will block all other clients until it completes.
- **No HTTP keep-alive** — Each request uses a fresh TCP connection (`connection: close`). This was necessary because the single-threaded accept loop cannot serve other clients while waiting for the next request on a keep-alive connection. Clients like `curl` work fine, but high-throughput scenarios will pay the cost of TCP handshakes per request.
- **No TLS** — The server speaks plain HTTP. Use a reverse proxy (e.g., nginx, Caddy) if you need HTTPS.

## Tests

```bash
zig build test
```

## Resources

### Official Zig

- [Zig Language](https://ziglang.org/) — The programming language and toolchain
- [Language Reference](https://ziglang.org/documentation/master/) — Full language specification
- [Standard Library Docs](https://ziglang.org/documentation/0.15.2/std/) — `std` API reference
- [Getting Started](https://ziglang.org/learn/getting-started/) — Installation and first steps
- [Language Overview](https://ziglang.org/learn/overview/) — High-level tour of the language
- [Why Zig?](https://ziglang.org/learn/why_zig_rust_d_cpp/) — Comparison with Rust, D, and C++
- [Code Samples](https://ziglang.org/learn/samples/) — Official example programs
- [Build System](https://ziglang.org/learn/build-system/) — Guide to `build.zig` and the Zig build system

### Learning

- [Zig Book](https://pedropark99.github.io/zig-book/) by Pedro Park — Comprehensive book covering:
  - [Language Basics](https://pedropark99.github.io/zig-book/Chapters/01-zig-weird.html) — What makes Zig different
  - [Memory Management](https://pedropark99.github.io/zig-book/Chapters/01-memory.html) — Allocators and manual memory
  - [Structs](https://pedropark99.github.io/zig-book/Chapters/03-structs.html) — Data types and methods
  - [Unit Testing](https://pedropark99.github.io/zig-book/Chapters/03-unittests.html) — Testing with `std.testing`
  - [Pointers](https://pedropark99.github.io/zig-book/Chapters/05-pointers.html) — Pointer semantics and slices
  - [Build System](https://pedropark99.github.io/zig-book/Chapters/07-build-system.html) — Build configuration
  - [Error Handling](https://pedropark99.github.io/zig-book/Chapters/09-error-handling.html) — Error unions and `try`/`catch`
  - [Data Structures](https://pedropark99.github.io/zig-book/Chapters/09-data-structures.html) — ArrayList, HashMap, etc.
  - [File Operations](https://pedropark99.github.io/zig-book/Chapters/12-file-op.html) — Reading and writing files
  - [C Interop](https://pedropark99.github.io/zig-book/Chapters/14-zig-c-interop.html) — Calling C from Zig (used by our SQLite adapter)
  - [Threads](https://pedropark99.github.io/zig-book/Chapters/14-threads.html) — Concurrency primitives
  - [Debugging](https://pedropark99.github.io/zig-book/Chapters/02-debugging.html) — Debug tooling and techniques
- [Ziglings](https://codeberg.org/ziglings/exercises/) — Learn Zig by fixing small broken programs

### Project Dependencies

- [SQLite](https://www.sqlite.org/) — Embedded database engine, bundled as the [amalgamation](https://www.sqlite.org/amalgamation.html) in `deps/`
- [Claude Code](https://claude.com/claude-code) — AI pair programming assistant used during development
