const std = @import("std");
const testing = std.testing;
const Browser = @import("main").Browser;
const helpers = @import("test_page_render_helpers.zig");

test "test_page render - float-container background and border" {
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

    try helpers.verifyH1Exists(&browser, allocator);

    const float_container_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "float-container", null);
    try testing.expect(float_container_layout != null);

    if (float_container_layout) |layout| {
        // 验证位置
        try testing.expect(layout.y > 0);
        try testing.expect(layout.y < @as(f32, @floatFromInt(height)));

        // 验证背景色 #e8f5e9 (RGB: 232, 245, 233)
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 232, 245, 233, 30);
        try testing.expect(found_bg);

        // 验证边框颜色 #4caf50 (RGB: 76, 175, 80)
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_search_bottom_y = @as(u32, @intFromFloat(layout.y + layout.height + layout.border_bottom + 5));
        const border_found = helpers.checkColorInRegion(pixels, width, height, @as(u32, @intFromFloat(layout.x)), border_search_top_y, @as(u32, @intFromFloat(layout.x + layout.width)), border_search_bottom_y, 76, 175, 80, 60);
        try testing.expect(border_found);
    }
}

// 测试：验证 float-left 的背景色和位置
// float-left 应该有浅绿色背景（background-color: #c8e6c9），宽度200px，左浮动
test "test_page render - float-left background and position" {
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

    try helpers.verifyH1Exists(&browser, allocator);

    const float_left_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "float-left", null);
    try testing.expect(float_left_layout != null);

    if (float_left_layout) |layout| {
        // 验证位置：左浮动应该在左侧
        try testing.expect(layout.x < @as(f32, @floatFromInt(width)) / 2.0);

        // 验证大小：宽度应该是 200px
        try testing.expect(layout.width >= 180.0);
        try testing.expect(layout.width <= 220.0);

        // 验证背景色 #c8e6c9 (RGB: 200, 230, 201)
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 200, 230, 201, 30);
        try testing.expect(found_bg);
    }
}

// 测试：验证 float-right 的背景色和位置
// float-right 应该有绿色背景（background-color: #a5d6a7），宽度200px，右浮动
test "test_page render - float-right background and position" {
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

    try helpers.verifyH1Exists(&browser, allocator);

    const float_right_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "float-right", null);
    try testing.expect(float_right_layout != null);

    if (float_right_layout) |layout| {
        // 验证位置：右浮动应该在右侧
        try testing.expect(layout.x > @as(f32, @floatFromInt(width)) / 2.0);

        // 验证大小：宽度应该是 200px
        try testing.expect(layout.width >= 180.0);
        try testing.expect(layout.width <= 220.0);

        // 验证背景色 #a5d6a7 (RGB: 165, 214, 167)
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 165, 214, 167, 30);
        try testing.expect(found_bg);
    }
}

// 测试：验证 flex-container 的背景色和边框
// flex-container 应该有黄色背景（background-color: #fff9c4）和黄色边框（border: 2px solid #fbc02d）
