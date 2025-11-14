const std = @import("std");
const testing = std.testing;
const Browser = @import("main").Browser;
const dom = @import("dom");
const html = @import("html");
const engine = @import("engine");
const box = @import("box");
const block = @import("block");
const css = @import("css");

// 辅助函数：读取 test_page.html 文件
fn readTestPage(allocator: std.mem.Allocator) ![]const u8 {
    const file = try std.fs.cwd().openFile("test_page.html", .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    _ = try file.readAll(content);

    return content;
}

// 辅助函数：从HTML中提取CSS
fn extractCSSFromHTML(html_content: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const style_start = std.mem.indexOf(u8, html_content, "<style>");
    const style_end = std.mem.indexOf(u8, html_content, "</style>");
    
    if (style_start == null or style_end == null) {
        return try allocator.dupe(u8, "");
    }
    
    const css_start = style_start.? + 7;
    const css_content = html_content[css_start..style_end.?];
    
    return try allocator.dupe(u8, css_content);
}

// 辅助函数：释放DOM节点（用于清理）
fn freeAllNodes(allocator: std.mem.Allocator, node: *dom.Node) void {
    var current = node.first_child;
    while (current) |child| {
        const next = child.next_sibling;
        freeAllNodes(allocator, child);
        freeNode(allocator, child);
        current = next;
    }
    node.first_child = null;
    node.last_child = null;
}

fn freeNode(allocator: std.mem.Allocator, node: *dom.Node) void {
    switch (node.node_type) {
        .element => {
            if (node.asElement()) |elem| {
                allocator.free(elem.tag_name);
                var it = elem.attributes.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    allocator.free(entry.value_ptr.*);
                }
                elem.attributes.deinit();
            }
        },
        .text => {
            if (node.asText()) |text| {
                allocator.free(text);
            }
        },
        .comment => {
            if (node.node_type == .comment) {
                allocator.free(node.data.comment);
            }
        },
        .document => return,
        else => {},
    }
    if (node.node_type != .document) {
        allocator.destroy(node);
    }
}

// 辅助函数：构建布局树（用于验证）
// 返回布局树和doc_ptr，调用者需要负责释放
fn buildLayoutTreeForVerification(
    html_content: []const u8,
    css_content: []const u8,
    allocator: std.mem.Allocator,
    viewport_width: f32,
    viewport_height: f32,
) !struct { layout_tree: *box.LayoutBox, doc_ptr: *dom.Document } {
    // 创建Document
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    doc_ptr.* = doc;

    // 解析HTML
    var html_parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer html_parser.deinit();
    try html_parser.parse();

    // 解析CSS
    var css_parser_instance = css.Parser.init(css_content, allocator);
    defer css_parser_instance.deinit();
    var stylesheet = try css_parser_instance.parse();
    defer stylesheet.deinit();

    // 构建布局树
    var layout_engine_instance = engine.LayoutEngine.init(allocator);
    const html_node = doc_ptr.getDocumentElement() orelse {
        freeAllNodes(allocator, &doc_ptr.node);
        allocator.destroy(doc_ptr);
        return error.NoDocumentElement;
    };
    const layout_tree = try layout_engine_instance.buildLayoutTree(html_node, &[_]css.Stylesheet{stylesheet});
    
    // 执行布局计算
    const viewport = box.Size{ .width = viewport_width, .height = viewport_height };
    try layout_engine_instance.layout(layout_tree, viewport, &[_]css.Stylesheet{stylesheet});

    // 返回布局树和doc_ptr，调用者需要负责释放
    return .{ .layout_tree = layout_tree, .doc_ptr = doc_ptr };
}

// 测试：验证 h1 元素的位置和尺寸
test "test_page layout - h1 position and size" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    // 构建布局树
    const result = try buildLayoutTreeForVerification(html_content, css_content, allocator, 1200, 800);
    const layout_tree = result.layout_tree;
    const doc_ptr = result.doc_ptr;
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        allocator.destroy(doc_ptr);
    }
    defer {
        // 先清理formatting_context，再清理布局树
        engine.LayoutEngine.cleanupFormattingContexts(layout_tree);
        layout_tree.deinitAndDestroyChildren();
        allocator.destroy(layout_tree);
    }

    // 查找body元素
    const body = block.findElement(layout_tree, "body", null, null);
    try testing.expect(body != null);

    // 查找h1元素
    const h1 = block.findElement(body.?, "h1", null, null);
    try testing.expect(h1 != null);

    // 验证h1的位置（应该在页面顶部，居中）
    const h1_x = h1.?.box_model.content.x;
    const h1_y = h1.?.box_model.content.y;
    const h1_width = h1.?.box_model.content.width;
    const h1_height = h1.?.box_model.content.height;

    // h1应该在顶部（y应该较小，但需要考虑padding）
    try testing.expect(h1_y >= 0);
    try testing.expect(h1_y < 200); // 应该在顶部200像素内

    // h1应该有宽度和高度
    try testing.expect(h1_width > 0);
    try testing.expect(h1_height > 0);

    // h1应该居中（x应该在中间位置附近，允许一些误差）
    const center_x = 600.0; // 视口宽度1200的一半
    const h1_center_x = h1_x + h1_width / 2.0;
    const x_diff = if (h1_center_x > center_x) h1_center_x - center_x else center_x - h1_center_x;
    try testing.expect(x_diff < 100); // 允许100像素的误差
}

