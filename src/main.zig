const std = @import("std");
const app_mod = @import("app/app.zig");
const Storage = @import("app/storage.zig").Storage;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    // Initialize storage (creates uploads/ directory)
    var store = Storage.init(gpa, io);
    defer store.deinit();

    // Set up and start the application
    var app = try app_mod.setup(gpa, io, &store);
    defer app.deinit();

    try app.listen(8080);
}
