const std = @import("std");
const testing = std.testing;
const Browser = @import("main").Browser;
const helpers = @import("test_page_render_helpers.zig");

test "test_page render - flex-container background and border" {
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

    const flex_container_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "flex-container", null);
    try testing.expect(flex_container_layout != null);

    if (flex_container_layout) |layout| {
        // 验证位置
        try testing.expect(layout.y > 0);

        // 验证背景色 #fff9c4 (RGB: 255, 249, 196)
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 255, 249, 196, 30);
        try testing.expect(found_bg);

        // 验证边框颜色 #fbc02d (RGB: 251, 192, 45)
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_found = helpers.checkColorInRegion(pixels, width, height, @as(u32, @intFromFloat(layout.x)), border_search_top_y, @as(u32, @intFromFloat(layout.x + layout.width)), @as(u32, @intFromFloat(layout.y + 5)), 251, 192, 45, 60);
        try testing.expect(border_found);
    }
}

// 测试：验证 flex-item 的背景色
// flex-item 应该有黄色背景（background-color: #fff59d）
test "test_page render - flex-item background" {
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

    // flex-item 在 flex-container 内部
    const flex_container_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "flex-container", null);
    try testing.expect(flex_container_layout != null);

    if (flex_container_layout) |container_layout| {
        // 在 flex-container 内部搜索 flex-item 背景色 #fff59d (RGB: 255, 245, 157)
        const found_item = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(container_layout.x)),
            @as(u32, @intFromFloat(container_layout.y)),
            @as(u32, @intFromFloat(container_layout.x + container_layout.width)),
            @as(u32, @intFromFloat(container_layout.y + container_layout.height)),
            255,
            245,
            157,
            30,
        );
        try testing.expect(found_item);
    }
}

// 测试：验证 grid-container 的背景色和边框
// grid-container 应该有青色背景（background-color: #e0f2f1）和青色边框（border: 2px solid #009688）
test "test_page render - grid-container background and border" {
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

    const grid_container_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "grid-container", null);
    try testing.expect(grid_container_layout != null);

    if (grid_container_layout) |layout| {
        // 验证位置
        try testing.expect(layout.y > 0);

        // 验证背景色 #e0f2f1 (RGB: 224, 242, 241)
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 224, 242, 241, 30);
        try testing.expect(found_bg);

        // 验证边框颜色 #009688 (RGB: 0, 150, 136)
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_found = helpers.checkColorInRegion(pixels, width, height, @as(u32, @intFromFloat(layout.x)), border_search_top_y, @as(u32, @intFromFloat(layout.x + layout.width)), @as(u32, @intFromFloat(layout.y + 5)), 0, 150, 136, 60);
        try testing.expect(border_found);
    }
}

// 测试：验证 grid-item 的背景色
// grid-item 应该有浅青色背景（background-color: #b2dfdb）
test "test_page render - grid-item background" {
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

    // grid-item 在 grid-container 内部
    const grid_container_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "grid-container", null);
    try testing.expect(grid_container_layout != null);

    if (grid_container_layout) |container_layout| {
        // 在 grid-container 内部搜索 grid-item 背景色 #b2dfdb (RGB: 178, 223, 219)
        const found_item = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(container_layout.x)),
            @as(u32, @intFromFloat(container_layout.y)),
            @as(u32, @intFromFloat(container_layout.x + container_layout.width)),
            @as(u32, @intFromFloat(container_layout.y + container_layout.height)),
            178,
            223,
            219,
            30,
        );
        try testing.expect(found_item);
    }
}

// 测试：验证 text-styles 的背景色和边框
// text-styles 应该有粉色背景（background-color: #fce4ec）和粉色边框（border: 2px solid #e91e63）
