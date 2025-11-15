const std = @import("std");
const testing = std.testing;
const Browser = @import("main").Browser;

// 辅助函数：读取 test_page.html 文件
pub fn readTestPage(allocator: std.mem.Allocator) ![]const u8 {
    const file = try std.fs.cwd().openFile("test_page.html", .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    _ = try file.readAll(content);

    return content;
}

// 辅助函数：从HTML中提取CSS（简化实现，只提取<style>标签中的内容）
pub fn extractCSSFromHTML(html_content: []const u8, allocator: std.mem.Allocator) ![]const u8 {
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

// 辅助函数：验证 h1 元素在布局树中存在
// 通过重新构建布局树来验证（因为 Browser 的布局树是私有的）
pub fn verifyH1Exists(browser: *Browser, allocator: std.mem.Allocator) !void {
    const engine = @import("engine");
    const block = @import("block");

    const html_node = browser.document.getDocumentElement() orelse {
        return error.NoDocumentElement;
    };

    // 构建布局树来验证 h1 是否存在
    var layout_engine_instance = engine.LayoutEngine.init(allocator);
    // 注意：LayoutEngine 没有 deinit 方法，它只包含分配器引用

    const layout_tree = try layout_engine_instance.buildLayoutTree(html_node, browser.stylesheets.items);
    defer {
        engine.LayoutEngine.cleanupFormattingContexts(layout_tree);
        layout_tree.deinitAndDestroyChildren();
        allocator.destroy(layout_tree);
    }

    // 查找 body 元素
    const body = block.findElement(layout_tree, "body", null, null);
    try testing.expect(body != null);

    // 查找 h1 元素
    const h1 = block.findElement(body.?, "h1", null, null);
    try testing.expect(h1 != null);
}

// 辅助函数：获取元素的布局信息（位置和大小）
// 返回元素的内容框位置和尺寸
pub fn getElementLayoutInfo(
    browser: *Browser,
    allocator: std.mem.Allocator,
    viewport_width: f32,
    viewport_height: f32,
    tag_name: []const u8,
    class_name: ?[]const u8,
    id: ?[]const u8,
) !?struct { x: f32, y: f32, width: f32, height: f32, margin_top: f32, margin_bottom: f32, margin_left: f32, margin_right: f32, border_top: f32, border_bottom: f32, border_left: f32, border_right: f32 } {
    const engine = @import("engine");
    const block = @import("block");
    const box = @import("box");

    const html_node = browser.document.getDocumentElement() orelse {
        return error.NoDocumentElement;
    };

    // 构建布局树
    var layout_engine_instance = engine.LayoutEngine.init(allocator);
    const layout_tree = try layout_engine_instance.buildLayoutTree(html_node, browser.stylesheets.items);
    defer {
        engine.LayoutEngine.cleanupFormattingContexts(layout_tree);
        layout_tree.deinitAndDestroyChildren();
        allocator.destroy(layout_tree);
    }

    // 执行布局计算
    const viewport = box.Size{ .width = viewport_width, .height = viewport_height };
    try layout_engine_instance.layout(layout_tree, viewport, browser.stylesheets.items);

    // 查找元素
    const body = block.findElement(layout_tree, "body", null, null);
    if (body == null) return null;

    const element = block.findElement(body.?, tag_name, class_name, id);
    if (element == null) return null;

    const box_model = element.?.box_model;
    return .{
        .x = box_model.content.x,
        .y = box_model.content.y,
        .width = box_model.content.width,
        .height = box_model.content.height,
        .margin_top = box_model.margin.top,
        .margin_bottom = box_model.margin.bottom,
        .margin_left = box_model.margin.left,
        .margin_right = box_model.margin.right,
        .border_top = box_model.border.top,
        .border_bottom = box_model.border.bottom,
        .border_left = box_model.border.left,
        .border_right = box_model.border.right,
    };
}

// 辅助函数：验证元素在指定位置和大小范围内
// 使用布局信息来精确验证元素的位置和大小
pub fn verifyElementPositionAndSize(
    pixels: []const u8,
    pixel_width: u32,
    pixel_height: u32,
    element_x: f32,
    element_y: f32,
    element_width: f32,
    element_height: f32,
    expected_r: u8,
    expected_g: u8,
    expected_b: u8,
    tolerance: u8,
) bool {
    // 将浮点坐标转换为整数像素坐标
    const start_x = @as(u32, @intFromFloat(element_x));
    const start_y = @as(u32, @intFromFloat(element_y));
    const end_x = @as(u32, @intFromFloat(element_x + element_width));
    const end_y = @as(u32, @intFromFloat(element_y + element_height));

    // 确保坐标在有效范围内
    if (start_x >= pixel_width or start_y >= pixel_height) return false;
    const safe_end_x = if (end_x >= pixel_width) pixel_width - 1 else end_x;
    const safe_end_y = if (end_y >= pixel_height) pixel_height - 1 else end_y;

    // 计算元素区域的总像素数
    const region_width = safe_end_x - start_x + 1;
    const region_height = safe_end_y - start_y + 1;
    const total_pixels = region_width * region_height;

    if (total_pixels == 0) return false;

    // 大幅提高匹配阈值：至少70%的像素匹配，确保元素确实在正确位置渲染
    // 对于小元素（小于100像素），要求至少90%匹配
    const min_pixels = if (total_pixels < 100)
        if (total_pixels * 9 / 10 > 0) total_pixels * 9 / 10 else 1 // 90% for small elements
    else if (total_pixels * 7 / 10 > 0) total_pixels * 7 / 10 else 1; // 70% for larger elements

    // 在元素区域内检查颜色
    var found_count: u32 = 0;
    var total_checked: u32 = 0;

    var y = start_y;
    while (y <= safe_end_y and y < pixel_height) : (y += 1) {
        var x = start_x;
        while (x <= safe_end_x and x < pixel_width) : (x += 1) {
            total_checked += 1;
            if (getPixelColor(pixels, pixel_width, pixel_height, x, y)) |color| {
                const r_diff = if (color.r > expected_r) color.r - expected_r else expected_r - color.r;
                const g_diff = if (color.g > expected_g) color.g - expected_g else expected_g - color.g;
                const b_diff = if (color.b > expected_b) color.b - expected_b else expected_b - color.b;

                if (r_diff <= tolerance and g_diff <= tolerance and b_diff <= tolerance) {
                    found_count += 1;
                }
            }
        }
    }

    // 确保检查了足够的像素
    if (total_checked < min_pixels) return false;

    // 计算匹配百分比
    const match_percentage = if (total_checked > 0) (@as(f32, @floatFromInt(found_count)) / @as(f32, @floatFromInt(total_checked))) * 100.0 else 0.0;
    const required_percentage: f32 = if (total_pixels < 100) @as(f32, 90.0) else @as(f32, 70.0);

    // 如果匹配百分比低于要求，返回false
    if (match_percentage < required_percentage) {
        // 在Debug模式下输出调试信息
        if (@import("builtin").mode == .Debug) {
            std.debug.print("[VERIFY] Element region: {d}x{d} pixels, found {d}/{d} ({d:.1}%), required {d:.1}%\n", .{ region_width, region_height, found_count, total_checked, match_percentage, required_percentage });
        }
        return false;
    }

    return true;
}

// 辅助函数：验证元素的位置和大小是否与布局计算一致
// 允许1-2像素的误差（由于浮点数到整数转换和抗锯齿）
pub fn verifyElementPositionAndSizeAccuracy(
    layout_x: f32,
    layout_y: f32,
    layout_width: f32,
    layout_height: f32,
    actual_x: f32,
    actual_y: f32,
    actual_width: f32,
    actual_height: f32,
    position_tolerance: f32,
    size_tolerance: f32,
) bool {
    // 验证位置（允许1-2像素误差）
    const x_diff = if (actual_x > layout_x) actual_x - layout_x else layout_x - actual_x;
    const y_diff = if (actual_y > layout_y) actual_y - layout_y else layout_y - actual_y;

    if (x_diff > position_tolerance or y_diff > position_tolerance) {
        return false;
    }

    // 验证大小（允许1-2像素误差）
    const width_diff = if (actual_width > layout_width) actual_width - layout_width else layout_width - actual_width;
    const height_diff = if (actual_height > layout_height) actual_height - layout_height else layout_height - actual_height;

    if (width_diff > size_tolerance or height_diff > size_tolerance) {
        return false;
    }

    return true;
}

// 辅助函数：验证两个元素的相对位置关系
// 例如：验证flexbox中元素的顺序，grid中元素的位置等
pub fn verifyRelativePosition(
    element1_x: f32,
    element1_y: f32,
    element1_width: f32,
    element1_height: f32,
    element2_x: f32,
    element2_y: f32,
    element2_width: f32,
    element2_height: f32,
    expected_relation: enum { left_of, right_of, above, below, same_row, same_column },
) bool {
    return switch (expected_relation) {
        .left_of => element1_x + element1_width <= element2_x,
        .right_of => element1_x >= element2_x + element2_width,
        .above => element1_y + element1_height <= element2_y,
        .below => element1_y >= element2_y + element2_height,
        .same_row => {
            // 在同一行（y坐标相近，允许5像素误差）
            const y_diff = if (element1_y > element2_y) element1_y - element2_y else element2_y - element1_y;
            return y_diff <= 5.0;
        },
        .same_column => {
            // 在同一列（x坐标相近，允许5像素误差）
            const x_diff = if (element1_x > element2_x) element1_x - element2_x else element2_x - element1_x;
            return x_diff <= 5.0;
        },
    };
}

// 辅助函数：获取像素颜色
pub fn getPixelColor(pixels: []const u8, width: u32, height: u32, x: u32, y: u32) ?struct { r: u8, g: u8, b: u8, a: u8 } {
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
pub fn checkColorInRegion(
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

// 辅助函数：在整个图像中查找指定颜色的区域（返回找到的第一个位置）
// 用于动态定位元素的实际渲染位置
pub fn findColorRegion(
    pixels: []const u8,
    width: u32,
    height: u32,
    expected_r: u8,
    expected_g: u8,
    expected_b: u8,
    tolerance: u8,
    min_region_size: u32,
) ?struct { x: u32, y: u32, width: u32, height: u32 } {
    const expected_len = width * height * 4;
    if (pixels.len < expected_len) return null;

    var y: u32 = 0;
    while (y < height) : (y += 1) {
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            if (getPixelColor(pixels, width, height, x, y)) |color| {
                const r_diff = if (color.r > expected_r) color.r - expected_r else expected_r - color.r;
                const g_diff = if (color.g > expected_g) color.g - expected_g else expected_g - color.g;
                const b_diff = if (color.b > expected_b) color.b - expected_b else expected_b - color.b;

                if (r_diff <= tolerance and g_diff <= tolerance and b_diff <= tolerance) {
                    // 找到匹配的像素，检查是否形成足够大的区域
                    var region_width: u32 = 0;
                    var region_height: u32 = 0;
                    var check_x = x;
                    var check_y = y;

                    // 计算水平方向的连续匹配像素数
                    while (check_x < width) : (check_x += 1) {
                        if (getPixelColor(pixels, width, height, check_x, check_y)) |c| {
                            const rd = if (c.r > expected_r) c.r - expected_r else expected_r - c.r;
                            const gd = if (c.g > expected_g) c.g - expected_g else expected_g - c.g;
                            const bd = if (c.b > expected_b) c.b - expected_b else expected_b - c.b;
                            if (rd <= tolerance and gd <= tolerance and bd <= tolerance) {
                                region_width += 1;
                            } else {
                                break;
                            }
                        } else {
                            break;
                        }
                    }

                    // 计算垂直方向的连续匹配像素数
                    check_x = x;
                    while (check_y < height) : (check_y += 1) {
                        if (getPixelColor(pixels, width, height, check_x, check_y)) |c| {
                            const rd = if (c.r > expected_r) c.r - expected_r else expected_r - c.r;
                            const gd = if (c.g > expected_g) c.g - expected_g else expected_g - c.g;
                            const bd = if (c.b > expected_b) c.b - expected_b else expected_b - c.b;
                            if (rd <= tolerance and gd <= tolerance and bd <= tolerance) {
                                region_height += 1;
                            } else {
                                break;
                            }
                        } else {
                            break;
                        }
                    }

                    // 如果区域足够大，返回位置
                    if (region_width >= min_region_size and region_height >= min_region_size) {
                        return .{ .x = x, .y = y, .width = region_width, .height = region_height };
                    }
                }
            }
        }
    }
    return null;
}

// 辅助函数：在指定y范围内搜索颜色（用于查找特定元素）
pub fn findColorInYRange(
    pixels: []const u8,
    width: u32,
    height: u32,
    start_y: u32,
    end_y: u32,
    expected_r: u8,
    expected_g: u8,
    expected_b: u8,
    tolerance: u8,
) ?struct { x: u32, y: u32 } {
    const expected_len = width * height * 4;
    if (pixels.len < expected_len) return null;
    if (start_y >= height or end_y >= height) return null;

    const safe_end_y = if (end_y >= height) height - 1 else end_y;
    var y = start_y;
    while (y <= safe_end_y) : (y += 1) {
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            if (getPixelColor(pixels, width, height, x, y)) |color| {
                const r_diff = if (color.r > expected_r) color.r - expected_r else expected_r - color.r;
                const g_diff = if (color.g > expected_g) color.g - expected_g else expected_g - color.g;
                const b_diff = if (color.b > expected_b) color.b - expected_b else expected_b - color.b;

                if (r_diff <= tolerance and g_diff <= tolerance and b_diff <= tolerance) {
                    return .{ .x = x, .y = y };
                }
            }
        }
    }
    return null;
}
