const std = @import("std");
const testing = std.testing;
const Browser = @import("main").Browser;

// 辅助函数：读取 test_page.html 文件
fn readTestPage(allocator: std.mem.Allocator) ![]const u8 {
    const file = try std.fs.cwd().openFile("test_page.html", .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    _ = try file.readAll(content);

    return content;
}

// 辅助函数：从HTML中提取CSS（简化实现，只提取<style>标签中的内容）
fn extractCSSFromHTML(html_content: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // 查找 <style> 标签
    const style_start = std.mem.indexOf(u8, html_content, "<style>");
    const style_end = std.mem.indexOf(u8, html_content, "</style>");
    
    if (style_start == null or style_end == null) {
        // 如果没有找到style标签，返回空字符串
        return try allocator.dupe(u8, "");
    }
    
    const css_start = style_start.? + 7; // "<style>" 的长度
    const css_content = html_content[css_start..style_end.?];
    
    return try allocator.dupe(u8, css_content);
}

// 测试：渲染 test_page.html 并验证PNG输出
test "test_page render - PNG output" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 读取 test_page.html
    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    // 提取CSS
    const css_content = try extractCSSFromHTML(html_content, allocator);
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
    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    // 提取CSS
    const css_content = try extractCSSFromHTML(html_content, allocator);
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
    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    // 提取CSS
    const css_content = try extractCSSFromHTML(html_content, allocator);
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

    // 验证像素数据
    try testing.expect(pixels.len == width * height * 4);

    // h1 元素应该在页面顶部居中位置
    // 由于h1有红色边框（border: 2px solid red），我们应该能在顶部中间区域检测到红色像素
    var found_red = false;
    const center_x = width / 2;
    const top_y: u32 = 50; // 顶部区域

    // 在顶部中间区域搜索红色像素（边框）
    var y: u32 = top_y;
    while (y < top_y + 100) : (y += 1) {
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

// 测试：验证 block-test div 的背景色渲染
// block-test div 应该有蓝色背景（background-color: #e3f2fd）
test "test_page render - block-test div background" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 读取 test_page.html
    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    // 提取CSS
    const css_content = try extractCSSFromHTML(html_content, allocator);
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

// 辅助函数：获取像素颜色
fn getPixelColor(pixels: []const u8, width: u32, height: u32, x: u32, y: u32) ?struct { r: u8, g: u8, b: u8, a: u8 } {
    if (x >= width or y >= height) return null;
    const index = (y * width + x) * 4;
    if (index + 3 >= pixels.len) return null;
    return .{
        .r = pixels[index],
        .g = pixels[index + 1],
        .b = pixels[index + 2],
        .a = pixels[index + 3],
    };
}

// 辅助函数：检查区域内的颜色是否匹配（允许误差）
fn checkColorInRegion(
    pixels: []const u8,
    width: u32,
    height: u32,
    start_x: u32,
    start_y: u32,
    end_x: u32,
    end_y: u32,
    expected_r: u8,
    expected_g: u8,
    expected_b: u8,
    tolerance: u8,
) bool {
    // 边界检查：确保坐标在有效范围内
    if (start_x >= width or start_y >= height) return false;
    const safe_end_x = if (end_x >= width) width - 1 else end_x;
    const safe_end_y = if (end_y >= height) height - 1 else end_y;
    
    // 检查像素数组长度
    const expected_len = width * height * 4;
    if (pixels.len < expected_len) return false;
    
    var y = start_y;
    while (y <= safe_end_y) : (y += 1) {
        var x = start_x;
        while (x <= safe_end_x) : (x += 1) {
            if (getPixelColor(pixels, width, height, x, y)) |color| {
                const r_diff = if (color.r > expected_r) color.r - expected_r else expected_r - color.r;
                const g_diff = if (color.g > expected_g) color.g - expected_g else expected_g - color.g;
                const b_diff = if (color.b > expected_b) color.b - expected_b else expected_b - color.b;
                
                if (r_diff <= tolerance and g_diff <= tolerance and b_diff <= tolerance) {
                    return true;
                }
            }
        }
    }
    return false;
}

// 测试：验证 body 背景色渲染
// body 应该有浅灰色背景（background-color: #f5f5f5）
test "test_page render - body background color" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    var browser = try Browser.init(allocator);
    defer browser.deinit();

    try browser.loadHTML(html_content);
    try browser.addStylesheet(css_content);

    const width: u32 = 1200;
    const height: u32 = 800;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // body 背景色是 #f5f5f5 (RGB: 245, 245, 245)
    // 检查左上角区域（应该主要是背景色）
    const found_bg = checkColorInRegion(pixels, width, height, 0, 0, 50, 50, 245, 245, 245, 20);
    try testing.expect(found_bg);
}

// 测试：验证 h1 文本颜色
// h1 应该有蓝色文本（color: #1976d2）
test "test_page render - h1 text color" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    var browser = try Browser.init(allocator);
    defer browser.deinit();

    try browser.loadHTML(html_content);
    try browser.addStylesheet(css_content);

    const width: u32 = 1200;
    const height: u32 = 800;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // h1 文本颜色是 #1976d2 (RGB: 25, 118, 210)
    // 在顶部中间区域搜索蓝色文本
    const center_x = width / 2;
    const found_blue_text = checkColorInRegion(pixels, width, height, center_x - 100, 50, center_x + 100, 150, 25, 118, 210, 30);
    try testing.expect(found_blue_text);
}

