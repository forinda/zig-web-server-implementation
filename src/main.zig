const std = @import("std");
const fw = @import("framework/framework.zig");
const app_mod = @import("app/app.zig");
const Storage = @import("app/storage.zig").Storage;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    // Read configuration from environment variables
    const env = fw.Env.init(init.environ_map);
    const db_name = env.get("DB_NAME", "data.db");
    const app_name = env.get("APP_NAME", "Zig Web Server");
    const port = env.getInt(u16, "PORT", 8080);

    // Initialize storage (creates uploads/ directory)
    var store = Storage.init(gpa, io, db_name);
    defer store.deinit();

    // Set up and start the application
    var app = try app_mod.setup(gpa, io, &store);
    defer app.deinit();

    try app.listen(port, app_name);
}
