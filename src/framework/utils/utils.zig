//! Framework utilities — reusable helpers for HTTP status codes, multipart parsing,
//! gzip compression, and header parsing.
//!
//! Usage:
//!   const utils = @import("framework/utils/utils.zig");
//!   const StatusCode = utils.StatusCode;
//!   const compressed = try utils.gzipCompress(allocator, data);

pub const status = @import("status.zig");
pub const StatusCode = status.StatusCode;

pub const multipart = @import("multipart.zig");
pub const Part = multipart.Part;

pub const compression = @import("compression.zig");
pub const gzipCompress = compression.gzipCompress;

pub const headers = @import("headers.zig");
pub const findHeaderValue = headers.findHeaderValue;

pub const env = @import("env.zig");
pub const Env = env.Env;
