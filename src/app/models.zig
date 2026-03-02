const std = @import("std");

pub const Task = struct {
    id: u64,
    title: []const u8,
    description: []const u8,
    completed: bool,
};

pub const TaskInput = struct {
    title: []const u8,
    description: []const u8 = "",
    completed: bool = false,
};

pub const Attachment = struct {
    id: u64,
    task_id: u64,
    filename: []const u8,
    original_filename: []const u8,
    content_type: []const u8,
    size: u64,
};
