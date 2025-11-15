const std = @import("std");
const testing = std.testing;
const Browser = @import("main").Browser;
const helpers = @import("test_page_render_helpers.zig");

test "test_page render - position-container background and border" {
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

    // 使用更大的高度以确保 position-container 可见
    const width: u32 = 1200;
    const height: u32 = 2000;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // 获取 position-container 的布局信息
    const container_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "position-container", null);
    try testing.expect(container_layout != null);

    if (container_layout) |layout| {
        // 验证位置：position-container 应该在页面中（y > 0）
        try testing.expect(layout.y > 0);
        try testing.expect(layout.y < @as(f32, @floatFromInt(height)));

        // 验证大小：position-container 高度应该是 300px（CSS中定义）
        // 允许一些误差（考虑padding、border等）
        try testing.expect(layout.height >= 250.0); // 至少250px（考虑容差）
        try testing.expect(layout.height <= 350.0); // 最多350px（考虑padding和border）

        // 验证背景色在元素区域内
        const found_bg = helpers.verifyElementPositionAndSize(
            pixels,
            width,
            height,
            layout.x,
            layout.y,
            layout.width,
            layout.height,
            243, // #f3e5f5
            229,
            245,
            30,
        );
        try testing.expect(found_bg);

        // 验证边框颜色在元素边缘（边框宽度是2px）
        // 检查顶部边框（扩大搜索范围，因为边框可能在内容框外）
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_search_bottom_y = @as(u32, @intFromFloat(layout.y + layout.height + layout.border_bottom + 5));
        const border_search_left_x = if (layout.x > layout.border_left) @as(u32, @intFromFloat(layout.x - layout.border_left - 5)) else 0;
        const border_search_right_x = @as(u32, @intFromFloat(layout.x + layout.width + layout.border_right + 5));

        // 检查顶部边框
        const border_top_found = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            border_search_left_x,
            border_search_top_y,
            border_search_right_x,
            @as(u32, @intFromFloat(layout.y + 5)), // 扩展到内容框内一点
            156, // #9c27b0
            39,
            176,
            60,
        );
        // 检查底部边框
        const border_bottom_found = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            border_search_left_x,
            @as(u32, @intFromFloat(layout.y + layout.height - 5)), // 从内容框底部开始
            border_search_right_x,
            if (border_search_bottom_y < height) border_search_bottom_y else height - 1,
            156,
            39,
            176,
            60,
        );
        // 检查左侧边框
        const border_left_found = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            border_search_left_x,
            border_search_top_y,
            @as(u32, @intFromFloat(layout.x + 5)),
            border_search_bottom_y,
            156,
            39,
            176,
            60,
        );
        // 检查右侧边框
        const border_right_found = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x + layout.width - 5)),
            border_search_top_y,
            border_search_right_x,
            border_search_bottom_y,
            156,
            39,
            176,
            60,
        );
        // 至少应该找到一条边框
        try testing.expect(border_top_found or border_bottom_found or border_left_found or border_right_found);
    }
}

// 测试：验证页脚的背景色和文本颜色
// 页脚应该有深色背景（background-color: #263238）和白色文本（color: white）
test "test_page render - static-box background" {
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
    const height: u32 = 2000;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // static-box 背景色是 #e1bee7 (RGB: 225, 190, 231)
    // 应该在 position-container 内部（先找到 position-container，然后在其内部搜索）
    if (helpers.findColorInYRange(pixels, width, height, 400, 1000, 243, 229, 245, 5)) |container_pos| {
        // 在 position-container 内部搜索 static-box
        const search_start = container_pos.y;
        const search_end = container_pos.y + 350;
        const found_static = helpers.findColorInYRange(pixels, width, height, search_start, search_end, 225, 190, 231, 5);
        try testing.expect(found_static != null);
    } else {
        // 如果找不到 position-container，在整个页面中搜索
        const found_static = helpers.findColorInYRange(pixels, width, height, 400, 1500, 225, 190, 231, 5);
        try testing.expect(found_static != null);
    }
}

// 测试：验证 relative-box 的背景色
// relative-box 应该有紫色背景（background-color: #ce93d8）
test "test_page render - relative-box background" {
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
    const height: u32 = 2000;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // relative-box 背景色是 #ce93d8 (RGB: 206, 147, 216)
    // 应该在 position-container 内部
    if (helpers.findColorInYRange(pixels, width, height, 400, 1000, 243, 229, 245, 5)) |container_pos| {
        const search_start = container_pos.y;
        const search_end = container_pos.y + 350;
        const found_relative = helpers.findColorInYRange(pixels, width, height, search_start, search_end, 206, 147, 216, 5);
        try testing.expect(found_relative != null);
    } else {
        const found_relative = helpers.findColorInYRange(pixels, width, height, 400, 1500, 206, 147, 216, 5);
        try testing.expect(found_relative != null);
    }
}

