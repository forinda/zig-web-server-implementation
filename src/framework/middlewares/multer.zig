const std = @import("std");
const Context = @import("../context.zig").Context;
const multipart = @import("../utils/multipart.zig");

/// Multer configuration options.
pub const MulterConfig = struct {
    /// Maximum file size in bytes (0 = unlimited).
    max_file_size: usize = 0,
    /// Maximum total upload size in bytes (0 = unlimited).
    max_total_size: usize = 50 * 1024 * 1024,
};

/// Default multer middleware — parses multipart/form-data and attaches parts to context.
/// Subsequent handlers can access parts via ctx.getParts().
/// Non-multipart requests pass through without parsing.
pub fn multer(ctx: *Context) anyerror!void {
    return multerHandler(.{}, ctx);
}

/// Create a multer middleware with custom configuration.
pub fn withConfig(comptime config: MulterConfig) *const fn (*Context) anyerror!void {
    return struct {
        fn handler(ctx: *Context) anyerror!void {
            return multerHandler(config, ctx);
        }
    }.handler;
}

fn multerHandler(comptime config: MulterConfig, ctx: *Context) anyerror!void {
    const content_type = ctx.getContentType() orelse {
        // No content-type — pass through
        return ctx.next();
    };

    // Only parse multipart/form-data requests
    if (std.mem.indexOf(u8, content_type, "multipart/form-data") == null) {
        return ctx.next();
    }

    const boundary = multipart.extractBoundary(content_type) orelse {
        return ctx.next();
    };

    // Copy boundary since it points into the cached content-type buffer
    var boundary_copy_buf: [256]u8 = undefined;
    if (boundary.len > boundary_copy_buf.len) {
        return ctx.next();
    }
    @memcpy(boundary_copy_buf[0..boundary.len], boundary);
    const boundary_copy = boundary_copy_buf[0..boundary.len];

    // Read body
    const body_data = ctx.body() catch {
        return ctx.next();
    };

    // Check total size limit
    if (config.max_total_size > 0 and body_data.len > config.max_total_size) {
        return ctx.sendError(@import("../utils/status.zig").StatusCode.payload_too_large, "Upload too large");
    }

    // Parse multipart
    const parts = multipart.parse(ctx.allocator, body_data, boundary_copy) catch {
        return ctx.next();
    };

    // Check individual file sizes
    if (config.max_file_size > 0) {
        for (parts) |part| {
            if (part.filename != null and part.data.len > config.max_file_size) {
                ctx.allocator.free(parts);
                return ctx.sendError(@import("../utils/status.zig").StatusCode.payload_too_large, "File too large");
            }
        }
    }

    // Attach parsed parts to context
    ctx._multer_parts = parts;

    try ctx.next();
}
