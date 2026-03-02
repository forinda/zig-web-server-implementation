# Zig Web Server

A task management REST API built from scratch with Zig 0.16, featuring a custom Express.js-inspired HTTP framework and SQLite persistence.

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

## Development (Hot Reload)

```bash
zig build dev
```

Watches `src/` for `.zig` file changes and automatically rebuilds and restarts. Uses `inotifywait` if available, otherwise polls every 1s.

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

## Tests

```bash
zig build test
```
