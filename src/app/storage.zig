const std = @import("std");
const Io = std.Io;
const Dir = std.Io.Dir;
const models = @import("models.zig");
const Task = models.Task;
const Attachment = models.Attachment;
const sqlite = @import("../framework/adapters/sqlite.zig");
const Database = sqlite.Database;

pub const Storage = struct {
    db: Database,
    gpa: std.mem.Allocator,
    io: Io,

    pub fn init(gpa: std.mem.Allocator, io: Io) Storage {
        Dir.cwd().createDirPath(io, "uploads") catch {};

        var db = Database.open("data.db") catch |err| {
            std.debug.print("Failed to open database: {s}\n", .{@errorName(err)});
            @panic("Cannot open data.db");
        };

        db.exec(
            "CREATE TABLE IF NOT EXISTS tasks (" ++
                "id INTEGER PRIMARY KEY AUTOINCREMENT, " ++
                "title TEXT NOT NULL, " ++
                "description TEXT NOT NULL DEFAULT '', " ++
                "completed INTEGER NOT NULL DEFAULT 0)",
        ) catch |err| {
            std.debug.print("Failed to create tasks table: {s}\n", .{@errorName(err)});
            @panic("Schema initialization failed");
        };

        db.exec(
            "CREATE TABLE IF NOT EXISTS attachments (" ++
                "id INTEGER PRIMARY KEY AUTOINCREMENT, " ++
                "task_id INTEGER NOT NULL, " ++
                "filename TEXT NOT NULL, " ++
                "original_filename TEXT NOT NULL, " ++
                "content_type TEXT NOT NULL, " ++
                "size INTEGER NOT NULL, " ++
                "FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE)",
        ) catch |err| {
            std.debug.print("Failed to create attachments table: {s}\n", .{@errorName(err)});
            @panic("Schema initialization failed");
        };

        db.exec("PRAGMA foreign_keys = ON") catch {};

        return .{
            .db = db,
            .gpa = gpa,
            .io = io,
        };
    }

    pub fn deinit(self: *Storage) void {
        self.db.close();
    }

    // ---- Task operations ----

    /// Return all tasks. Caller must call freeTasks() on the result.
    pub fn listTasks(self: *Storage, allocator: std.mem.Allocator) ![]Task {
        var stmt = try self.db.prepare("SELECT id, title, description, completed FROM tasks ORDER BY id");
        defer stmt.finalize();

        var tasks: std.ArrayList(Task) = .empty;
        errdefer {
            for (tasks.items) |t| {
                allocator.free(t.title);
                allocator.free(t.description);
            }
            tasks.deinit(allocator);
        }

        while (try stmt.step()) {
            const id_val = try stmt.columnValue(allocator, 0);
            const title_val = try stmt.columnValue(allocator, 1);
            errdefer allocator.free(title_val.text);
            const desc_val = try stmt.columnValue(allocator, 2);
            errdefer allocator.free(desc_val.text);
            const completed_val = try stmt.columnValue(allocator, 3);

            try tasks.append(allocator, .{
                .id = @intCast(id_val.integer),
                .title = title_val.text,
                .description = desc_val.text,
                .completed = completed_val.integer != 0,
            });
        }

        return try tasks.toOwnedSlice(allocator);
    }

    pub fn freeTasks(allocator: std.mem.Allocator, tasks: []Task) void {
        for (tasks) |t| {
            allocator.free(t.title);
            allocator.free(t.description);
        }
        allocator.free(tasks);
    }

    /// Find a task by ID. Caller must call freeTask() on the result.
    pub fn findTask(self: *Storage, allocator: std.mem.Allocator, id: u64) !?Task {
        var stmt = try self.db.prepare("SELECT id, title, description, completed FROM tasks WHERE id = ?1");
        defer stmt.finalize();
        try stmt.bindInt(1, @intCast(id));

        if (try stmt.step()) {
            const id_val = try stmt.columnValue(allocator, 0);
            const title_val = try stmt.columnValue(allocator, 1);
            errdefer allocator.free(title_val.text);
            const desc_val = try stmt.columnValue(allocator, 2);
            errdefer allocator.free(desc_val.text);
            const completed_val = try stmt.columnValue(allocator, 3);

            return .{
                .id = @intCast(id_val.integer),
                .title = title_val.text,
                .description = desc_val.text,
                .completed = completed_val.integer != 0,
            };
        }
        return null;
    }

    pub fn freeTask(allocator: std.mem.Allocator, task: Task) void {
        allocator.free(task.title);
        allocator.free(task.description);
    }

    /// Insert a new task. Caller must call freeTask() on the result.
    pub fn addTask(self: *Storage, allocator: std.mem.Allocator, title: []const u8, desc: []const u8, completed: bool) !Task {
        var stmt = try self.db.prepare("INSERT INTO tasks (title, description, completed) VALUES (?1, ?2, ?3)");
        defer stmt.finalize();
        try stmt.bindText(1, title);
        try stmt.bindText(2, desc);
        try stmt.bindInt(3, if (completed) 1 else 0);
        _ = try stmt.exec();

        const new_id: u64 = @intCast(self.db.lastInsertRowId());

        return .{
            .id = new_id,
            .title = try allocator.dupe(u8, title),
            .description = try allocator.dupe(u8, desc),
            .completed = completed,
        };
    }

    /// Update a task. Returns null if task not found. Caller must call freeTask().
    pub fn updateTask(self: *Storage, allocator: std.mem.Allocator, id: u64, title: []const u8, desc: []const u8, completed: bool) !?Task {
        var stmt = try self.db.prepare("UPDATE tasks SET title = ?1, description = ?2, completed = ?3 WHERE id = ?4");
        defer stmt.finalize();
        try stmt.bindText(1, title);
        try stmt.bindText(2, desc);
        try stmt.bindInt(3, if (completed) 1 else 0);
        try stmt.bindInt(4, @intCast(id));
        _ = try stmt.exec();

        if (self.db.changes() == 0) return null;

        return .{
            .id = id,
            .title = try allocator.dupe(u8, title),
            .description = try allocator.dupe(u8, desc),
            .completed = completed,
        };
    }

    /// Delete a task by ID. Returns true if a row was deleted.
    pub fn deleteTask(self: *Storage, id: u64) !bool {
        var del_att = try self.db.prepare("DELETE FROM attachments WHERE task_id = ?1");
        defer del_att.finalize();
        try del_att.bindInt(1, @intCast(id));
        _ = try del_att.exec();

        var stmt = try self.db.prepare("DELETE FROM tasks WHERE id = ?1");
        defer stmt.finalize();
        try stmt.bindInt(1, @intCast(id));
        _ = try stmt.exec();

        return self.db.changes() > 0;
    }

    /// Check if a task exists (lightweight, no data returned).
    pub fn taskExists(self: *Storage, id: u64) !bool {
        var stmt = try self.db.prepare("SELECT 1 FROM tasks WHERE id = ?1");
        defer stmt.finalize();
        try stmt.bindInt(1, @intCast(id));
        return try stmt.step();
    }

    // ---- Attachment operations ----

    /// Get the next attachment ID (for filename generation before INSERT).
    pub fn nextAttachmentId(self: *Storage) !u64 {
        var stmt = try self.db.prepare("SELECT seq FROM sqlite_sequence WHERE name = 'attachments'");
        defer stmt.finalize();
        if (try stmt.step()) {
            const val = try stmt.columnValue(self.gpa, 0);
            return @as(u64, @intCast(val.integer)) + 1;
        }
        return 1;
    }

    /// Insert a new attachment. Caller must call freeAttachment() on the result.
    pub fn addAttachment(
        self: *Storage,
        allocator: std.mem.Allocator,
        task_id: u64,
        filename: []const u8,
        original: []const u8,
        content_type_val: []const u8,
        size: u64,
    ) !Attachment {
        var stmt = try self.db.prepare(
            "INSERT INTO attachments (task_id, filename, original_filename, content_type, size) VALUES (?1, ?2, ?3, ?4, ?5)",
        );
        defer stmt.finalize();
        try stmt.bindInt(1, @intCast(task_id));
        try stmt.bindText(2, filename);
        try stmt.bindText(3, original);
        try stmt.bindText(4, content_type_val);
        try stmt.bindInt(5, @intCast(size));
        _ = try stmt.exec();

        const new_id: u64 = @intCast(self.db.lastInsertRowId());

        return .{
            .id = new_id,
            .task_id = task_id,
            .filename = try allocator.dupe(u8, filename),
            .original_filename = try allocator.dupe(u8, original),
            .content_type = try allocator.dupe(u8, content_type_val),
            .size = size,
        };
    }

    /// Find an attachment by ID. Caller must call freeAttachment().
    pub fn findAttachment(self: *Storage, allocator: std.mem.Allocator, id: u64) !?Attachment {
        var stmt = try self.db.prepare(
            "SELECT id, task_id, filename, original_filename, content_type, size FROM attachments WHERE id = ?1",
        );
        defer stmt.finalize();
        try stmt.bindInt(1, @intCast(id));

        if (try stmt.step()) {
            const id_val = try stmt.columnValue(allocator, 0);
            const tid_val = try stmt.columnValue(allocator, 1);
            const fname_val = try stmt.columnValue(allocator, 2);
            errdefer allocator.free(fname_val.text);
            const orig_val = try stmt.columnValue(allocator, 3);
            errdefer allocator.free(orig_val.text);
            const ct_val = try stmt.columnValue(allocator, 4);
            errdefer allocator.free(ct_val.text);
            const size_val = try stmt.columnValue(allocator, 5);

            return .{
                .id = @intCast(id_val.integer),
                .task_id = @intCast(tid_val.integer),
                .filename = fname_val.text,
                .original_filename = orig_val.text,
                .content_type = ct_val.text,
                .size = @intCast(size_val.integer),
            };
        }
        return null;
    }

    /// List all attachments for a task. Caller must call freeAttachments().
    pub fn listAttachments(self: *Storage, allocator: std.mem.Allocator, task_id: u64) ![]Attachment {
        var stmt = try self.db.prepare(
            "SELECT id, task_id, filename, original_filename, content_type, size FROM attachments WHERE task_id = ?1 ORDER BY id",
        );
        defer stmt.finalize();
        try stmt.bindInt(1, @intCast(task_id));

        var atts: std.ArrayList(Attachment) = .empty;
        errdefer {
            for (atts.items) |a| {
                allocator.free(a.filename);
                allocator.free(a.original_filename);
                allocator.free(a.content_type);
            }
            atts.deinit(allocator);
        }

        while (try stmt.step()) {
            const id_val = try stmt.columnValue(allocator, 0);
            const tid_val = try stmt.columnValue(allocator, 1);
            const fname_val = try stmt.columnValue(allocator, 2);
            errdefer allocator.free(fname_val.text);
            const orig_val = try stmt.columnValue(allocator, 3);
            errdefer allocator.free(orig_val.text);
            const ct_val = try stmt.columnValue(allocator, 4);
            errdefer allocator.free(ct_val.text);
            const size_val = try stmt.columnValue(allocator, 5);

            try atts.append(allocator, .{
                .id = @intCast(id_val.integer),
                .task_id = @intCast(tid_val.integer),
                .filename = fname_val.text,
                .original_filename = orig_val.text,
                .content_type = ct_val.text,
                .size = @intCast(size_val.integer),
            });
        }

        return try atts.toOwnedSlice(allocator);
    }

    pub fn freeAttachment(allocator: std.mem.Allocator, att: Attachment) void {
        allocator.free(att.filename);
        allocator.free(att.original_filename);
        allocator.free(att.content_type);
    }

    pub fn freeAttachments(allocator: std.mem.Allocator, atts: []Attachment) void {
        for (atts) |a| {
            allocator.free(a.filename);
            allocator.free(a.original_filename);
            allocator.free(a.content_type);
        }
        allocator.free(atts);
    }

    // ---- File operations (unchanged) ----

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
