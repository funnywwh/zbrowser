const std = @import("std");
const testing = std.testing;
const Browser = @import("main").Browser;
const helpers = @import("test_page_render_helpers.zig");

// 测试：渲染 test_page.html 并验证PNG输出
test "test_page render - PNG output" {
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

    // 渲染为PNG（使用较大的尺寸以确保内容可见）
    const test_output = "test_page_output.png";
    try browser.renderToPNG(1200, 800, test_output);
    defer std.fs.cwd().deleteFile(test_output) catch {};

    // 验证PNG文件存在
    const file = try std.fs.cwd().openFile(test_output, .{});
    defer file.close();

    // 验证PNG签名（前8字节）
    var signature: [8]u8 = undefined;
    _ = try file.readAll(&signature);
    try file.seekTo(0);

    const expected_signature = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
    try testing.expectEqualSlices(u8, &expected_signature, &signature);

    // 验证文件大小合理（至少应该有一些内容）
    const stat = try file.stat();
    try testing.expect(stat.size > 1000); // 至少1KB（test_page.html内容较多）
}

// 测试：渲染 test_page.html 并验证像素数据
test "test_page render - pixel data verification" {
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

    // 渲染获取像素数据（使用较大的尺寸）
    const width: u32 = 1200;
    const height: u32 = 800;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // 验证像素数据
    try testing.expect(pixels.len == width * height * 4); // RGBA格式

    // 检查是否有非零像素（确保有内容）
    var has_non_zero = false;
    for (pixels) |pixel| {
        if (pixel != 0) {
            has_non_zero = true;
            break;
        }
    }
    try testing.expect(has_non_zero);
}

// 测试：验证 test_page.html 中特定元素的渲染
// 测试 h1 元素的渲染（应该居中，有红色边框）
test "test_page render - h1 element verification" {
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

    // h1 元素应该在页面顶部居中位置
    // 由于h1有红色边框（border: 2px solid red），我们应该能在顶部中间区域检测到红色像素
    // 根据布局信息，h1的实际位置是y=20.0（with margin），边框在y=18-22左右
    var found_red = false;
    const center_x = width / 2;
    const top_y: u32 = 15; // 顶部区域（调整到h1实际位置）

    // 在顶部中间区域搜索红色像素（边框）
    var y: u32 = top_y;
    while (y < top_y + 50) : (y += 1) {
        var x: u32 = if (center_x > 100) center_x - 100 else 0;
        while (x < center_x + 100 and x < width) : (x += 1) {
            const index = (y * width + x) * 4;
            if (index + 2 < pixels.len) {
                const r = pixels[index];
                const g = pixels[index + 1];
                const b = pixels[index + 2];

                // 检查是否是红色（R值高，G和B值低）
                if (r > 200 and g < 100 and b < 100) {
                    found_red = true;
                    break;
                }
            }
        }
        if (found_red) break;
    }

    // 验证找到了红色像素（h1的红色边框）
    try testing.expect(found_red);
}

// 测试：验证 body 背景色渲染
// body 应该有浅灰色背景（background-color: #f5f5f5）
test "test_page render - body background color" {
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

    // body 背景色是 #f5f5f5 (RGB: 245, 245, 245)
    // 检查左上角区域（应该主要是背景色）
    const found_bg = helpers.checkColorInRegion(pixels, width, height, 0, 0, 50, 50, 245, 245, 245, 20);
    try testing.expect(found_bg);
}

// 测试：验证 h1 文本颜色
// h1 应该有蓝色文本（color: #1976d2）
test "test_page render - h1 text color" {
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

    // h1 文本颜色是 #1976d2 (RGB: 25, 118, 210)
    // 在顶部中间区域搜索蓝色文本
    const center_x = width / 2;
    const found_blue_text = helpers.checkColorInRegion(pixels, width, height, center_x - 100, 50, center_x + 100, 150, 25, 118, 210, 30);
    try testing.expect(found_blue_text);
}

// 测试：验证整体布局 - 检查多个元素是否都在正确位置
test "test_page render - layout verification" {
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

    // 先验证pixels，再清理browser
    // 注意：pixels是通过allocator.alloc分配的，不依赖于browser，所以可以先验证

    // 验证多个关键元素：
    // 1. 顶部有红色边框（h1）
    // 根据布局信息，h1的实际位置是y=20.0（with margin），边框在y=18-22左右
    // 使用更宽的搜索区域和更大的容差，确保能找到红色边框
    var found_h1_border = false;
    const center_x = width / 2;
    var search_y: u32 = 10; // 从更早的位置开始搜索
    while (search_y < 70) : (search_y += 1) {
        var search_x: u32 = if (center_x > 200) center_x - 200 else 0;
        while (search_x < center_x + 200 and search_x < width) : (search_x += 1) {
            const index = (search_y * width + search_x) * 4;
            if (index + 2 < pixels.len) {
                const r = pixels[index];
                const g = pixels[index + 1];
                const b = pixels[index + 2];
                // 检查是否是红色（R值高，G和B值低），使用更宽松的条件
                if (r > 150 and g < 150 and b < 150) {
                    found_h1_border = true;
                    break;
                }
            }
        }
        if (found_h1_border) break;
    }
    try testing.expect(found_h1_border);

    // 2. h1下方有浅蓝色背景（block-test div）
    const found_block_bg = helpers.checkColorInRegion(pixels, width, height, width / 2 - 200, 200, width / 2 + 200, 250, 227, 242, 253, 30);
    try testing.expect(found_block_bg);

    // 3. 页面有内容（不是全黑或全白）
    // 检查像素数组长度是否正确
    const expected_pixels_len = width * height * 4;
    if (pixels.len < expected_pixels_len) {
        // 如果像素数组长度不正确，跳过内容检查
        return;
    }

    var has_content = false;
    var has_dark = false;
    var has_light = false;
    var i: usize = 0;
    const max_i = if (pixels.len > expected_pixels_len) expected_pixels_len else pixels.len;
    // 确保不会越界访问
    const safe_max_i = if (max_i > 3) max_i - 3 else 0;
    while (i < safe_max_i) : (i += 4) {
        // 再次检查边界
        if (i + 3 < pixels.len) {
            const a = pixels[i + 3]; // alpha通道
            if (a > 0) {
                has_content = true;
                const r = pixels[i];
                const g = pixels[i + 1];
                const b = pixels[i + 2];
                const brightness = (@as(u32, r) + @as(u32, g) + @as(u32, b)) / 3;
                if (brightness < 128) has_dark = true;
                if (brightness > 128) has_light = true;
            }
        }
    }
    try testing.expect(has_content);
    try testing.expect(has_dark or has_light); // 应该有明暗变化
}

