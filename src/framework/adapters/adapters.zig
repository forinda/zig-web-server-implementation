//! Framework adapters — database and external service integrations.
//!
//! Adapters are NOT auto-imported by framework.zig to avoid mandatory
//! dependencies. Import them explicitly when needed:
//!
//!   const sqlite = @import("framework/adapters/sqlite.zig");
//!   var db = try sqlite.Database.open("myapp.db");
//!
//! To enable SQLite, build with: zig build -Dsqlite=true
//! Requires: libsqlite3-dev (apt) or sqlite3 (brew)

pub const sqlite = @import("sqlite.zig");
