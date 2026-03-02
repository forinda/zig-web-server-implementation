//! SQLite database adapter using C interop.
//!
//! Provides a Zig-idiomatic wrapper around the SQLite3 C API.
//!
//! Requirements:
//!   - libsqlite3-dev system package
//!   - Build with: zig build -Dsqlite=true
//!
//! Usage:
//!   const sqlite = @import("framework/adapters/sqlite.zig");
//!   var db = try sqlite.Database.open("myapp.db");
//!   defer db.close();
//!   try db.exec("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)");

const std = @import("std");
const c = @cImport(@cInclude("sqlite3.h"));

pub const SqliteError = error{
    CantOpen,
    SqlError,
    Busy,
    Constraint,
    Misuse,
    Internal,
    OutOfMemory,
};

/// A single value from a SQLite row.
pub const Value = union(enum) {
    integer: i64,
    float: f64,
    text: []const u8,
    blob: []const u8,
    null_val: void,
};

/// A single row from a query result.
pub const Row = struct {
    values: []Value,
    columns: [][]const u8,
    allocator: std.mem.Allocator,

    /// Get a value by column name.
    pub fn get(self: *const Row, column_name: []const u8) ?Value {
        for (self.columns, 0..) |col, i| {
            if (std.mem.eql(u8, col, column_name)) {
                return self.values[i];
            }
        }
        return null;
    }

    /// Get an integer value by column name.
    pub fn getInt(self: *const Row, column_name: []const u8) ?i64 {
        const val = self.get(column_name) orelse return null;
        return switch (val) {
            .integer => |v| v,
            else => null,
        };
    }

    /// Get a text value by column name.
    pub fn getText(self: *const Row, column_name: []const u8) ?[]const u8 {
        const val = self.get(column_name) orelse return null;
        return switch (val) {
            .text => |v| v,
            else => null,
        };
    }

    pub fn deinit(self: *Row) void {
        // Free duped text/blob values
        for (self.values) |val| {
            switch (val) {
                .text => |v| self.allocator.free(v),
                .blob => |v| self.allocator.free(v),
                else => {},
            }
        }
        // Free duped column names
        for (self.columns) |col| {
            self.allocator.free(col);
        }
        self.allocator.free(self.values);
        self.allocator.free(self.columns);
    }
};

/// Result of a query — holds rows that must be freed by the caller.
pub const QueryResult = struct {
    rows: []Row,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *QueryResult) void {
        for (self.rows) |*row| {
            var r = row.*;
            r.deinit();
        }
        self.allocator.free(self.rows);
    }
};

/// SQLite prepared statement wrapper.
pub const Statement = struct {
    stmt: *c.sqlite3_stmt,
    db: *Database,

    /// Bind an integer parameter (1-indexed).
    pub fn bindInt(self: *Statement, index: c_int, value: i64) SqliteError!void {
        const rc = c.sqlite3_bind_int64(self.stmt, index, value);
        if (rc != c.SQLITE_OK) return mapError(rc);
    }

    /// Bind a text parameter (1-indexed).
    pub fn bindText(self: *Statement, index: c_int, value: []const u8) SqliteError!void {
        const rc = c.sqlite3_bind_text(
            self.stmt,
            index,
            value.ptr,
            @intCast(value.len),
            c.SQLITE_TRANSIENT,
        );
        if (rc != c.SQLITE_OK) return mapError(rc);
    }

    /// Bind a null parameter (1-indexed).
    pub fn bindNull(self: *Statement, index: c_int) SqliteError!void {
        const rc = c.sqlite3_bind_null(self.stmt, index);
        if (rc != c.SQLITE_OK) return mapError(rc);
    }

    /// Bind a float parameter (1-indexed).
    pub fn bindFloat(self: *Statement, index: c_int, value: f64) SqliteError!void {
        const rc = c.sqlite3_bind_double(self.stmt, index, value);
        if (rc != c.SQLITE_OK) return mapError(rc);
    }

    /// Execute the statement (for INSERT/UPDATE/DELETE). Returns number of changes.
    pub fn exec(self: *Statement) SqliteError!usize {
        const rc = c.sqlite3_step(self.stmt);
        if (rc != c.SQLITE_DONE and rc != c.SQLITE_ROW) return mapError(rc);
        return @intCast(c.sqlite3_changes(self.db.db));
    }

    /// Step the statement — returns true if there is a row available.
    pub fn step(self: *Statement) SqliteError!bool {
        const rc = c.sqlite3_step(self.stmt);
        if (rc == c.SQLITE_ROW) return true;
        if (rc == c.SQLITE_DONE) return false;
        return mapError(rc);
    }

    /// Get the number of columns in the result.
    pub fn columnCount(self: *const Statement) usize {
        return @intCast(c.sqlite3_column_count(self.stmt));
    }

    /// Get column name by index.
    pub fn columnName(self: *const Statement, index: usize) []const u8 {
        const name_ptr = c.sqlite3_column_name(self.stmt, @intCast(index));
        if (name_ptr) |p| {
            return std.mem.span(p);
        }
        return "";
    }

    /// Get a column value by index.
    pub fn columnValue(self: *const Statement, allocator: std.mem.Allocator, index: usize) !Value {
        const idx: c_int = @intCast(index);
        const col_type = c.sqlite3_column_type(self.stmt, idx);
        return switch (col_type) {
            c.SQLITE_INTEGER => .{ .integer = c.sqlite3_column_int64(self.stmt, idx) },
            c.SQLITE_FLOAT => .{ .float = c.sqlite3_column_double(self.stmt, idx) },
            c.SQLITE_TEXT => blk: {
                const text_ptr = c.sqlite3_column_text(self.stmt, idx);
                const text_len: usize = @intCast(c.sqlite3_column_bytes(self.stmt, idx));
                if (text_ptr) |p| {
                    break :blk .{ .text = try allocator.dupe(u8, p[0..text_len]) };
                }
                break :blk .null_val;
            },
            c.SQLITE_BLOB => blk: {
                const blob_ptr = c.sqlite3_column_blob(self.stmt, idx);
                const blob_len: usize = @intCast(c.sqlite3_column_bytes(self.stmt, idx));
                if (blob_ptr) |p| {
                    const bytes: [*]const u8 = @ptrCast(p);
                    break :blk .{ .blob = try allocator.dupe(u8, bytes[0..blob_len]) };
                }
                break :blk .null_val;
            },
            else => .null_val,
        };
    }

    /// Reset the statement for re-execution.
    pub fn reset(self: *Statement) SqliteError!void {
        const rc = c.sqlite3_reset(self.stmt);
        if (rc != c.SQLITE_OK) return mapError(rc);
    }

    /// Finalize (destroy) the statement.
    pub fn finalize(self: *Statement) void {
        _ = c.sqlite3_finalize(self.stmt);
    }
};

