const std = @import("std");
const fw = @import("../../framework/framework.zig");
const Context = fw.Context;
const StatusCode = fw.StatusCode;
const Storage = @import("../storage.zig").Storage;
const models = @import("../models.zig");

/// GET /api/tasks
pub fn list(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    const tasks = store.listTasks(ctx.allocator) catch {
        return ctx.sendError(StatusCode.internal_server_error, "Failed to list tasks");
    };
    defer Storage.freeTasks(ctx.allocator, tasks);
    try ctx.sendJson(tasks);
}

/// GET /api/tasks/:id
pub fn getOne(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    const id = parseId(ctx.param("id")) orelse {
        return ctx.sendError(StatusCode.bad_request, "Invalid task ID");
    };
    const task = store.findTask(ctx.allocator, id) catch {
        return ctx.sendError(StatusCode.internal_server_error, "Database error");
    } orelse {
        return ctx.sendError(StatusCode.not_found, "Task not found");
    };
    defer Storage.freeTask(ctx.allocator, task);
    try ctx.sendJson(task);
}

/// POST /api/tasks
pub fn create(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    const parsed = ctx.json(models.TaskInput) catch {
        return ctx.sendError(StatusCode.bad_request, "Invalid JSON body");
    };
    defer parsed.deinit();
    const input = parsed.value;

    const task = store.addTask(ctx.allocator, input.title, input.description, input.completed) catch {
        return ctx.sendError(StatusCode.internal_server_error, "Failed to create task");
    };
    defer Storage.freeTask(ctx.allocator, task);
    try ctx.setStatus(StatusCode.created).sendJson(task);
}

/// PUT /api/tasks/:id
pub fn update(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    const id = parseId(ctx.param("id")) orelse {
        return ctx.sendError(StatusCode.bad_request, "Invalid task ID");
    };

    const parsed = ctx.json(models.TaskInput) catch {
        return ctx.sendError(StatusCode.bad_request, "Invalid JSON body");
    };
    defer parsed.deinit();
    const input = parsed.value;

    const task = store.updateTask(ctx.allocator, id, input.title, input.description, input.completed) catch {
        return ctx.sendError(StatusCode.internal_server_error, "Failed to update task");
    } orelse {
        return ctx.sendError(StatusCode.not_found, "Task not found");
    };
    defer Storage.freeTask(ctx.allocator, task);
    try ctx.sendJson(task);
}

/// DELETE /api/tasks/:id
pub fn delete(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    const id = parseId(ctx.param("id")) orelse {
        return ctx.sendError(StatusCode.bad_request, "Invalid task ID");
    };
    const deleted = store.deleteTask(id) catch {
        return ctx.sendError(StatusCode.internal_server_error, "Failed to delete task");
    };
    if (deleted) {
        try ctx.sendRawJson("{\"message\":\"Task deleted\"}");
    } else {
        try ctx.sendError(StatusCode.not_found, "Task not found");
    }
}

fn parseId(id_str: ?[]const u8) ?u64 {
    const s = id_str orelse return null;
    return std.fmt.parseInt(u64, s, 10) catch null;
}