// 测试：验证 block-test div 的位置和尺寸
test "test_page layout - block-test div position and size" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    const result = try buildLayoutTreeForVerification(html_content, css_content, allocator, 1200, 800);
    const layout_tree = result.layout_tree;
    const doc_ptr = result.doc_ptr;
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        allocator.destroy(doc_ptr);
    }
    defer {
        // 先清理formatting_context，再清理布局树
        engine.LayoutEngine.cleanupFormattingContexts(layout_tree);
        layout_tree.deinitAndDestroyChildren();
        allocator.destroy(layout_tree);
    }

    const body = block.findElement(layout_tree, "body", null, null);
    try testing.expect(body != null);

    // 查找block-test div
    const block_test = block.findElement(body.?, "div", "block-test", null);
    try testing.expect(block_test != null);

    // 验证位置和尺寸
    const div_y = block_test.?.box_model.content.y;
    const div_width = block_test.?.box_model.content.width;
    const div_height = block_test.?.box_model.content.height;

    // 应该在h1下方
    const h1 = block.findElement(body.?, "h1", null, null);
    if (h1) |h1_box| {
        const h1_bottom = h1_box.box_model.content.y + h1_box.box_model.content.height;
        try testing.expect(div_y >= h1_bottom - 10); // 允许10像素误差
    }

    // 应该有宽度和高度
    try testing.expect(div_width > 0);
    try testing.expect(div_height > 0);

    // 宽度应该接近视口宽度（考虑padding和margin）
    try testing.expect(div_width > 500); // 至少500像素宽
}

// 测试：验证 position-container div 的位置布局
test "test_page layout - position-container layout" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    const result = try buildLayoutTreeForVerification(html_content, css_content, allocator, 1200, 800);
    const layout_tree = result.layout_tree;
    const doc_ptr = result.doc_ptr;
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        allocator.destroy(doc_ptr);
    }
    defer {
        // 先清理formatting_context，再清理布局树
        engine.LayoutEngine.cleanupFormattingContexts(layout_tree);
        layout_tree.deinitAndDestroyChildren();
        allocator.destroy(layout_tree);
    }

    const body = block.findElement(layout_tree, "body", null, null);
    try testing.expect(body != null);

    // 查找position-container div
    const position_container = block.findElement(body.?, "div", "position-container", null);
    try testing.expect(position_container != null);

    // 验证position-container有子元素
    try testing.expect(position_container.?.children.items.len > 0);

    // 查找relative-box（应该有相对定位）
    const relative_box = block.findElement(position_container.?, "div", "relative-box", null);
    try testing.expect(relative_box != null);

    // 验证relative定位（应该有left和top偏移）
    try testing.expect(relative_box.?.position == .relative);
    try testing.expect(relative_box.?.position_left != null);
    try testing.expect(relative_box.?.position_top != null);

    // 验证left和top的值（根据CSS：left: 20px, top: 10px）
    if (relative_box.?.position_left) |left| {
        try testing.expect(left >= 15 and left <= 25); // 允许5像素误差
    }
    if (relative_box.?.position_top) |top| {
        try testing.expect(top >= 5 and top <= 15); // 允许5像素误差
    }
}