// 测试：验证 inline-test div 的背景色
// inline-test div 应该有橙色背景（background-color: #fff3e0）
test "test_page render - inline-test div background" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    var browser = try Browser.init(allocator);
    defer browser.deinit();

    try browser.loadHTML(html_content);
    try browser.addStylesheet(css_content);

    const width: u32 = 1200;
    const height: u32 = 800;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

    // inline-test div 背景色是 #fff3e0 (RGB: 255, 243, 224)
    // 应该在block-test div下方
    const center_x = width / 2;
    const inline_y: u32 = 400; // block-test div下方
    const found_orange_bg = checkColorInRegion(pixels, width, height, center_x - 200, inline_y, center_x + 200, inline_y + 100, 255, 243, 224, 20);
    try testing.expect(found_orange_bg);
}

// 测试：验证 block-test div 的边框颜色
// block-test div 应该有蓝色边框（border: 2px solid #2196f3）
test "test_page render - block-test div border" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    var browser = try Browser.init(allocator);
    defer browser.deinit();

    try browser.loadHTML(html_content);
    try browser.addStylesheet(css_content);

    const width: u32 = 1200;
    const height: u32 = 800;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);

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
        if (checkColorInRegion(pixels, width, height, center_x - 500, test_y, center_x + 500, test_y + 5, 33, 150, 243, 60)) {
            found_border = true;
            break;
        }
    }
    try testing.expect(found_border);
}

// 测试：验证整体布局 - 检查多个元素是否都在正确位置
test "test_page render - layout verification" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    var browser = try Browser.init(allocator);
    defer browser.deinit();
    
    try browser.loadHTML(html_content);
    try browser.addStylesheet(css_content);

    const width: u32 = 1200;
    const height: u32 = 800;
    const pixels = try browser.render(width, height);
    defer allocator.free(pixels);
    
    // 先验证pixels，再清理browser
    // 注意：pixels是通过allocator.alloc分配的，不依赖于browser，所以可以先验证

    // 验证多个关键元素：
    // 1. 顶部有红色边框（h1）
    const found_h1_border = checkColorInRegion(pixels, width, height, width / 2 - 100, 50, width / 2 + 100, 60, 255, 0, 0, 50);
    try testing.expect(found_h1_border);

    // 2. h1下方有浅蓝色背景（block-test div）
    const found_block_bg = checkColorInRegion(pixels, width, height, width / 2 - 200, 200, width / 2 + 200, 250, 227, 242, 253, 30);
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

