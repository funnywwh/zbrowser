const std = @import("std");
const testing = std.testing;
const Browser = @import("main").Browser;
const helpers = @import("test_page_render_helpers.zig");

test "test_page render - block-test div background" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 读取 test_page.html
    const html_content = try helpers.readTestPage(allocator);
    defer allocator.free(html_content);

    // 提取CSS
    const css_content = try helpers.extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    // 创建Browser实例
    var browser = try Browser.init(allocator);
    defer browser.deinit();

    // 加载HTML和CSS
    try browser.loadHTML(html_content);
    try browser.addStylesheet(css_content);

    // 渲染获取像素数据
    const width: u32 = 1200;
    const height: u32 = 800;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // 验证像素数据
    try testing.expect(pixels.len == width * height * 4);

    // block-test div 应该在h1下方
    // 背景色是 #e3f2fd (RGB: 227, 242, 253)
    // 在页面中间偏上区域搜索这个颜色
    var found_blue_bg = false;
    const center_x = width / 2;
    const block_y: u32 = 200; // h1下方

    // 在block-test div区域搜索浅蓝色背景
    var y: u32 = block_y;
    while (y < block_y + 100) : (y += 1) {
        var x: u32 = if (center_x > 200) center_x - 200 else 0;
        while (x < center_x + 200 and x < width) : (x += 1) {
            const index = (y * width + x) * 4;
            if (index + 2 < pixels.len) {
                const r = pixels[index];
                const g = pixels[index + 1];
                const b = pixels[index + 2];

                // 检查是否是浅蓝色（#e3f2fd: R=227, G=242, B=253）
                // 允许一些误差（±20）
                if (r >= 207 and r <= 247 and g >= 222 and g <= 262 and b >= 233 and b <= 273) {
                    found_blue_bg = true;
                    break;
                }
            }
        }
        if (found_blue_bg) break;
    }

    // 验证找到了浅蓝色背景（block-test div的背景色）
    try testing.expect(found_blue_bg);
}





// 测试：验证 body 背景色渲染
// body 应该有浅灰色背景（background-color: #f5f5f5）
test "test_page render - block-test div border" {
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
    const height: u32 = 800;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // block-test div 边框颜色是 #2196f3 (RGB: 33, 150, 243)
    // 边框应该在div的边缘，检查顶部边框
    // 使用 checkColorInRegion 辅助函数，扩大搜索范围和容差
    // 注意：边框可能在div的顶部边缘，需要检查更大的区域
    const center_x = width / 2;
    // block-test div应该在h1下方，大约在y=150-250之间
    // 检查多个可能的y位置，因为布局可能不同
    var found_border = false;
    var test_y: u32 = 150;
    while (test_y < 300) : (test_y += 10) {
        if (helpers.checkColorInRegion(pixels, width, height, center_x - 500, test_y, center_x + 500, test_y + 5, 33, 150, 243, 60)) {
            found_border = true;
            break;
        }
    }
    try testing.expect(found_border);
}

// 测试：验证整体布局 - 检查多个元素是否都在正确位置
test "test_page render - block-test h1 text color" {
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

    // 获取 block-test div 的布局信息
    const block_test_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "block-test", null);
    try testing.expect(block_test_layout != null);

    if (block_test_layout) |layout| {
        // block-test h1 应该在 block-test div 内部
        // 文本颜色是 #1976d2 (RGB: 25, 118, 210)
        // 在 block-test 的上半部分搜索（h1 在 div 的顶部）
        const found_text = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x)),
            @as(u32, @intFromFloat(layout.y)),
            @as(u32, @intFromFloat(layout.x + layout.width)),
            @as(u32, @intFromFloat(layout.y + layout.height / 2.0)), // 只搜索上半部分
            25,
            118,
            210,
            30,
        );
        try testing.expect(found_text);
    }
}

// 测试：验证 float-container 的背景色和边框
// float-container 应该有绿色背景（background-color: #e8f5e9）和绿色边框（border: 2px solid #4caf50）
test "test_page render - inline-test div background" {
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
    const height: u32 = 800;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // inline-test div 背景色是 #fff3e0 (RGB: 255, 243, 224)
    // 应该在block-test div下方
    const center_x = width / 2;
    const inline_y: u32 = 400; // block-test div下方
    const found_orange_bg = helpers.checkColorInRegion(pixels, width, height, center_x - 200, inline_y, center_x + 200, inline_y + 100, 255, 243, 224, 20);
    try testing.expect(found_orange_bg);
}

