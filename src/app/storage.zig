const std = @import("std");
const Io = std.Io;
const Dir = std.Io.Dir;
const models = @import("models.zig");
const Task = models.Task;
const Attachment = models.Attachment;

pub const Storage = struct {
    tasks: std.ArrayList(Task),
    attachments: std.ArrayList(Attachment),
    next_task_id: u64,
    next_attachment_id: u64,
    gpa: std.mem.Allocator,
    io: Io,

    pub fn init(gpa: std.mem.Allocator, io: Io) Storage {
        Dir.cwd().createDirPath(io, "uploads") catch {};

        return .{
            .tasks = .empty,
            .attachments = .empty,
            .next_task_id = 1,
            .next_attachment_id = 1,
            .gpa = gpa,
            .io = io,
        };
    }

    pub fn deinit(self: *Storage) void {
        for (self.tasks.items) |task| {
            self.gpa.free(task.title);
            self.gpa.free(task.description);
        }
        self.tasks.deinit(self.gpa);

        for (self.attachments.items) |att| {
            self.gpa.free(att.filename);
            self.gpa.free(att.original_filename);
            self.gpa.free(att.content_type);
        }
        self.attachments.deinit(self.gpa);
    }

    pub fn addTask(self: *Storage, title: []const u8, desc: []const u8, completed: bool) !*const Task {
        const id = self.next_task_id;
        self.next_task_id += 1;
        const owned_title = try self.gpa.dupe(u8, title);
        errdefer self.gpa.free(owned_title);
        const owned_desc = try self.gpa.dupe(u8, desc);
        errdefer self.gpa.free(owned_desc);

        try self.tasks.append(self.gpa, .{
            .id = id,
            .title = owned_title,
            .description = owned_desc,
            .completed = completed,
        });
        return &self.tasks.items[self.tasks.items.len - 1];
    }

    pub fn findTask(self: *Storage, id: u64) ?*Task {
        for (self.tasks.items) |*task| {
            if (task.id == id) return task;
        }
        return null;
    }

    pub fn deleteTask(self: *Storage, id: u64) bool {
        for (self.tasks.items, 0..) |task, i| {
            if (task.id == id) {
                self.gpa.free(task.title);
                self.gpa.free(task.description);
                _ = self.tasks.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn addAttachment(
        self: *Storage,
        task_id: u64,
        filename: []const u8,
        original: []const u8,
        content_type_val: []const u8,
        size: u64,
    ) !*const Attachment {
        const id = self.next_attachment_id;
        self.next_attachment_id += 1;
        const owned_filename = try self.gpa.dupe(u8, filename);
        errdefer self.gpa.free(owned_filename);
        const owned_original = try self.gpa.dupe(u8, original);
        errdefer self.gpa.free(owned_original);
        const owned_ct = try self.gpa.dupe(u8, content_type_val);
        errdefer self.gpa.free(owned_ct);

        try self.attachments.append(self.gpa, .{
            .id = id,
            .task_id = task_id,
            .filename = owned_filename,
            .original_filename = owned_original,
            .content_type = owned_ct,
            .size = size,
        });
        return &self.attachments.items[self.attachments.items.len - 1];
    }

    pub fn findAttachment(self: *Storage, id: u64) ?*const Attachment {
        for (self.attachments.items) |*att| {
            if (att.id == id) return att;
        }
        return null;
    }

    pub fn saveFile(self: *Storage, filename: []const u8, data: []const u8) !void {
        var path_buf: [512]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "uploads/{s}", .{filename}) catch return error.OutOfMemory;
        try Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = data });
    }

    pub fn readFile(self: *Storage, filename: []const u8) ![]u8 {
        var path_buf: [512]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "uploads/{s}", .{filename}) catch return error.OutOfMemory;
        return Dir.cwd().readFileAlloc(self.io, path, self.gpa, .limited(50 * 1024 * 1024));
    }
};
