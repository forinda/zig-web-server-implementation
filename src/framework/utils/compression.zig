const std = @import("std");
const Io = std.Io;

/// Compress data using gzip (Huffman-only deflate for small memory footprint).
pub fn gzipCompress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const flate = std.compress.flate;
    const Writer = Io.Writer;

    // Output writer with pre-allocated capacity
    var aw: Writer.Allocating = try .initCapacity(allocator, @max(input.len, 64));
    errdefer aw.deinit();

    // Working buffer for Huffman compressor
    var work_buf: [4096]u8 = undefined;

    // Create Huffman compressor with gzip container
    var h: flate.Compress.Huffman = try .init(&aw.writer, &work_buf, .gzip);

    // Write input data
    try h.writer.writeAll(input);

    // Flush — writes final deflate block + gzip footer (CRC32 + size)
    try h.writer.flush();

    // Extract compressed bytes
    return try aw.toOwnedSlice();
}

// ---- Tests ----

test "gzipCompress round-trip" {
    const allocator = std.testing.allocator;
    const flate = std.compress.flate;
    const Reader = Io.Reader;

    const input = "Hello, this is a test string for gzip compression! " ** 20;
    const compressed = try gzipCompress(allocator, input);
    defer allocator.free(compressed);

    // Compressed should be smaller than input
    try std.testing.expect(compressed.len < input.len);

    // Decompress and verify
    var input_reader: Reader = .fixed(compressed);
    var decomp_buf: [flate.max_window_len * 2]u8 = undefined;
    var decomp: flate.Decompress = .init(&input_reader, .gzip, &decomp_buf);
    const decompressed = try decomp.reader.readAllAlloc(allocator, input.len + 1);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}