// 测试：验证 block-test div 的边框颜色
// block-test div 应该有蓝色边框（border: 2px solid #2196f3）
test "test_page render - inline-test div border" {
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
    const height: u32 = 800;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // inline-test div 边框颜色是 #ff9800 (RGB: 255, 152, 0)
    // 应该在 inline-test div 区域（大约在 y=300-400 之间）
    const center_x = width / 2;
    var found_border = false;
    var test_y: u32 = 300;
    while (test_y < 450) : (test_y += 10) {
        if (helpers.checkColorInRegion(pixels, width, height, center_x - 500, test_y, center_x + 500, test_y + 5, 255, 152, 0, 60)) {
            found_border = true;
            break;
        }
    }
    try testing.expect(found_border);
}

// 测试：验证 position-container 的背景色和边框（精确验证位置和大小）
// position-container 应该有紫色背景（background-color: #f3e5f5）和紫色边框（border: 2px solid #9c27b0）
test "test_page render - inline-test red text" {
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

    // 获取 inline-test div 的布局信息
    const inline_test_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "inline-test", null);
    try testing.expect(inline_test_layout != null);

    if (inline_test_layout) |layout| {
        // 红色文本 color: red (RGB: 255, 0, 0) 应该在 inline-test 内部
        const found_red_text = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x)),
            @as(u32, @intFromFloat(layout.y)),
            @as(u32, @intFromFloat(layout.x + layout.width)),
            @as(u32, @intFromFloat(layout.y + layout.height)),
            255,
            0,
            0,
            30,
        );
        try testing.expect(found_red_text);
    }
}

// 测试：验证 inline-test 中的蓝色文本（精确验证位置）
// span style="color: blue;" 应该有蓝色文本（color: blue）
test "test_page render - inline-test blue text" {
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

    // 获取 inline-test div 的布局信息
    const inline_test_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "inline-test", null);
    try testing.expect(inline_test_layout != null);

    if (inline_test_layout) |layout| {
        // 蓝色文本 color: blue (RGB: 0, 0, 255) 应该在 inline-test 内部
        const found_blue_text = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x)),
            @as(u32, @intFromFloat(layout.y)),
            @as(u32, @intFromFloat(layout.x + layout.width)),
            @as(u32, @intFromFloat(layout.y + layout.height)),
            0,
            0,
            255,
            30,
        );
        try testing.expect(found_blue_text);
    }
}

// 测试：验证 position-container 内的子元素背景色
// static-box 应该有浅紫色背景（background-color: #e1bee7）
test "test_page render - highlight class background" {
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

    // 获取 inline-test div 的布局信息（highlight 在 inline-test 内部）
    const inline_test_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "div", "inline-test", null);
    try testing.expect(inline_test_layout != null);

    if (inline_test_layout) |layout| {
        // highlight 应该在 inline-test 内部，在文本区域内
        // 由于 highlight 是行内元素，我们可以在 inline-test 的内容区域内搜索
        // highlight 背景色是 #ffeb3b (RGB: 255, 235, 59)
        const found_highlight = helpers.checkColorInRegion(
            pixels,
            width,
            height,
            @as(u32, @intFromFloat(layout.x)),
            @as(u32, @intFromFloat(layout.y)),
            @as(u32, @intFromFloat(layout.x + layout.width)),
            @as(u32, @intFromFloat(layout.y + layout.height)),
            255,
            235,
            59,
            30,
        );
        try testing.expect(found_highlight);
    }
}

// 测试：验证 inline-test 中的红色文本（精确验证位置）
// span style="color: red;" 应该有红色文本（color: red）
test "test_page render - nested div background" {
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
    const height: u32 = 800;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // 嵌套 div 背景色是 #bbdefb (RGB: 187, 222, 251)
    // 应该在 block-test div 内部（大约在 y=250-300 之间）
    const center_x = width / 2;
    const found_nested = helpers.checkColorInRegion(pixels, width, height, center_x - 200, 250, center_x + 200, 300, 187, 222, 251, 30);
    try testing.expect(found_nested);
}

// 测试：验证 highlight 类的背景色（精确验证位置和大小）
// highlight 类应该有黄色背景（background-color: #ffeb3b）
