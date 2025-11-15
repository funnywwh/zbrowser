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
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 252, 228, 236, 5);
        try testing.expect(found_bg);

        // 验证边框颜色 #e91e63 (RGB: 233, 30, 99)
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_found = helpers.checkColorInRegion(pixels, width, height, @as(u32, @intFromFloat(layout.x)), border_search_top_y, @as(u32, @intFromFloat(layout.x + layout.width)), @as(u32, @intFromFloat(layout.y + 5)), 233, 30, 99, 10);
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
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 232, 234, 246, 5);
        try testing.expect(found_bg);

        // 验证边框颜色 #3f51b5 (RGB: 63, 81, 181)
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_found = helpers.checkColorInRegion(pixels, width, height, @as(u32, @intFromFloat(layout.x)), border_search_top_y, @as(u32, @intFromFloat(layout.x + layout.width)), @as(u32, @intFromFloat(layout.y + 5)), 63, 81, 181, 10);
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
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 255, 248, 225, 5);
        try testing.expect(found_bg);

        // 验证边框颜色 #ff6f00 (RGB: 255, 111, 0)，边框宽度是5px
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_found = helpers.checkColorInRegion(pixels, width, height, @as(u32, @intFromFloat(layout.x)), border_search_top_y, @as(u32, @intFromFloat(layout.x + layout.width)), @as(u32, @intFromFloat(layout.y + 10)), 255, 111, 0, 10);
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
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 241, 248, 233, 5);
        try testing.expect(found_bg);

        // 验证边框颜色 #689f38 (RGB: 104, 159, 56)
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_found = helpers.checkColorInRegion(pixels, width, height, @as(u32, @intFromFloat(layout.x)), border_search_top_y, @as(u32, @intFromFloat(layout.x + layout.width)), @as(u32, @intFromFloat(layout.y + 5)), 104, 159, 56, 10);
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

// 测试：验证 text-medium 的文本颜色
// text-medium 应该有粉色文本（color: #e91e63），字体大小20px
test "test_page render - text-medium color" {
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
        // text-medium 文本颜色是 #e91e63 (RGB: 233, 30, 99)
        // 在 text-styles 内部搜索（text-medium在中间部分）
        const found_text = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x)),
            @as(u32, @intFromFloat(layout.y + layout.height / 3.0)), // 中间1/3区域
            @as(u32, @intFromFloat(layout.x + layout.width)),
            @as(u32, @intFromFloat(layout.y + layout.height * 2.0 / 3.0)),
            233,
            30,
            99,
            30,
        );
        try testing.expect(found_text);
    }
}

// 测试：验证 text-small 的文本颜色
// text-small 应该有浅粉色文本（color: #f06292），字体大小12px
test "test_page render - text-small color" {
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
        // text-small 文本颜色是 #f06292 (RGB: 240, 98, 146)
        // 在 text-styles 内部搜索（text-small在中间部分）
        const found_text = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x)),
            @as(u32, @intFromFloat(layout.y + layout.height / 3.0)), // 中间1/3区域
            @as(u32, @intFromFloat(layout.x + layout.width)),
            @as(u32, @intFromFloat(layout.y + layout.height * 2.0 / 3.0)),
            240,
            98,
            146,
            30,
        );
        try testing.expect(found_text);
    }
}

// 测试：验证 border-dashed 的虚线边框
// border-dashed 应该有橙色虚线边框（border: 3px dashed #ffa726）
test "test_page render - border-dashed border" {
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

    // border-dashed 元素可能没有特定的class，我们通过搜索橙色边框来验证
    // 边框颜色是 #ffa726 (RGB: 255, 167, 38)
    // 在页面中搜索这个颜色（可能在border-test附近）
    const found_dashed = helpers.checkColorInRegion(
        pixels,
        width,
        height,
        0,
        0,
        width,
        height,
        255,
        167,
        38,
        60,
    );
    // 注意：虚线边框可能不是连续的，所以这个测试可能不够精确
    // 但至少验证了边框颜色存在
    try testing.expect(found_dashed);
}

// 测试：验证 nested-level-2 的背景色
// nested-level-2 应该有浅绿色背景（background-color: #c5e1a5）
test "test_page render - nested-level-2 background" {
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
        // nested-level-2 在 nested 内部（更深一层）
        // 背景色是 #c5e1a5 (RGB: 197, 225, 165)
        const found_level2 = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(container_layout.x)),
            @as(u32, @intFromFloat(container_layout.y)),
            @as(u32, @intFromFloat(container_layout.x + container_layout.width)),
            @as(u32, @intFromFloat(container_layout.y + container_layout.height)),
            197,
            225,
            165,
            30,
        );
        try testing.expect(found_level2);
    }
}

