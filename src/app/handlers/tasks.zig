const std = @import("std");
const fw = @import("../../framework/framework.zig");
const Context = fw.Context;
const StatusCode = fw.StatusCode;
const Storage = @import("../storage.zig").Storage;
const models = @import("../models.zig");

/// GET /api/tasks
pub fn list(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    try ctx.sendJson(store.tasks.items);
}

/// GET /api/tasks/:id
pub fn getOne(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    const id = parseId(ctx.param("id")) orelse {
        return ctx.sendError(StatusCode.bad_request, "Invalid task ID");
    };
    const task = store.findTask(id) orelse {
        return ctx.sendError(StatusCode.not_found, "Task not found");
    };
    try ctx.sendJson(task.*);
}

/// POST /api/tasks
pub fn create(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    const parsed = ctx.json(models.TaskInput) catch {
        return ctx.sendError(StatusCode.bad_request, "Invalid JSON body");
    };
    defer parsed.deinit();
    const input = parsed.value;

    const task = store.addTask(input.title, input.description, input.completed) catch {
        return ctx.sendError(StatusCode.internal_server_error, "Failed to create task");
    };
    try ctx.setStatus(StatusCode.created).sendJson(task.*);
}

/// PUT /api/tasks/:id
pub fn update(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    const id = parseId(ctx.param("id")) orelse {
        return ctx.sendError(StatusCode.bad_request, "Invalid task ID");
    };
    const task = store.findTask(id) orelse {
        return ctx.sendError(StatusCode.not_found, "Task not found");
    };

    const parsed = ctx.json(models.TaskInput) catch {
        return ctx.sendError(StatusCode.bad_request, "Invalid JSON body");
    };
    defer parsed.deinit();
    const input = parsed.value;

    const gpa = ctx.allocator;
    const new_title = gpa.dupe(u8, input.title) catch {
        return ctx.sendError(StatusCode.internal_server_error, "Out of memory");
    };
    const new_desc = gpa.dupe(u8, input.description) catch {
        gpa.free(new_title);
        return ctx.sendError(StatusCode.internal_server_error, "Out of memory");
    };
    gpa.free(task.title);
    gpa.free(task.description);
    task.title = new_title;
    task.description = new_desc;
    task.completed = input.completed;

    try ctx.sendJson(task.*);
}

/// DELETE /api/tasks/:id
pub fn delete(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    const id = parseId(ctx.param("id")) orelse {
        return ctx.sendError(StatusCode.bad_request, "Invalid task ID");
    };
    if (store.deleteTask(id)) {
        try ctx.sendRawJson("{\"message\":\"Task deleted\"}");
    } else {
        try ctx.sendError(StatusCode.not_found, "Task not found");
    }
}

fn parseId(id_str: ?[]const u8) ?u64 {
    const s = id_str orelse return null;
    return std.fmt.parseInt(u64, s, 10) catch null;
}
