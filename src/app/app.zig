const std = @import("std");
const fw = @import("../framework/framework.zig");
const Storage = @import("storage.zig").Storage;
const task_handlers = @import("handlers/tasks.zig");
const attachment_handlers = @import("handlers/attachments.zig");

pub fn setup(allocator: std.mem.Allocator, io: std.Io, store: *Storage) !fw.App(Storage) {
    var app = fw.App(Storage).init(allocator, io, store);

    // Middleware
    try app.use(fw.middleware.logger);

    // Task routes
    try app.get("/api/tasks", task_handlers.list);
    try app.post("/api/tasks", task_handlers.create);
    try app.get("/api/tasks/:id", task_handlers.getOne);
    try app.put("/api/tasks/:id", task_handlers.update);
    try app.delete("/api/tasks/:id", task_handlers.delete);

    // Attachment routes
    try app.post("/api/tasks/:id/attachments", attachment_handlers.upload);
    try app.get("/api/tasks/:id/attachments", attachment_handlers.listForTask);
    try app.get("/api/attachments/:id/download", attachment_handlers.download);

    // Health check
    try app.get("/health", struct {
        fn handler(ctx: *fw.Context) !void {
            try ctx.sendRawJson("{\"status\":\"ok\"}");
        }
    }.handler);

    return app;
}