/// SQLite database connection.
pub const Database = struct {
    db: *c.sqlite3,

    /// Open a database file. Use ":memory:" for in-memory database.
    pub fn open(path: [*:0]const u8) SqliteError!Database {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path, &db);
        if (rc != c.SQLITE_OK) {
            if (db) |d| _ = c.sqlite3_close(d);
            return error.CantOpen;
        }
        return .{ .db = db.? };
    }

    /// Close the database connection.
    pub fn close(self: *Database) void {
        _ = c.sqlite3_close(self.db);
    }

    /// Execute a SQL statement that returns no rows (CREATE, INSERT, UPDATE, DELETE).
    pub fn exec(self: *Database, sql: [*:0]const u8) SqliteError!void {
        var err_msg: ?[*:0]u8 = null;
        const rc = c.sqlite3_exec(self.db, sql, null, null, &err_msg);
        if (err_msg) |msg| {
            std.debug.print("SQLite error: {s}\n", .{msg});
            c.sqlite3_free(msg);
        }
        if (rc != c.SQLITE_OK) return mapError(rc);
    }

    /// Prepare a SQL statement for execution with parameter binding.
    pub fn prepare(self: *Database, sql: [*:0]const u8) SqliteError!Statement {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return mapError(rc);
        return .{ .stmt = stmt.?, .db = self };
    }

    /// Execute a query and return all rows.
    pub fn query(self: *Database, allocator: std.mem.Allocator, sql: [*:0]const u8) !QueryResult {
        var stmt = try self.prepare(sql);
        defer stmt.finalize();

        var rows: std.ArrayList(Row) = .empty;
        errdefer {
            for (rows.items) |*row| {
                var r = row.*;
                r.deinit();
            }
            rows.deinit(allocator);
        }

        const col_count = stmt.columnCount();

        while (try stmt.step()) {
            // Extract column names
            var columns = try allocator.alloc([]const u8, col_count);
            errdefer allocator.free(columns);
            for (0..col_count) |i| {
                columns[i] = try allocator.dupe(u8, stmt.columnName(i));
            }

            // Extract values
            var values = try allocator.alloc(Value, col_count);
            errdefer allocator.free(values);
            for (0..col_count) |i| {
                values[i] = try stmt.columnValue(allocator, i);
            }

            try rows.append(allocator, .{
                .values = values,
                .columns = columns,
                .allocator = allocator,
            });
        }

        return .{
            .rows = try rows.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }

    /// Get the rowid of the last inserted row.
    pub fn lastInsertRowId(self: *const Database) i64 {
        return c.sqlite3_last_insert_rowid(self.db);
    }

    /// Get the number of rows changed by the last INSERT/UPDATE/DELETE.
    pub fn changes(self: *const Database) usize {
        return @intCast(c.sqlite3_changes(self.db));
    }
};

fn mapError(rc: c_int) SqliteError {
    return switch (rc) {
        c.SQLITE_BUSY, c.SQLITE_LOCKED => error.Busy,
        c.SQLITE_CONSTRAINT => error.Constraint,
        c.SQLITE_MISUSE => error.Misuse,
        c.SQLITE_NOMEM => error.OutOfMemory,
        c.SQLITE_CANTOPEN => error.CantOpen,
        else => error.SqlError,
    };
}
