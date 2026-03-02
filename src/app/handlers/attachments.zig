const std = @import("std");
const fw = @import("../../framework/framework.zig");
const Context = fw.Context;
const StatusCode = fw.StatusCode;
const multipart = fw.multipart;
const Storage = @import("../storage.zig").Storage;
const models = @import("../models.zig");

/// POST /api/tasks/:id/attachments — Upload attachment (multipart/form-data)
pub fn upload(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    const task_id = parseId(ctx.param("id")) orelse {
        return ctx.sendError(StatusCode.bad_request, "Invalid task ID");
    };

    // Verify task exists
    if (store.findTask(task_id) == null) {
        return ctx.sendError(StatusCode.not_found, "Task not found");
    }

    // Extract boundary from cached Content-Type (before body read invalidates head)
    const content_type = ctx.getContentType() orelse {
        return ctx.sendError(StatusCode.bad_request, "Missing Content-Type header");
    };

    const boundary = multipart.extractBoundary(content_type) orelse {
        return ctx.sendError(StatusCode.bad_request, "Missing multipart boundary");
    };

    // Copy boundary since it points into the cached content-type buffer
    var boundary_copy_buf: [256]u8 = undefined;
    if (boundary.len > boundary_copy_buf.len) {
        return ctx.sendError(StatusCode.bad_request, "Boundary too long");
    }
    @memcpy(boundary_copy_buf[0..boundary.len], boundary);
    const boundary_copy = boundary_copy_buf[0..boundary.len];

    // Read body
    const body_data = ctx.body() catch {
        return ctx.sendError(StatusCode.bad_request, "Failed to read request body");
    };

    // Parse multipart
    const parts = multipart.parse(ctx.allocator, body_data, boundary_copy) catch {
        return ctx.sendError(StatusCode.bad_request, "Invalid multipart data");
    };
    defer ctx.allocator.free(parts);

    var uploaded_count: u32 = 0;

    // Process file parts
    for (parts) |part| {
        if (part.filename) |original_filename| {
            if (original_filename.len == 0) continue;

            // Generate a stored filename: {attachment_id}_{original}
            var name_buf: [384]u8 = undefined;
            const stored_filename = std.fmt.bufPrint(&name_buf, "{d}_{s}", .{
                store.next_attachment_id,
                original_filename,
            }) catch continue;

            // Save file to disk
            store.saveFile(stored_filename, part.data) catch continue;

            // Record attachment metadata
            _ = store.addAttachment(
                task_id,
                stored_filename,
                original_filename,
                part.content_type,
                part.data.len,
            ) catch continue;

            uploaded_count += 1;
        }
    }

    if (uploaded_count > 0) {
        var msg_buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "{{\"message\":\"{d} file(s) uploaded\"}}", .{uploaded_count}) catch
            "{\"message\":\"Files uploaded\"}";
        try ctx.setStatus(StatusCode.created).sendRawJson(msg);
    } else {
        try ctx.sendError(StatusCode.bad_request, "No files found in upload");
    }
}

/// GET /api/tasks/:id/attachments — List attachments for a task
pub fn listForTask(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    const task_id = parseId(ctx.param("id")) orelse {
        return ctx.sendError(StatusCode.bad_request, "Invalid task ID");
    };

    // Verify task exists
    if (store.findTask(task_id) == null) {
        return ctx.sendError(StatusCode.not_found, "Task not found");
    }

    // Filter attachments for this task
    var result: std.ArrayList(models.Attachment) = .empty;
    defer result.deinit(ctx.allocator);
    for (store.attachments.items) |att| {
        if (att.task_id == task_id) {
            result.append(ctx.allocator, att) catch continue;
        }
    }

    try ctx.sendJson(result.items);
}

/// GET /api/attachments/:id/download — Download an attachment
pub fn download(ctx: *Context) !void {
    const store = ctx.appContext(Storage);
    const att_id = parseId(ctx.param("id")) orelse {
        return ctx.sendError(StatusCode.bad_request, "Invalid attachment ID");
    };

    const att = store.findAttachment(att_id) orelse {
        return ctx.sendError(StatusCode.not_found, "Attachment not found");
    };

    // Read file from disk
    const file_data = store.readFile(att.filename) catch {
        return ctx.sendError(StatusCode.internal_server_error, "File not found on disk");
    };
    defer ctx.allocator.free(file_data);

    try ctx.sendFile(file_data, att.original_filename, att.content_type);
}

fn parseId(id_str: ?[]const u8) ?u64 {
    const s = id_str orelse return null;
    return std.fmt.parseInt(u64, s, 10) catch null;
}
