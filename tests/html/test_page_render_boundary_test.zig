const std = @import("std");
const testing = std.testing;
const Browser = @import("main").Browser;
const helpers = @import("test_page_render_helpers.zig");

test "test_page render boundary_case - small viewport" {
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

    // 使用很小的视口（100x100）
    const width: u32 = 100;
    const height: u32 = 100;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // 验证像素数据长度正确
    try testing.expect(pixels.len == width * height * 4);

    // 验证有内容（不是全零）
    var has_content = false;
    for (pixels) |pixel| {
        if (pixel != 0) {
            has_content = true;
            break;
        }
    }
    try testing.expect(has_content);
}

// 边界测试：大视口渲染
test "test_page render boundary_case - large viewport" {
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

    // 使用很大的视口（4000x4000）
    const width: u32 = 4000;
    const height: u32 = 4000;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    // 验证像素数据长度正确
    try testing.expect(pixels.len == width * height * 4);

    // 验证有内容（不是全零）
    var has_content = false;
    for (pixels) |pixel| {
        if (pixel != 0) {
            has_content = true;
            break;
        }
    }
    try testing.expect(has_content);
}

// 边界测试：多次渲染（验证缓存和内存管理）
test "test_page render boundary_case - multiple renders" {
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

    // 第一次渲染
    const width1: u32 = 1200;
    const height1: u32 = 800;
    const pixels1 = try browser.render(width1, height1);
    defer allocator.free(pixels1);

    // 验证 h1 元素存在（在布局树中）
    try helpers.verifyH1Exists(&browser, allocator);

    try testing.expect(pixels1.len == width1 * height1 * 4);

    // 第二次渲染（使用不同的尺寸，验证布局树缓存）
    const width2: u32 = 800;
    const height2: u32 = 600;
    const pixels2 = try browser.render(width2, height2);
    defer allocator.free(pixels2);

    // 验证 h1 元素仍然存在
    try helpers.verifyH1Exists(&browser, allocator);

    try testing.expect(pixels2.len == width2 * height2 * 4);

    // 第三次渲染（使用相同的尺寸，验证缓存复用）
    const pixels3 = try browser.render(width2, height2);
    defer allocator.free(pixels3);

    // 验证 h1 元素仍然存在
    try helpers.verifyH1Exists(&browser, allocator);

    try testing.expect(pixels3.len == width2 * height2 * 4);
}

// 测试：验证嵌套 div 的背景色
// 嵌套的 div 应该有浅蓝色背景（background-color: #bbdefb）
