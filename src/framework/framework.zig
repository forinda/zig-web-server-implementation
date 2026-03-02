//! Zig Web Framework — Express.js-like HTTP framework for Zig 0.16.0-dev.
//!
//! Usage:
//!   const fw = @import("framework/framework.zig");
//!   var app = fw.App(MyState).init(allocator, io, &state);
//!   try app.get("/hello", myHandler);
//!   try app.use(fw.middlewares.logger);
//!   try app.listen(8080);
//!
//! Adapters (optional, import explicitly):
//!   const sqlite = @import("framework/adapters/sqlite.zig");
//!   // Build with: zig build -Dsqlite=true

pub const App = @import("app.zig").App;
pub const context = @import("context.zig");
pub const Context = context.Context;
pub const utils = @import("utils/utils.zig");
pub const StatusCode = utils.StatusCode;
pub const Router = @import("router.zig").Router;
pub const Params = context.Params;
pub const HandlerFn = context.HandlerFn;
pub const MiddlewareFn = context.MiddlewareFn;
pub const middlewares = @import("middlewares/middlewares.zig");
/// Backwards-compat alias
pub const middleware = middlewares;
pub const multipart = utils.multipart;
pub const Env = utils.Env;