// 测试：验证 float-container div 的浮动布局
test "test_page layout - float-container layout" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    const result = try buildLayoutTreeForVerification(html_content, css_content, allocator, 1200, 800);
    const layout_tree = result.layout_tree;
    const doc_ptr = result.doc_ptr;
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        allocator.destroy(doc_ptr);
    }
    defer {
        // 先清理formatting_context，再清理布局树
        engine.LayoutEngine.cleanupFormattingContexts(layout_tree);
        layout_tree.deinitAndDestroyChildren();
        allocator.destroy(layout_tree);
    }

    const body = block.findElement(layout_tree, "body", null, null);
    try testing.expect(body != null);

    // 查找float-container div
    const float_container = block.findElement(body.?, "div", "float-container", null);
    try testing.expect(float_container != null);

    // 查找float-left div
    const float_left = block.findElement(float_container.?, "div", "float-left", null);
    try testing.expect(float_left != null);

    // 验证浮动类型
    try testing.expect(float_left.?.float == .left);

    // 查找float-right div
    const float_right = block.findElement(float_container.?, "div", "float-right", null);
    try testing.expect(float_right != null);

    // 验证浮动类型
    try testing.expect(float_right.?.float == .right);

    // 验证位置：float-left应该在左侧，float-right应该在右侧
    const left_x = float_left.?.box_model.content.x;
    const right_x = float_right.?.box_model.content.x;
    try testing.expect(left_x < right_x);
}

// 测试：验证 flex-container div 的Flexbox布局
test "test_page layout - flex-container layout" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    const result = try buildLayoutTreeForVerification(html_content, css_content, allocator, 1200, 800);
    const layout_tree = result.layout_tree;
    const doc_ptr = result.doc_ptr;
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        allocator.destroy(doc_ptr);
    }
    defer {
        // 先清理formatting_context，再清理布局树
        engine.LayoutEngine.cleanupFormattingContexts(layout_tree);
        layout_tree.deinitAndDestroyChildren();
        allocator.destroy(layout_tree);
    }

    const body = block.findElement(layout_tree, "body", null, null);
    try testing.expect(body != null);

    // 查找flex-container div
    const flex_container = block.findElement(body.?, "div", "flex-container", null);
    try testing.expect(flex_container != null);

    // 验证display类型
    try testing.expect(flex_container.?.display == .flex);

    // 验证有flex子元素
    try testing.expect(flex_container.?.children.items.len > 0);

    // 查找flex-item元素
    var flex_item_count: usize = 0;
    for (flex_container.?.children.items) |child| {
        if (child.node.node_type == .element) {
            if (child.node.asElement()) |elem| {
                const class_attr = elem.getAttribute("class");
                if (class_attr) |cls| {
                    if (std.mem.indexOf(u8, cls, "flex-item") != null) {
                        flex_item_count += 1;
                    }
                }
            }
        }
    }
    try testing.expect(flex_item_count >= 3); // 应该至少有3个flex-item
}

// 测试：验证 grid-container div 的Grid布局
test "test_page layout - grid-container layout" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    const result = try buildLayoutTreeForVerification(html_content, css_content, allocator, 1200, 800);
    const layout_tree = result.layout_tree;
    const doc_ptr = result.doc_ptr;
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        allocator.destroy(doc_ptr);
    }
    defer {
        // 先清理formatting_context，再清理布局树
        engine.LayoutEngine.cleanupFormattingContexts(layout_tree);
        layout_tree.deinitAndDestroyChildren();
        allocator.destroy(layout_tree);
    }

    const body = block.findElement(layout_tree, "body", null, null);
    try testing.expect(body != null);

    // 查找grid-container div
    const grid_container = block.findElement(body.?, "div", "grid-container", null);
    try testing.expect(grid_container != null);

    // 验证display类型
    try testing.expect(grid_container.?.display == .grid);

    // 验证有grid子元素
    try testing.expect(grid_container.?.children.items.len > 0);

    // 查找grid-item元素，验证grid-row和grid-column属性
    var found_grid_item_1 = false;
    var found_grid_item_2 = false;
    for (grid_container.?.children.items) |child| {
        if (child.node.node_type == .element) {
            if (child.node.asElement()) |elem| {
                const class_attr = elem.getAttribute("class");
                if (class_attr) |cls| {
                    if (std.mem.indexOf(u8, cls, "grid-item-1") != null) {
                        found_grid_item_1 = true;
                        // 验证grid-column属性（应该跨2列）
                        try testing.expect(child.grid_column_start != null);
                        try testing.expect(child.grid_column_end != null);
                    }
                    if (std.mem.indexOf(u8, cls, "grid-item-2") != null) {
                        found_grid_item_2 = true;
                        // 验证grid-row属性（应该跨2行）
                        try testing.expect(child.grid_row_start != null);
                        try testing.expect(child.grid_row_end != null);
                    }
                }
            }
        }
    }
    try testing.expect(found_grid_item_1);
    try testing.expect(found_grid_item_2);
}

