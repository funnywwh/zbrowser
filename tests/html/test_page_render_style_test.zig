const std = @import("std");
const testing = std.testing;
const Browser = @import("main").Browser;
const helpers = @import("test_page_render_helpers.zig");

test "test_page render - text-styles background and border" {
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

    const text_styles_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "text-styles", null);
    try testing.expect(text_styles_layout != null);

    if (text_styles_layout) |layout| {
        // 验证背景色 #fce4ec (RGB: 252, 228, 236)
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 252, 228, 236, 30);
        try testing.expect(found_bg);

        // 验证边框颜色 #e91e63 (RGB: 233, 30, 99)
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_found = helpers.checkColorInRegion(pixels, width, height, @as(u32, @intFromFloat(layout.x)), border_search_top_y, @as(u32, @intFromFloat(layout.x + layout.width)), @as(u32, @intFromFloat(layout.y + 5)), 233, 30, 99, 60);
        try testing.expect(border_found);
    }
}

// 测试：验证 text-large 的文本颜色
// text-large 应该有深粉色文本（color: #c2185b），字体大小32px
test "test_page render - text-large color" {
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

    const text_styles_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "text-styles", null);
    try testing.expect(text_styles_layout != null);

    if (text_styles_layout) |layout| {
        // text-large 文本颜色是 #c2185b (RGB: 194, 24, 91)
        // 在 text-styles 内部搜索
        const found_text = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x)),
            @as(u32, @intFromFloat(layout.y)),
            @as(u32, @intFromFloat(layout.x + layout.width)),
            @as(u32, @intFromFloat(layout.y + layout.height / 3.0)), // 只搜索前1/3（text-large在顶部）
            194,
            24,
            91,
            30,
        );
        try testing.expect(found_text);
    }
}

// 测试：验证 multilang 的背景色和边框
// multilang 应该有蓝色背景（background-color: #e8eaf6）和蓝色边框（border: 2px solid #3f51b5）
test "test_page render - multilang background and border" {
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

    const multilang_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "multilang", null);
    try testing.expect(multilang_layout != null);

    if (multilang_layout) |layout| {
        // 验证背景色 #e8eaf6 (RGB: 232, 234, 246)
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 232, 234, 246, 30);
        try testing.expect(found_bg);

        // 验证边框颜色 #3f51b5 (RGB: 63, 81, 181)
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_found = helpers.checkColorInRegion(pixels, width, height, @as(u32, @intFromFloat(layout.x)), border_search_top_y, @as(u32, @intFromFloat(layout.x + layout.width)), @as(u32, @intFromFloat(layout.y + 5)), 63, 81, 181, 60);
        try testing.expect(border_found);
    }
}

// 测试：验证 border-test 的背景色、边框和圆角
// border-test 应该有黄色背景（background-color: #fff8e1）、橙色边框（border: 5px solid #ff6f00）和圆角（border-radius: 10px）
test "test_page render - border-test background border and radius" {
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

    const border_test_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "border-test", null);
    try testing.expect(border_test_layout != null);

    if (border_test_layout) |layout| {
        // 验证背景色 #fff8e1 (RGB: 255, 248, 225)
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 255, 248, 225, 30);
        try testing.expect(found_bg);

        // 验证边框颜色 #ff6f00 (RGB: 255, 111, 0)，边框宽度是5px
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_found = helpers.checkColorInRegion(pixels, width, height, @as(u32, @intFromFloat(layout.x)), border_search_top_y, @as(u32, @intFromFloat(layout.x + layout.width)), @as(u32, @intFromFloat(layout.y + 10)), 255, 111, 0, 60);
        try testing.expect(border_found);
    }
}

// 测试：验证 nested 的背景色和边框
// nested 应该有浅绿色背景（background-color: #f1f8e9）和绿色边框（border: 2px solid #689f38）
test "test_page render - nested background and border" {
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

    const nested_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "nested", null);
    try testing.expect(nested_layout != null);

    if (nested_layout) |layout| {
        // 验证背景色 #f1f8e9 (RGB: 241, 248, 233)
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 241, 248, 233, 30);
        try testing.expect(found_bg);

        // 验证边框颜色 #689f38 (RGB: 104, 159, 56)
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_found = helpers.checkColorInRegion(pixels, width, height, @as(u32, @intFromFloat(layout.x)), border_search_top_y, @as(u32, @intFromFloat(layout.x + layout.width)), @as(u32, @intFromFloat(layout.y + 5)), 104, 159, 56, 60);
        try testing.expect(border_found);
    }
}

// 测试：验证 nested-level-1 的背景色
// nested-level-1 应该有浅绿色背景（background-color: #dcedc8）
test "test_page render - nested-level-1 background" {
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

    const nested_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "nested", null);
    try testing.expect(nested_layout != null);

    if (nested_layout) |container_layout| {
        // nested-level-1 在 nested 内部
        // 背景色是 #dcedc8 (RGB: 220, 237, 200)
        const found_level1 = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(container_layout.x)),
            @as(u32, @intFromFloat(container_layout.y)),
            @as(u32, @intFromFloat(container_layout.x + container_layout.width)),
            @as(u32, @intFromFloat(container_layout.y + container_layout.height)),
            220,
            237,
            200,
            30,
        );
        try testing.expect(found_level1);
    }
}

// 测试：验证 relative-box 的位置（相对定位）
// relative-box 应该有相对偏移（left: 20px, top: 10px）
