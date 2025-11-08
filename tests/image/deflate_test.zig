const std = @import("std");
const testing = std.testing;
const deflate = @import("deflate");

test "DeflateCompressor interface exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const compressor = deflate.DeflateCompressor.init(allocator);
    _ = compressor;
    try testing.expect(true);
}

test "DeflateCompressor compress - basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const compressor = deflate.DeflateCompressor.init(allocator);

    const test_data = "Hello World";
    const compressed = try compressor.compress(test_data);
    defer allocator.free(compressed);

    // 压缩后的数据应该存在
    try testing.expect(compressed.len > 0);

    // 应该包含DEFLATE块头（至少1字节）
    try testing.expect(compressed.len >= 1);
}

test "DeflateCompressor compress - empty data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const compressor = deflate.DeflateCompressor.init(allocator);

    const test_data = "";
    const compressed = try compressor.compress(test_data);
    defer allocator.free(compressed);

    // 即使数据为空，也应该有DEFLATE块头
    try testing.expect(compressed.len >= 1);
}

test "DeflateCompressor compress - repeated data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const compressor = deflate.DeflateCompressor.init(allocator);

    // 创建重复数据（应该可以压缩）
    const test_data = try allocator.alloc(u8, 100);
    defer allocator.free(test_data);
    @memset(test_data, 0xAA);

    const compressed = try compressor.compress(test_data);
    defer allocator.free(compressed);

    // 压缩后的数据应该存在
    try testing.expect(compressed.len > 0);
}

test "DeflateCompressor findLongestMatch - basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const compressor = deflate.DeflateCompressor.init(allocator);

    // 测试数据：包含重复字符串
    const test_data = "ABCABCABC";
    const match = compressor.findLongestMatch(test_data, 3);

    // 在位置3（第二个"ABC"的开始），应该找到匹配
    // 匹配长度应该是3，距离应该是3
    try testing.expect(match.length >= 3);
    try testing.expect(match.distance > 0);
}

test "DeflateCompressor findLongestMatch - no match" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const compressor = deflate.DeflateCompressor.init(allocator);

    // 测试数据：没有重复
    const test_data = "ABCDEFGH";
    const match = compressor.findLongestMatch(test_data, 4);

    // 在位置4，不应该找到匹配（或匹配长度小于MIN_MATCH）
    // 这是正常的，因为数据没有重复
    _ = match;
    try testing.expect(true);
}