// 测试：验证文本内容的渲染（通过像素模式匹配）
// 这是一个简化的文本验证，通过检查文本区域是否有内容来验证文本是否渲染
test "test_page render - text content verification" {
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

    // 构建布局树来获取h1的位置
    const result = try buildLayoutTreeForVerification(html_content, css_content, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)));
    const layout_tree = result.layout_tree;
    const doc_ptr = result.doc_ptr;
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        allocator.destroy(doc_ptr);
    }
    defer {
        // 先清理formatting_context，再清理布局树
        engine.LayoutEngine.cleanupFormattingContexts(layout_tree);
        layout_tree.deinitAndDestroyChildren();
        allocator.destroy(layout_tree);
    }

    const body = block.findElement(layout_tree, "body", null, null);
    try testing.expect(body != null);

    const h1 = block.findElement(body.?, "h1", null, null);
    try testing.expect(h1 != null);

    // 获取h1的位置和尺寸
    const h1_x = @as(u32, @intFromFloat(h1.?.box_model.content.x));
    const h1_y = @as(u32, @intFromFloat(h1.?.box_model.content.y));
    const h1_width = @as(u32, @intFromFloat(h1.?.box_model.content.width));
    const h1_height = @as(u32, @intFromFloat(h1.?.box_model.content.height));

    // 在h1区域内检查是否有文本内容（非背景色的像素）
    // h1文本颜色是 #1976d2 (RGB: 25, 118, 210)
    var found_text_pixels = false;
    var y: u32 = h1_y;
    while (y < h1_y + h1_height and y < height) : (y += 1) {
        var x: u32 = h1_x;
        while (x < h1_x + h1_width and x < width) : (x += 1) {
            const index = (y * width + x) * 4;
            if (index + 2 < pixels.len) {
                const r = pixels[index];
                const g = pixels[index + 1];
                const b = pixels[index + 2];

                // 检查是否是文本颜色（蓝色，允许误差）
                const r_diff = if (r > 25) r - 25 else 25 - r;
                const g_diff = if (g > 118) g - 118 else 118 - g;
                const b_diff = if (b > 210) b - 210 else 210 - b;

                if (r_diff <= 50 and g_diff <= 50 and b_diff <= 50) {
                    found_text_pixels = true;
                    break;
                }
            }
        }
        if (found_text_pixels) break;
    }

    // 验证找到了文本像素
    try testing.expect(found_text_pixels);
}

// 测试：验证多个元素的相对位置关系
test "test_page layout - element relative positions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    // 创建Document用于释放DOM节点
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    doc_ptr.* = doc;
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        allocator.destroy(doc_ptr);
    }
    
    // 解析HTML
    var html_parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer html_parser.deinit();
    try html_parser.parse();
    
    // 解析CSS
    var css_parser_instance = css.Parser.init(css_content, allocator);
    defer css_parser_instance.deinit();
    var stylesheet = try css_parser_instance.parse();
    defer stylesheet.deinit();
    
    // 构建布局树
    var layout_engine_instance = engine.LayoutEngine.init(allocator);
    const html_node = doc_ptr.getDocumentElement() orelse return error.NoDocumentElement;
    const layout_tree = try layout_engine_instance.buildLayoutTree(html_node, &[_]css.Stylesheet{stylesheet});
    defer {
        layout_tree.deinitAndDestroyChildren();
        allocator.destroy(layout_tree);
    }
    
    // 执行布局计算
    const viewport = box.Size{ .width = 1200, .height = 800 };
    try layout_engine_instance.layout(layout_tree, viewport, &[_]css.Stylesheet{stylesheet});

    const body = block.findElement(layout_tree, "body", null, null);
    try testing.expect(body != null);

    // 获取各个元素的位置
    const h1 = block.findElement(body.?, "h1", null, null);
    const block_test = block.findElement(body.?, "div", "block-test", null);
    const inline_test = block.findElement(body.?, "div", "inline-test", null);

    try testing.expect(h1 != null);
    try testing.expect(block_test != null);
    try testing.expect(inline_test != null);

    // 验证元素顺序：h1在顶部，block-test在h1下方，inline-test在block-test下方
    const h1_bottom = h1.?.box_model.content.y + h1.?.box_model.content.height;
    const block_test_top = block_test.?.box_model.content.y;
    const block_test_bottom = block_test.?.box_model.content.y + block_test.?.box_model.content.height;
    const inline_test_top = inline_test.?.box_model.content.y;

    // block-test应该在h1下方
    try testing.expect(block_test_top >= h1_bottom - 50); // 允许50像素误差（考虑margin）

    // inline-test应该在block-test下方
    try testing.expect(inline_test_top >= block_test_bottom - 50); // 允许50像素误差
}

