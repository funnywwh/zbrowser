const std = @import("std");
const testing = std.testing;
const png = @import("png");

test "PNG encoder interface exists" {
    // 测试接口是否存在
    // 这是一个占位测试，确保模块可以正确导入
    _ = png;
    try testing.expect(true);
}