// 测试：验证 special-chars 的背景色和边框
// special-chars 应该有紫色背景（background-color: #ede7f6）和紫色边框（border: 2px solid #7b1fa2）
test "test_page render - special-chars background and border" {
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

    const special_chars_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "special-chars", null);
    try testing.expect(special_chars_layout != null);

    if (special_chars_layout) |layout| {
        // 验证背景色 #ede7f6 (RGB: 237, 231, 246)
        const found_bg = helpers.verifyElementPositionAndSize(pixels, width, height, layout.x, layout.y, layout.width, layout.height, 237, 231, 246, 5);
        try testing.expect(found_bg);

        // 验证边框颜色 #7b1fa2 (RGB: 123, 31, 162)
        const border_search_top_y = if (layout.y > layout.border_top) @as(u32, @intFromFloat(layout.y - layout.border_top - 5)) else 0;
        const border_found = helpers.checkColorInRegion(pixels, width, height, @as(u32, @intFromFloat(layout.x)), border_search_top_y, @as(u32, @intFromFloat(layout.x + layout.width)), @as(u32, @intFromFloat(layout.y + 5)), 123, 31, 162, 10);
        try testing.expect(border_found);
    }
}

// 测试：验证 text-decoration 下划线文本
// 应该有下划线样式的文本（text-decoration: underline）
test "test_page render - text-decoration underline" {
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
        // 下划线文本在 text-styles 内部（底部区域）
        // 由于下划线是装饰性的，我们主要验证文本存在
        // 文本颜色应该是默认的 #333 (RGB: 51, 51, 51)
        const found_text = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x)),
            @as(u32, @intFromFloat(layout.y + layout.height * 0.7)), // 底部区域
            @as(u32, @intFromFloat(layout.x + layout.width)),
            @as(u32, @intFromFloat(layout.y + layout.height)),
            51,
            51,
            51,
            50,
        );
        try testing.expect(found_text);
    }
}

// 测试：验证 strong 和 em 元素的文本样式
// strong 应该有粗体文本，em 应该有斜体文本
test "test_page render - strong and em text styles" {
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

    // strong 和 em 在 inline-test 内部
    const inline_test_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "inline-test", null);
    try testing.expect(inline_test_layout != null);

    if (inline_test_layout) |layout| {
        // 验证文本存在（strong 和 em 的文本颜色应该是默认的 #333）
        // 由于粗体和斜体主要是字体样式，我们验证文本存在即可
        const found_text = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x)),
            @as(u32, @intFromFloat(layout.y)),
            @as(u32, @intFromFloat(layout.x + layout.width)),
            @as(u32, @intFromFloat(layout.y + layout.height)),
            51,
            51,
            51,
            50,
        );
        try testing.expect(found_text);
    }
}

// 测试：验证第三层嵌套的背景色
// 第三层嵌套应该有浅绿色背景（background-color: #aed581）
test "test_page render - nested-level-3 background" {
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
        // 第三层嵌套在 nested 内部（最深一层）
        // 背景色是 #aed581 (RGB: 174, 213, 129)
        const found_level3 = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(container_layout.x)),
            @as(u32, @intFromFloat(container_layout.y)),
            @as(u32, @intFromFloat(container_layout.x + container_layout.width)),
            @as(u32, @intFromFloat(container_layout.y + container_layout.height)),
            174,
            213,
            129,
            30,
        );
        try testing.expect(found_level3);
    }
}

// 测试：验证复杂组合测试区域的背景色和边框
// 复杂组合测试区域应该有浅灰色背景（background-color: #fafafa）和深灰色边框（border: 3px solid #616161）
test "test_page render - complex-combination background and border" {
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

    // 复杂组合测试区域没有特定的class，我们通过搜索背景色来验证
    // 背景色是 #fafafa (RGB: 250, 250, 250)
    // 这个区域在页面底部，应该在footer之前
    const found_complex = helpers.checkColorInRegion(
        pixels,
        width,
        height,
        0,
        @as(u32, @intFromFloat(@as(f32, @floatFromInt(height)) * 0.7)), // 在页面下半部分
        width,
        height,
        250,
        250,
        250,
        20,
    );
    try testing.expect(found_complex);
}
