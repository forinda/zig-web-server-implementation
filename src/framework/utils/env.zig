//! Environment variable utilities.
//!
//! Provides typed getters with defaults over the process environment map.
//!
//! Usage:
//!   const Env = @import("framework/framework.zig").Env;
//!   var env = Env.init(init.environ_map);
//!   const port = env.getInt(u16, "PORT", 8080);
//!   const db = env.get("DB_NAME", "data.db");

const std = @import("std");

pub const Env = struct {
    map: *std.process.Environ.Map,

    pub fn init(map: *std.process.Environ.Map) Env {
        return .{ .map = map };
    }

    /// Get a string env var, returning `default` if not set.
    pub fn get(self: Env, key: []const u8, default: []const u8) []const u8 {
        return self.map.get(key) orelse default;
    }

    /// Get an optional string env var (null if not set).
    pub fn getOptional(self: Env, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }

    /// Get an integer env var, returning `default` if not set or unparseable.
    pub fn getInt(self: Env, comptime T: type, key: []const u8, default: T) T {
        const val = self.map.get(key) orelse return default;
        return std.fmt.parseInt(T, val, 10) catch default;
    }

    /// Get a boolean env var. Truthy: "1", "true", "yes". Falsy: "0", "false", "no".
    /// Returns `default` if not set or unrecognized.
    pub fn getBool(self: Env, key: []const u8, default: bool) bool {
        const val = self.map.get(key) orelse return default;
        if (std.mem.eql(u8, val, "1") or std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "yes")) return true;
        if (std.mem.eql(u8, val, "0") or std.mem.eql(u8, val, "false") or std.mem.eql(u8, val, "no")) return false;
        return default;
    }
};

// ---- Tests ----

const testing = std.testing;

fn testEnv(entries: []const struct { []const u8, []const u8 }) Env {
    const S = struct {
        var map: std.process.Environ.Map = undefined;
    };
    S.map = std.process.Environ.Map.init(testing.allocator);
    for (entries) |kv| {
        S.map.put(kv[0], kv[1]) catch @panic("OOM in test setup");
    }
    return Env.init(&S.map);
}

test "get returns value when set" {
    var env = testEnv(&.{ .{ "DB_NAME", "myapp.db" } });
    defer env.map.deinit();

    try testing.expectEqualStrings("myapp.db", env.get("DB_NAME", "data.db"));
}

test "get returns default when not set" {
    var env = testEnv(&.{});
    defer env.map.deinit();

    try testing.expectEqualStrings("data.db", env.get("DB_NAME", "data.db"));
}

test "getOptional returns value when set" {
    var env = testEnv(&.{ .{ "APP_NAME", "My App" } });
    defer env.map.deinit();

    try testing.expectEqualStrings("My App", env.getOptional("APP_NAME").?);
}

test "getOptional returns null when not set" {
    var env = testEnv(&.{});
    defer env.map.deinit();

    try testing.expect(env.getOptional("APP_NAME") == null);
}

test "getInt parses valid integer" {
    var env = testEnv(&.{ .{ "PORT", "3000" } });
    defer env.map.deinit();

    try testing.expectEqual(@as(u16, 3000), env.getInt(u16, "PORT", 8080));
}

test "getInt returns default when not set" {
    var env = testEnv(&.{});
    defer env.map.deinit();

    try testing.expectEqual(@as(u16, 8080), env.getInt(u16, "PORT", 8080));
}

test "getInt returns default for invalid value" {
    var env = testEnv(&.{ .{ "PORT", "not_a_number" } });
    defer env.map.deinit();

    try testing.expectEqual(@as(u16, 8080), env.getInt(u16, "PORT", 8080));
}

test "getInt returns default for out-of-range value" {
    var env = testEnv(&.{ .{ "PORT", "99999" } });
    defer env.map.deinit();

    try testing.expectEqual(@as(u16, 8080), env.getInt(u16, "PORT", 8080));
}

test "getBool recognizes truthy values" {
    for ([_][]const u8{ "1", "true", "yes" }) |val| {
        var env = testEnv(&.{ .{ "DEBUG", val } });
        defer env.map.deinit();

        try testing.expect(env.getBool("DEBUG", false) == true);
    }
}

test "getBool recognizes falsy values" {
    for ([_][]const u8{ "0", "false", "no" }) |val| {
        var env = testEnv(&.{ .{ "DEBUG", val } });
        defer env.map.deinit();

        try testing.expect(env.getBool("DEBUG", true) == false);
    }
}

test "getBool returns default when not set" {
    var env = testEnv(&.{});
    defer env.map.deinit();

    try testing.expect(env.getBool("DEBUG", false) == false);
    try testing.expect(env.getBool("DEBUG", true) == true);
}

test "getBool returns default for unrecognized value" {
    var env = testEnv(&.{ .{ "DEBUG", "maybe" } });
    defer env.map.deinit();

    try testing.expect(env.getBool("DEBUG", false) == false);
}
