const std = @import("std");
const testing = std.testing;
const Browser = @import("main").Browser;
const helpers = @import("test_page_render_helpers.zig");

// 测试：完整验证 block-test div 元素
// 包括位置、大小、背景色、边框、内部元素
test "test_page render - block-test div complete verification" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try helpers.readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try helpers.extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    var browser = try Browser.init(allocator);
    defer browser.deinit();

    try browser.loadHTML(html_content);
    try browser.addStylesheet(css_content);

    const width: u32 = 1200;
    const height: u32 = 3000;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在
    try helpers.verifyH1Exists(&browser, allocator);

    // 获取 block-test div 的布局信息
    const block_test_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "block-test", null);
    try testing.expect(block_test_layout != null);

    if (block_test_layout) |layout| {
        std.debug.print("\n=== Block-Test Div Layout Info ===\n", .{});
        std.debug.print("Content Box:\n", .{});
        std.debug.print("  x: {d:.2}\n", .{layout.x});
        std.debug.print("  y: {d:.2}\n", .{layout.y});
        std.debug.print("  width: {d:.2}\n", .{layout.width});
        std.debug.print("  height: {d:.2}\n", .{layout.height});
        std.debug.print("Margins:\n", .{});
        std.debug.print("  top: {d:.2}, right: {d:.2}, bottom: {d:.2}, left: {d:.2}\n", .{ layout.margin_top, layout.margin_right, layout.margin_bottom, layout.margin_left });
        std.debug.print("Borders:\n", .{});
        std.debug.print("  top: {d:.2}, right: {d:.2}, bottom: {d:.2}, left: {d:.2}\n", .{ layout.border_top, layout.border_right, layout.border_bottom, layout.border_left });
        std.debug.print("==============================\n\n", .{});

        // 1. 验证位置：应该在 h1 下方
        const h1_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "h1", null, null);
        if (h1_layout) |h1| {
            const h1_bottom = h1.y + h1.height + h1.margin_bottom + h1.border_bottom;
            const block_test_top = layout.y - layout.margin_top - layout.border_top;
            std.debug.print("H1 bottom: {d:.2}, Block-test top: {d:.2}\n", .{ h1_bottom, block_test_top });
            try testing.expect(block_test_top >= h1_bottom - 5.0); // 允许5像素误差
        }

        // 2. 验证背景色：应该是 #e3f2fd (RGB: 227, 242, 253)
        const found_bg = helpers.verifyElementPositionAndSize(
            pixels,
            width,
            height,
            layout.x,
            layout.y,
            layout.width,
            layout.height,
            227,
            242,
            253,
            5, // 容差
        );
        try testing.expect(found_bg);

        // 3. 验证边框：应该是 #2196f3 (RGB: 33, 150, 243)，2px
        // 检查顶部边框
        const border_top_y = @as(u32, @intFromFloat(layout.y - layout.border_top));
        const border_found = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x - layout.border_left)),
            border_top_y,
            @as(u32, @intFromFloat(layout.x + layout.width + layout.border_right)),
            border_top_y + @as(u32, @intFromFloat(layout.border_top)) + 1,
            33,
            150,
            243,
            20, // 容差
        );
        try testing.expect(border_found);

        // 4. 验证内部 h1 元素：应该在 block-test div 内部
        // block-test h1 文本颜色是 #1976d2 (RGB: 25, 118, 210)
        // 注意：可能有多个 h1，需要找到 block-test 内部的 h1
        // 这里先验证 block-test 内部有蓝色文本
        const found_h1_text = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x)),
            @as(u32, @intFromFloat(layout.y)),
            @as(u32, @intFromFloat(layout.x + layout.width)),
            @as(u32, @intFromFloat(layout.y + layout.height / 2.0)), // 上半部分
            25,
            118,
            210,
            30,
        );
        try testing.expect(found_h1_text);

        // 5. 验证大小：应该有合理的宽度和高度
        try testing.expect(layout.width > 500); // 至少500像素宽
        try testing.expect(layout.height > 100); // 至少100像素高

        // 6. 验证边框宽度：应该是 2px
        try testing.expect(layout.border_top == 2.0);
        try testing.expect(layout.border_bottom == 2.0);
        try testing.expect(layout.border_left == 2.0);
        try testing.expect(layout.border_right == 2.0);
    }
}