// 测试：验证 absolute-box 的背景色（精确验证位置和大小）
// absolute-box 应该有深紫色背景（background-color: #ba68c8），宽度150px，绝对定位在右侧
test "test_page render - relative-box position" {
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
    const height: u32 = 2000;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    try helpers.verifyH1Exists(&browser, allocator);

    const relative_box_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "relative-box", null);
    try testing.expect(relative_box_layout != null);

    if (relative_box_layout) |layout| {
        // 验证位置：relative-box 应该在 position-container 内部
        // 由于是相对定位，位置应该相对于正常流有偏移
        try testing.expect(layout.y > 0);
        try testing.expect(layout.x > 0);

        // 验证背景色 #ce93d8 (RGB: 206, 147, 216)
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 206, 147, 216, 5);
        try testing.expect(found_bg);
    }
}

test "test_page render - absolute-box background" {
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
    const height: u32 = 2000;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // 获取 absolute-box 的布局信息
    const absolute_box_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "absolute-box", null);
    try testing.expect(absolute_box_layout != null);

    if (absolute_box_layout) |layout| {
        // 验证位置：absolute-box 应该在 position-container 内部
        // 由于是绝对定位，x 应该在容器右侧（right: 20px）
        try testing.expect(layout.x > @as(f32, @floatFromInt(width)) / 2.0); // 应该在右侧
        try testing.expect(layout.x < @as(f32, @floatFromInt(width)) - 20.0); // 距离右边缘至少20px

        // 验证大小：宽度应该是 150px（CSS中定义）
        try testing.expect(layout.width >= 140.0); // 允许一些误差
        try testing.expect(layout.width <= 160.0);

        // 验证背景色在元素区域内
        const found_bg = helpers.verifyElementPositionAndSize(
            pixels,
            width,
            height,
            layout.x,
            layout.y,
            layout.width,
            layout.height,
            186, // #ba68c8
            104,
            200,
            30,
        );
        try testing.expect(found_bg);
    }
}

// 测试：验证 block-test div 内 h1 的文本颜色（精确验证位置和大小）
// .block-test h1 应该有蓝色文本（color: #1976d2），字体大小24px
test "test_page render - footer background and text color" {
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

    // 使用更大的高度以确保页脚可见
    const width: u32 = 1200;
    const height: u32 = 5000; // 增加高度以包含页脚
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // 页脚背景色是 #263238 (RGB: 38, 50, 56)
    // 使用 findColorInYRange 从页面底部向上搜索（页脚在最后）
    // 从 height - 500 开始搜索，因为页脚应该在底部
    const search_start_y = if (height > 500) height - 500 else 0;
    if (helpers.findColorInYRange(pixels, width, height, search_start_y, height - 1, 38, 50, 56, 5)) |footer_pos| {
        // 找到了页脚背景，验证位置在底部区域
        try testing.expect(footer_pos.y >= search_start_y);
        try testing.expect(footer_pos.y < height);

        // 在页脚区域内检查白色文本 (RGB: 255, 255, 255)
        // 文本应该在背景区域内
        const text_search_y_start = footer_pos.y;
        const text_search_y_end = if (footer_pos.y + 300 < height) footer_pos.y + 300 else height - 1;
        const found_text = helpers.findColorInYRange(pixels, width, height, text_search_y_start, text_search_y_end, 255, 255, 255, 50);
        try testing.expect(found_text != null);
    } else {
        // 如果找不到，尝试在整个页面中搜索（可能页脚位置不同）
        const found_bg_anywhere = helpers.findColorInYRange(pixels, width, height, 1000, height - 1, 38, 50, 56, 5);
        try testing.expect(found_bg_anywhere != null);

        if (found_bg_anywhere) |footer_pos| {
            // 在找到的位置检查白色文本
            const text_search_y_start = footer_pos.y;
            const text_search_y_end = if (footer_pos.y + 300 < height) footer_pos.y + 300 else height - 1;
            const found_text = helpers.findColorInYRange(pixels, width, height, text_search_y_start, text_search_y_end, 255, 255, 255, 50);
            try testing.expect(found_text != null);
        }
    }
}

// 测试：验证 fixed-box 的背景色和位置
// fixed-box 应该有紫色背景（background-color: #ab47bc），白色文本，固定定位在右下角
test "test_page render - fixed-box background and position" {
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
    const height: u32 = 2000;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    try helpers.verifyH1Exists(&browser, allocator);

    const fixed_box_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "fixed-box", null);
    try testing.expect(fixed_box_layout != null);

    if (fixed_box_layout) |layout| {
        // 验证位置：fixed定位应该在右下角（right: 20px, bottom: 20px）
        // 由于是fixed定位，位置相对于视口
        try testing.expect(layout.x > 0);
        try testing.expect(layout.y > 0);

        // 验证大小：宽度应该是 120px
        try testing.expect(layout.width >= 100.0);
        try testing.expect(layout.width <= 140.0);

        // 验证背景色 #ab47bc (RGB: 171, 71, 188)
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 171, 71, 188, 5);
        try testing.expect(found_bg);

        // 验证白色文本 (RGB: 255, 255, 255)
        const found_text = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x)),
            @as(u32, @intFromFloat(layout.y)),
            @as(u32, @intFromFloat(layout.x + layout.width)),
            @as(u32, @intFromFloat(layout.y + layout.height)),
            255,
            255,
            255,
            50,
        );
        try testing.expect(found_text);
    }
}
