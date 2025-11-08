const std = @import("std");
const testing = std.testing;
const backend = @import("backend");

// 测试抽象渲染后端接口的基本功能
// 注意：这是接口测试，实际实现会在cpu_backend.zig中

test "RenderBackend interface exists" {
    // 测试接口是否存在
    // 这是一个占位测试，确保模块可以正确导入
    _ = backend;
    try testing.expect(true);
}
