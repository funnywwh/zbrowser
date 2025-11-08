const std = @import("std");
const testing = std.testing;
const backend = @import("backend");
const cpu_backend = @import("cpu_backend");

test "CpuRenderBackend init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const render_backend = try cpu_backend.CpuRenderBackend.init(allocator, 800, 600);
    defer render_backend.deinit();

    try testing.expectEqual(@as(u32, 800), render_backend.getWidth());
    try testing.expectEqual(@as(u32, 600), render_backend.getHeight());
}

test "CpuRenderBackend fillRect - basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const render_backend = try cpu_backend.CpuRenderBackend.init(allocator, 100, 100);
    defer render_backend.deinit();

    const rect = backend.Rect.init(10, 10, 50, 50);
    const color = backend.Color.rgb(255, 0, 0); // 红色
    render_backend.base.fillRect(rect, color);

    // 获取像素数据
    const pixels = try render_backend.getPixels(allocator);
    defer allocator.free(pixels);

    // 检查填充区域内的像素是否为红色
    // 简化测试：检查中心点
    const center_x: u32 = 35;
    const center_y: u32 = 35;
    const index = (center_y * 100 + center_x) * 4;
    try testing.expectEqual(@as(u8, 255), pixels[index]); // R
    try testing.expectEqual(@as(u8, 0), pixels[index + 1]); // G
    try testing.expectEqual(@as(u8, 0), pixels[index + 2]); // B
    try testing.expectEqual(@as(u8, 255), pixels[index + 3]); // A
}

test "CpuRenderBackend fillRect - boundary" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const render_backend = try cpu_backend.CpuRenderBackend.init(allocator, 100, 100);
    defer render_backend.deinit();

    // 填充整个画布
    const rect = backend.Rect.init(0, 0, 100, 100);
    const color = backend.Color.rgb(0, 255, 0); // 绿色
    render_backend.base.fillRect(rect, color);

    const pixels = try render_backend.getPixels(allocator);
    defer allocator.free(pixels);

    // 检查所有像素是否为绿色
    var i: usize = 0;
    while (i < pixels.len) : (i += 4) {
        try testing.expectEqual(@as(u8, 0), pixels[i]); // R
        try testing.expectEqual(@as(u8, 255), pixels[i + 1]); // G
        try testing.expectEqual(@as(u8, 0), pixels[i + 2]); // B
        try testing.expectEqual(@as(u8, 255), pixels[i + 3]); // A
    }
}

test "CpuRenderBackend fillRect - empty rect" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const render_backend = try cpu_backend.CpuRenderBackend.init(allocator, 100, 100);
    defer render_backend.deinit();

    // 空矩形（宽度或高度为0）
    const rect = backend.Rect.init(10, 10, 0, 50);
    const color = backend.Color.rgb(255, 0, 0);
    render_backend.base.fillRect(rect, color);

    // 应该不会崩溃，但也不会绘制任何内容
    const pixels = try render_backend.getPixels(allocator);
    defer allocator.free(pixels);

    // 检查背景仍然是白色
    const index = (50 * 100 + 50) * 4;
    try testing.expectEqual(@as(u8, 255), pixels[index]); // R (白色背景)
    try testing.expectEqual(@as(u8, 255), pixels[index + 1]); // G
    try testing.expectEqual(@as(u8, 255), pixels[index + 2]); // B
}

test "CpuRenderBackend fillRect - out of bounds" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const render_backend = try cpu_backend.CpuRenderBackend.init(allocator, 100, 100);
    defer render_backend.deinit();

    // 超出边界的矩形
    const rect = backend.Rect.init(50, 50, 100, 100);
    const color = backend.Color.rgb(255, 0, 0);
    render_backend.base.fillRect(rect, color);

    // 应该只绘制在边界内的部分
    const pixels = try render_backend.getPixels(allocator);
    defer allocator.free(pixels);

    // 检查边界内的像素
    const index = (75 * 100 + 75) * 4;
    try testing.expectEqual(@as(u8, 255), pixels[index]); // R (红色)
    try testing.expectEqual(@as(u8, 0), pixels[index + 1]); // G
    try testing.expectEqual(@as(u8, 0), pixels[index + 2]); // B
}

test "CpuRenderBackend initial background - white" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const render_backend = try cpu_backend.CpuRenderBackend.init(allocator, 100, 100);
    defer render_backend.deinit();

    const pixels = try render_backend.getPixels(allocator);
    defer allocator.free(pixels);

    // 检查所有像素都是白色（初始背景）
    var i: usize = 0;
    while (i < pixels.len) : (i += 4) {
        try testing.expectEqual(@as(u8, 255), pixels[i]); // R
        try testing.expectEqual(@as(u8, 255), pixels[i + 1]); // G
        try testing.expectEqual(@as(u8, 255), pixels[i + 2]); // B
        try testing.expectEqual(@as(u8, 255), pixels[i + 3]); // A
    }
}
