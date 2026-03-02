//! Barrel re-export for all built-in middleware.
//!
//! Usage:
//!   const mw = @import("framework/framework.zig").middlewares;
//!   try app.use(mw.logger);
//!   try app.use(mw.cors);
//!   try app.use(mw.compression);

pub const logger = @import("logger.zig").logger;

pub const cors_mod = @import("cors.zig");
pub const cors = cors_mod.cors;
pub const corsWithOptions = cors_mod.withOptions;
pub const CorsOptions = cors_mod.CorsOptions;

pub const compression_mod = @import("compression.zig");
pub const compression = compression_mod.compression;

pub const multer_mod = @import("multer.zig");
pub const multer = multer_mod.multer;
pub const multerWithConfig = multer_mod.withConfig;
pub const MulterConfig = multer_mod.MulterConfig;
