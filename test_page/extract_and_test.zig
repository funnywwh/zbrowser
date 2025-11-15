const std = @import("std");
const html = @import("html");
const dom = @import("dom");
const allocator_utils = @import("allocator");
const css_parser = @import("parser");
const layout_engine = @import("engine");
const box = @import("box");
const block = @import("block");
const Browser = @import("main").Browser;

const TOLERANCE: f32 = 1.0; // 1px误差范围
const MAX_RETRIES: u32 = 100; // 最大重试次数

/// Box信息结构
const BoxInfo = struct {
    content_box: struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    },
    border_box: struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    },
    padding: struct {
        top: f32,
        right: f32,
        bottom: f32,
        left: f32,
    },
    border: struct {
        top: f32,
        right: f32,
        bottom: f32,
        left: f32,
    },
    margin: struct {
        top: f32,
        right: f32,
        bottom: f32,
        left: f32,
    },
};

/// 从HTML内容中提取CSS（从<style>标签）
fn extractCSSFromHTML(allocator: std.mem.Allocator, html_content: []const u8) !?[]u8 {
    const style_start_tag = "<style";
    const style_end_tag = "</style>";

    // 查找第一个<style>标签的开始位置
    if (std.mem.indexOf(u8, html_content, style_start_tag)) |pos| {
        const after_start = html_content[pos + style_start_tag.len ..];
        const tag_end = std.mem.indexOf(u8, after_start, ">") orelse return null;
        const style_content_start = pos + style_start_tag.len + tag_end + 1;

        // 查找</style>标签
        if (std.mem.indexOf(u8, html_content[style_content_start..], style_end_tag)) |end_offset| {
            const start = style_content_start;
            const end = style_content_start + end_offset;
            const css_content = html_content[start..end];
            const trimmed = std.mem.trim(u8, css_content, " \t\n\r");
            if (trimmed.len > 0) {
                return try allocator.dupe(u8, trimmed);
            }
        }
    }

    return null;
}

/// 提取HTML的head部分（包含style标签）
fn extractHeadSection(allocator: std.mem.Allocator, html_content: []const u8) ![]u8 {
    const head_start_tag = "<head";
    const head_end_tag = "</head>";

    if (std.mem.indexOf(u8, html_content, head_start_tag)) |pos| {
        const after_start = html_content[pos + head_start_tag.len ..];
        const tag_end = std.mem.indexOf(u8, after_start, ">") orelse return try allocator.dupe(u8, "");
        const head_content_start = pos + head_start_tag.len + tag_end + 1;

        if (std.mem.indexOf(u8, html_content[head_content_start..], head_end_tag)) |end_offset| {
            const start = pos;
            const end = head_content_start + end_offset + head_end_tag.len;
            return try allocator.dupe(u8, html_content[start..end]);
        }
    }

    return try allocator.dupe(u8, "");
}

/// 提取body的直接子元素
fn extractBodyChildren(allocator: std.mem.Allocator, document: *dom.Document) !std.ArrayList([]const u8) {
    var children = std.ArrayList([]const u8){};
    children = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    const body = document.getBody() orelse return children;

    // 调试：检查body元素
    if (body.asElement()) |elem| {
        std.debug.print("Body tag: {s}\n", .{elem.tag_name});
    }

    // 遍历body的直接子节点
    // 跳过head中的元素（meta、title、style、link等）
    const skip_tags = [_][]const u8{ "meta", "title", "style", "link", "script", "base" };
    var current = body.first_child;
    var element_count: usize = 0;
    while (current) |node| {
        if (node.node_type == .element) {
            if (node.asElement()) |elem| {
                // 检查是否应该跳过（head中的元素）
                var should_skip = false;
                for (skip_tags) |skip_tag| {
                    if (std.mem.eql(u8, elem.tag_name, skip_tag)) {
                        should_skip = true;
                        break;
                    }
                }
                if (should_skip) {
                    std.debug.print("  Skipping head element: {s}\n", .{elem.tag_name});
                    current = node.next_sibling;
                    continue;
                }
                std.debug.print("  Found body element child: {s}\n", .{elem.tag_name});
                // 获取元素的HTML字符串表示
                // 简化实现：使用outerHTML的概念
                // 这里我们需要序列化元素
                const element_html = try serializeElement(allocator, node);
                try children.append(allocator, element_html);
                element_count += 1;
            }
        } else if (node.node_type == .text) {
            if (node.asText()) |text| {
                const trimmed = std.mem.trim(u8, text, " \t\n\r");
                if (trimmed.len > 0) {
                    std.debug.print("  Found text child: {s}...\n", .{if (trimmed.len > 20) text[0..20] else text});
                }
            }
        }
        current = node.next_sibling;
    }
    
    std.debug.print("Total body element children (after filtering): {d}\n", .{element_count});

    return children;
}

/// 序列化元素为HTML字符串（简化实现）
fn serializeElement(allocator: std.mem.Allocator, node: *dom.Node) ![]u8 {
    if (node.asElement()) |elem| {
        var buffer = std.ArrayList(u8){};
        buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
        defer buffer.deinit(allocator);

        // 写入开始标签
        try buffer.writer(allocator).print("<{s}", .{elem.tag_name});

        // 写入属性
        var attr_iter = elem.attributes.iterator();
        while (attr_iter.next()) |entry| {
            try buffer.writer(allocator).print(" {s}=\"", .{entry.key_ptr.*});
            // 转义属性值中的引号
            for (entry.value_ptr.*) |char| {
                if (char == '"') {
                    try buffer.appendSlice(allocator, "&quot;");
                } else {
                    try buffer.append(allocator, char);
                }
            }
                try buffer.append(allocator, '"');
        }

        try buffer.append(allocator, '>');

        // 写入子节点
        var child = node.first_child;
        while (child) |child_node| {
            if (child_node.node_type == .text) {
                if (child_node.asText()) |text| {
                    // 转义HTML特殊字符
                    for (text) |char| {
                        switch (char) {
                            '<' => try buffer.appendSlice(allocator, "&lt;"),
                            '>' => try buffer.appendSlice(allocator, "&gt;"),
                            '&' => try buffer.appendSlice(allocator, "&amp;"),
                            '"' => try buffer.appendSlice(allocator, "&quot;"),
                            '\'' => try buffer.appendSlice(allocator, "&apos;"),
                            else => try buffer.append(allocator, char),
                        }
                    }
                }
            } else if (child_node.node_type == .element) {
                const child_html = try serializeElement(allocator, child_node);
                defer allocator.free(child_html);
                try buffer.appendSlice(allocator, child_html);
            }
            child = child_node.next_sibling;
        }

        // 写入结束标签
        try buffer.writer(allocator).print("</{s}>", .{elem.tag_name});

        return buffer.toOwnedSlice(allocator);
    } else {
        return try allocator.dupe(u8, "");
    }
}

/// 创建单个元素的HTML文件
fn createElementHTML(allocator: std.mem.Allocator, head_section: []const u8, element_html: []const u8) ![]u8 {
    var buffer = std.ArrayList(u8){};
    buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    try buffer.appendSlice(allocator, "<!DOCTYPE html>\n<html>\n");
    try buffer.appendSlice(allocator, head_section);
    try buffer.appendSlice(allocator, "\n<body>\n");
    try buffer.appendSlice(allocator, element_html);
    try buffer.appendSlice(allocator, "\n</body>\n</html>\n");

    return buffer.toOwnedSlice(allocator);
}

/// 从ZBrowser获取元素的box信息
fn getZBrowserBoxInfo(allocator: std.mem.Allocator, browser: *Browser, viewport_width: f32, viewport_height: f32) !?BoxInfo {
    const engine = layout_engine.LayoutEngine;
    const html_node = browser.document.getDocumentElement() orelse return null;

    // 构建布局树
    var layout_engine_instance = engine.init(allocator);
    const layout_tree = try layout_engine_instance.buildLayoutTree(html_node, browser.stylesheets.items);
    defer {
        engine.cleanupFormattingContexts(layout_tree);
        layout_tree.deinitAndDestroyChildren();
        allocator.destroy(layout_tree);
    }

    // 执行布局计算
    const viewport = box.Size{ .width = viewport_width, .height = viewport_height };
    try layout_engine_instance.layout(layout_tree, viewport, browser.stylesheets.items);

    // 查找body元素
    const body = block.findElement(layout_tree, "body", null, null) orelse return null;

    // 获取body的第一个element子元素（我们测试的元素）
    // 跳过text节点，只获取element节点
    var element: ?*box.LayoutBox = null;
    for (body.children.items) |child| {
        if (child.node.node_type == .element) {
            element = child;
            break;
        }
    }
    const element_box = element orelse return null;

    const box_model = element_box.box_model;

    // 计算border box
    const border_box_x = box_model.content.x - box_model.padding.left - box_model.border.left;
    const border_box_y = box_model.content.y - box_model.padding.top - box_model.border.top;
    const border_box_width = box_model.content.width + box_model.padding.horizontal() + box_model.border.horizontal();
    const border_box_height = box_model.content.height + box_model.padding.vertical() + box_model.border.vertical();

    return BoxInfo{
        .content_box = .{
            .x = box_model.content.x,
            .y = box_model.content.y,
            .width = box_model.content.width,
            .height = box_model.content.height,
        },
        .border_box = .{
            .x = border_box_x,
            .y = border_box_y,
            .width = border_box_width,
            .height = border_box_height,
        },
        .padding = .{
            .top = box_model.padding.top,
            .right = box_model.padding.right,
            .bottom = box_model.padding.bottom,
            .left = box_model.padding.left,
        },
        .border = .{
            .top = box_model.border.top,
            .right = box_model.border.right,
            .bottom = box_model.border.bottom,
            .left = box_model.border.left,
        },
        .margin = .{
            .top = box_model.margin.top,
            .right = box_model.margin.right,
            .bottom = box_model.margin.bottom,
            .left = box_model.margin.left,
        },
    };
}

/// 保存box信息到JSON文件
fn saveBoxInfoToJSON(allocator: std.mem.Allocator, box_info: BoxInfo, file_path: []const u8) !void {
    var buffer = std.ArrayList(u8){};
    buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);
    try writer.print(
        \\{{
        \\  "content_box": {{
        \\    "x": {d:.2},
        \\    "y": {d:.2},
        \\    "width": {d:.2},
        \\    "height": {d:.2}
        \\  }},
        \\  "border_box": {{
        \\    "x": {d:.2},
        \\    "y": {d:.2},
        \\    "width": {d:.2},
        \\    "height": {d:.2}
        \\  }},
        \\  "padding": {{
        \\    "top": {d:.2},
        \\    "right": {d:.2},
        \\    "bottom": {d:.2},
        \\    "left": {d:.2}
        \\  }},
        \\  "border": {{
        \\    "top": {d:.2},
        \\    "right": {d:.2},
        \\    "bottom": {d:.2},
        \\    "left": {d:.2}
        \\  }},
        \\  "margin": {{
        \\    "top": {d:.2},
        \\    "right": {d:.2},
        \\    "bottom": {d:.2},
        \\    "left": {d:.2}
        \\  }}
        \\}}
    , .{
        box_info.content_box.x,
        box_info.content_box.y,
        box_info.content_box.width,
        box_info.content_box.height,
        box_info.border_box.x,
        box_info.border_box.y,
        box_info.border_box.width,
        box_info.border_box.height,
        box_info.padding.top,
        box_info.padding.right,
        box_info.padding.bottom,
        box_info.padding.left,
        box_info.border.top,
        box_info.border.right,
        box_info.border.bottom,
        box_info.border.left,
        box_info.margin.top,
        box_info.margin.right,
        box_info.margin.bottom,
        box_info.margin.left,
    });

    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try file.writeAll(buffer.items);
}

/// 从JSON字符串中解析浮点数
fn parseFloatFromJSON(json: []const u8, key: []const u8) ?f32 {
    // 查找key的位置
    if (std.mem.indexOf(u8, json, key)) |pos| {
        const after_key = json[pos + key.len ..];
        // 查找冒号
        if (std.mem.indexOf(u8, after_key, ":")) |colon_pos| {
            const after_colon = after_key[colon_pos + 1 ..];
            // 跳过空白字符
            var start: usize = 0;
            while (start < after_colon.len and (after_colon[start] == ' ' or after_colon[start] == '\t' or after_colon[start] == '\n' or after_colon[start] == '\r')) {
                start += 1;
            }
            // 解析数字
            var num_str: [100]u8 = undefined;
            var num_len: usize = 0;
            var i = start;
            while (i < after_colon.len) : (i += 1) {
                const char = after_colon[i];
                if (char == ' ' or char == ',' or char == '}' or char == '\n' or char == '\r') {
                    if (num_len > 0) break;
                    continue;
                }
                if ((char >= '0' and char <= '9') or char == '.' or char == '-' or char == '+') {
                    if (num_len < num_str.len) {
                        num_str[num_len] = char;
                        num_len += 1;
                    }
                } else {
                    if (num_len > 0) break;
                }
            }
            if (num_len > 0) {
                const num_slice = num_str[0..num_len];
                return std.fmt.parseFloat(f32, num_slice) catch null;
            }
        }
    }
    return null;
}

/// 读取JSON文件中的box信息
fn readBoxInfoFromJSON(allocator: std.mem.Allocator, file_path: []const u8) !BoxInfo {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    defer allocator.free(content);
    _ = try file.readAll(content);

    var box_info = BoxInfo{
        .content_box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
        .border_box = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
        .padding = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
        .border = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
        .margin = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
    };

    // 查找content_box部分
    if (std.mem.indexOf(u8, content, "\"content_box\"")) |content_start| {
        const content_section = content[content_start..];
        if (parseFloatFromJSON(content_section, "\"x\"")) |val| box_info.content_box.x = val;
        if (parseFloatFromJSON(content_section, "\"y\"")) |val| box_info.content_box.y = val;
        if (parseFloatFromJSON(content_section, "\"width\"")) |val| box_info.content_box.width = val;
        if (parseFloatFromJSON(content_section, "\"height\"")) |val| box_info.content_box.height = val;
    }

    // 查找border_box部分
    if (std.mem.indexOf(u8, content, "\"border_box\"")) |border_start| {
        const border_section = content[border_start..];
        if (parseFloatFromJSON(border_section, "\"x\"")) |val| box_info.border_box.x = val;
        if (parseFloatFromJSON(border_section, "\"y\"")) |val| box_info.border_box.y = val;
        if (parseFloatFromJSON(border_section, "\"width\"")) |val| box_info.border_box.width = val;
        if (parseFloatFromJSON(border_section, "\"height\"")) |val| box_info.border_box.height = val;
    }

    return box_info;
}

/// 对比两个box信息
fn compareBoxes(zbrowser_box: BoxInfo, puppeteer_box: BoxInfo) struct {
    content_box_match: bool,
    border_box_match: bool,
    content_box_diff: struct { x: f32, y: f32, width: f32, height: f32 },
    border_box_diff: struct { x: f32, y: f32, width: f32, height: f32 },
} {
    const calcDiff = struct {
        fn calcDiff(a: f32, b: f32) f32 {
            return if (a > b) a - b else b - a;
        }
    }.calcDiff;

    const content_x_diff = calcDiff(zbrowser_box.content_box.x, puppeteer_box.content_box.x);
    const content_y_diff = calcDiff(zbrowser_box.content_box.y, puppeteer_box.content_box.y);
    const content_width_diff = calcDiff(zbrowser_box.content_box.width, puppeteer_box.content_box.width);
    const content_height_diff = calcDiff(zbrowser_box.content_box.height, puppeteer_box.content_box.height);

    const border_x_diff = calcDiff(zbrowser_box.border_box.x, puppeteer_box.border_box.x);
    const border_y_diff = calcDiff(zbrowser_box.border_box.y, puppeteer_box.border_box.y);
    const border_width_diff = calcDiff(zbrowser_box.border_box.width, puppeteer_box.border_box.width);
    const border_height_diff = calcDiff(zbrowser_box.border_box.height, puppeteer_box.border_box.height);

    const content_box_match = content_x_diff <= TOLERANCE and
        content_y_diff <= TOLERANCE and
        content_width_diff <= TOLERANCE and
        content_height_diff <= TOLERANCE;

    const border_box_match = border_x_diff <= TOLERANCE and
        border_y_diff <= TOLERANCE and
        border_width_diff <= TOLERANCE and
        border_height_diff <= TOLERANCE;

    return .{
        .content_box_match = content_box_match,
        .border_box_match = border_box_match,
        .content_box_diff = .{
            .x = content_x_diff,
            .y = content_y_diff,
            .width = content_width_diff,
            .height = content_height_diff,
        },
        .border_box_diff = .{
            .x = border_x_diff,
            .y = border_y_diff,
            .width = border_width_diff,
            .height = border_height_diff,
        },
    };
}

/// 生成修复日志
fn generateFixLog(allocator: std.mem.Allocator, element_index: usize, element_tag: []const u8, element_class: ?[]const u8, element_id: ?[]const u8, zbrowser_box: BoxInfo, puppeteer_box: BoxInfo, comparison: anytype) ![]u8 {
    var buffer = std.ArrayList(u8){};
    buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);
    try writer.print("Element: {s} (index: {d})\n", .{ element_tag, element_index });
    if (element_class) |class| {
        try writer.print("Class: {s}\n", .{class});
    }
    if (element_id) |id| {
        try writer.print("ID: {s}\n", .{id});
    }
    try writer.print("\n", .{});

    // Content Box对比
    try writer.print("Content Box Comparison:\n", .{});
    try writer.print("  x: ZBrowser={d:.2}, Puppeteer={d:.2}, diff={d:.2} {s}\n", .{
        zbrowser_box.content_box.x,
        puppeteer_box.content_box.x,
        comparison.content_box_diff.x,
        if (comparison.content_box_diff.x <= TOLERANCE) "✓" else "✗",
    });
    try writer.print("  y: ZBrowser={d:.2}, Puppeteer={d:.2}, diff={d:.2} {s}\n", .{
        zbrowser_box.content_box.y,
        puppeteer_box.content_box.y,
        comparison.content_box_diff.y,
        if (comparison.content_box_diff.y <= TOLERANCE) "✓" else "✗",
    });
    try writer.print("  width: ZBrowser={d:.2}, Puppeteer={d:.2}, diff={d:.2} {s}\n", .{
        zbrowser_box.content_box.width,
        puppeteer_box.content_box.width,
        comparison.content_box_diff.width,
        if (comparison.content_box_diff.width <= TOLERANCE) "✓" else "✗",
    });
    try writer.print("  height: ZBrowser={d:.2}, Puppeteer={d:.2}, diff={d:.2} {s}\n", .{
        zbrowser_box.content_box.height,
        puppeteer_box.content_box.height,
        comparison.content_box_diff.height,
        if (comparison.content_box_diff.height <= TOLERANCE) "✓" else "✗",
    });

    // Border Box对比
    try writer.print("\nBorder Box Comparison:\n", .{});
    try writer.print("  x: ZBrowser={d:.2}, Puppeteer={d:.2}, diff={d:.2} {s}\n", .{
        zbrowser_box.border_box.x,
        puppeteer_box.border_box.x,
        comparison.border_box_diff.x,
        if (comparison.border_box_diff.x <= TOLERANCE) "✓" else "✗",
    });
    try writer.print("  y: ZBrowser={d:.2}, Puppeteer={d:.2}, diff={d:.2} {s}\n", .{
        zbrowser_box.border_box.y,
        puppeteer_box.border_box.y,
        comparison.border_box_diff.y,
        if (comparison.border_box_diff.y <= TOLERANCE) "✓" else "✗",
    });
    try writer.print("  width: ZBrowser={d:.2}, Puppeteer={d:.2}, diff={d:.2} {s}\n", .{
        zbrowser_box.border_box.width,
        puppeteer_box.border_box.width,
        comparison.border_box_diff.width,
        if (comparison.border_box_diff.width <= TOLERANCE) "✓" else "✗",
    });
    try writer.print("  height: ZBrowser={d:.2}, Puppeteer={d:.2}, diff={d:.2} {s}\n", .{
        zbrowser_box.border_box.height,
        puppeteer_box.border_box.height,
        comparison.border_box_diff.height,
        if (comparison.border_box_diff.height <= TOLERANCE) "✓" else "✗",
    });

    // 可能的问题原因
    try writer.print("\nPossible Issues:\n", .{});
    if (comparison.content_box_diff.y > TOLERANCE or comparison.border_box_diff.y > TOLERANCE) {
        try writer.print("  - Vertical positioning calculation may be incorrect\n", .{});
    }
    if (comparison.content_box_diff.x > TOLERANCE or comparison.border_box_diff.x > TOLERANCE) {
        try writer.print("  - Horizontal positioning calculation may be incorrect\n", .{});
    }
    if (comparison.content_box_diff.width > TOLERANCE or comparison.border_box_diff.width > TOLERANCE) {
        try writer.print("  - Width calculation may need adjustment\n", .{});
    }
    if (comparison.content_box_diff.height > TOLERANCE or comparison.border_box_diff.height > TOLERANCE) {
        try writer.print("  - Height calculation may need adjustment\n", .{});
    }

    // 修复建议
    try writer.print("\nSuggested Fix Locations:\n", .{});
    try writer.print("  - src/layout/block.zig: check layout calculation\n", .{});
    try writer.print("  - src/layout/box.zig: check box model calculation\n", .{});
    try writer.print("  - src/layout/style_utils.zig: check padding/border/margin parsing\n", .{});

    return buffer.toOwnedSlice(allocator);
}

/// 运行Puppeteer脚本
fn runPuppeteerScript(allocator: std.mem.Allocator, html_file_path: []const u8, output_dir: []const u8) !void {
    const script_path = "puppeteer_runner.js";
    const args = [_][]const u8{ "node", script_path, html_file_path, output_dir };

    var process = std.process.Child.init(&args, allocator);
    process.stdin_behavior = .Ignore;
    process.stdout_behavior = .Ignore;
    process.stderr_behavior = .Pipe;

    try process.spawn();
    
    // 读取stderr
    const stderr = try process.stderr.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);

    const term = try process.wait();
    if (term != .Exited or term.Exited != 0) {
        std.debug.print("Puppeteer script failed: {s}\n", .{stderr});
        return error.PuppeteerScriptFailed;
    }
}

/// 运行对比脚本
fn runCompareScript(allocator: std.mem.Allocator, zbrowser_box_path: []const u8, puppeteer_box_path: []const u8, output_path: []const u8) !void {
    const script_path = "compare_boxes.js";
    const args = [_][]const u8{ "node", script_path, zbrowser_box_path, puppeteer_box_path, output_path };

    var process = std.process.Child.init(&args, allocator);
    process.stdin_behavior = .Ignore;
    process.stdout_behavior = .Ignore;
    process.stderr_behavior = .Pipe;

    try process.spawn();
    
    // 读取stderr
    const stderr = try process.stderr.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);

    const term = try process.wait();
    if (term != .Exited or term.Exited != 0) {
        std.debug.print("Compare script failed: {s}\n", .{stderr});
        return error.CompareScriptFailed;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 读取test_page.html
    const html_file = try std.fs.cwd().openFile("test_page.html", .{});
    defer html_file.close();

    const html_content = try html_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(html_content);

    // 提取head部分和CSS
    const head_section = try extractHeadSection(allocator, html_content);
    defer allocator.free(head_section);

    const css_content = try extractCSSFromHTML(allocator, html_content);
    defer if (css_content) |css| allocator.free(css);

    // 解析HTML获取body的直接子元素
    var browser = try Browser.init(allocator);
    defer browser.deinit();

    try browser.loadHTML(html_content);
    if (css_content) |css| {
        try browser.addStylesheet(css);
    }

    var body_children = try extractBodyChildren(allocator, browser.document);
    defer {
        for (body_children.items) |child| {
            allocator.free(child);
        }
        body_children.deinit(allocator);
    }

    std.debug.print("Found {d} body children\n", .{body_children.items.len});
    
    // 调试：打印前几个元素的标签
    for (body_children.items, 0..) |child_html, i| {
        if (i < 3) {
            const preview = if (child_html.len > 50) child_html[0..50] else child_html;
            std.debug.print("  Element {d}: {s}...\n", .{ i, preview });
        }
    }

    // 视口大小
    const viewport_width: f32 = 980;
    const viewport_height: f32 = 8000;

    // 遍历每个子元素
    for (body_children.items, 0..) |element_html, index| {
        std.debug.print("\n=== Testing element {d} ===\n", .{index});

        var retry_count: u32 = 0;
        var passed = false;

        while (retry_count < MAX_RETRIES and !passed) {
            // 创建结果目录
            const result_dir = try std.fmt.allocPrint(allocator, "results/element_{d}", .{index});
            defer allocator.free(result_dir);
            try std.fs.cwd().makePath(result_dir);

            // 创建元素的HTML文件
            const element_html_file = try std.fmt.allocPrint(allocator, "{s}/element.html", .{result_dir});
            defer allocator.free(element_html_file);

            const full_html = try createElementHTML(allocator, head_section, element_html);
            defer allocator.free(full_html);

            const element_file = try std.fs.cwd().createFile(element_html_file, .{});
            defer element_file.close();
            try element_file.writeAll(full_html);

            // 使用ZBrowser渲染
            var test_browser = try Browser.init(allocator);
            defer test_browser.deinit();

            try test_browser.loadHTML(full_html);
            if (css_content) |css| {
                try test_browser.addStylesheet(css);
            }

            const zbrowser_png_path = try std.fmt.allocPrint(allocator, "{s}/zbrowser.png", .{result_dir});
            defer allocator.free(zbrowser_png_path);

            try test_browser.renderToPNG(@as(u32, @intFromFloat(viewport_width)), @as(u32, @intFromFloat(viewport_height)), zbrowser_png_path);

            // 获取ZBrowser的box信息
            const zbrowser_box = (try getZBrowserBoxInfo(allocator, &test_browser, viewport_width, viewport_height)) orelse {
                std.debug.print("Failed to get ZBrowser box info\n", .{});
                retry_count += 1;
                continue;
            };

            const zbrowser_box_path = try std.fmt.allocPrint(allocator, "{s}/zbrowser_box.json", .{result_dir});
            defer allocator.free(zbrowser_box_path);
            try saveBoxInfoToJSON(allocator, zbrowser_box, zbrowser_box_path);

            // 运行Puppeteer脚本
            try runPuppeteerScript(allocator, element_html_file, result_dir);

            // 读取Puppeteer的box信息
            const puppeteer_box_path = try std.fmt.allocPrint(allocator, "{s}/puppeteer_box.json", .{result_dir});
            defer allocator.free(puppeteer_box_path);

            const puppeteer_box = readBoxInfoFromJSON(allocator, puppeteer_box_path) catch |err| {
                std.debug.print("Failed to read Puppeteer box info: {}\n", .{err});
                retry_count += 1;
                continue;
            };

            // 对比box信息
            const comparison = compareBoxes(zbrowser_box, puppeteer_box);

            // 保存对比结果
            const comparison_path = try std.fmt.allocPrint(allocator, "{s}/comparison.json", .{result_dir});
            defer allocator.free(comparison_path);

            var comparison_buffer = std.ArrayList(u8){};
            comparison_buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
            defer comparison_buffer.deinit(allocator);
            try comparison_buffer.writer(allocator).print(
                \\{{
                \\  "element_index": {d},
                \\  "content_box_match": {},
                \\  "border_box_match": {},
                \\  "content_box_diff": {{
                \\    "x": {d:.2},
                \\    "y": {d:.2},
                \\    "width": {d:.2},
                \\    "height": {d:.2}
                \\  }},
                \\  "border_box_diff": {{
                \\    "x": {d:.2},
                \\    "y": {d:.2},
                \\    "width": {d:.2},
                \\    "height": {d:.2}
                \\  }}
                \\}}
            , .{
                index,
                comparison.content_box_match,
                comparison.border_box_match,
                comparison.content_box_diff.x,
                comparison.content_box_diff.y,
                comparison.content_box_diff.width,
                comparison.content_box_diff.height,
                comparison.border_box_diff.x,
                comparison.border_box_diff.y,
                comparison.border_box_diff.width,
                comparison.border_box_diff.height,
            });

            const comparison_file = try std.fs.cwd().createFile(comparison_path, .{});
            defer comparison_file.close();
            try comparison_file.writeAll(comparison_buffer.items);

            // 检查是否通过
            if (comparison.content_box_match and comparison.border_box_match) {
                std.debug.print("Element {d} passed!\n", .{index});
                passed = true;
            } else {
                // 生成修复日志
                const body = browser.document.getBody() orelse return error.NoBody;
                var element_node: ?*dom.Node = null;
                var current = body.first_child;
                var node_index: usize = 0;
                while (current) |node| {
                    if (node.node_type == .element) {
                        if (node_index == index) {
                            element_node = node;
                            break;
                        }
                        node_index += 1;
                    }
                    current = node.next_sibling;
                }

                const element_tag = if (element_node) |node| blk: {
                    if (node.asElement()) |elem| {
                        break :blk elem.tag_name;
                    }
                    break :blk "unknown";
                } else "unknown";

                const element_class = if (element_node) |node| blk: {
                    if (node.asElement()) |elem| {
                        if (elem.attributes.get("class")) |class| {
                            break :blk class;
                        }
                    }
                    break :blk null;
                } else null;

                const element_id = if (element_node) |node| blk: {
                    if (node.asElement()) |elem| {
                        if (elem.attributes.get("id")) |id| {
                            break :blk id;
                        }
                    }
                    break :blk null;
                } else null;

                const fix_log = try generateFixLog(allocator, index, element_tag, element_class, element_id, zbrowser_box, puppeteer_box, comparison);
                defer allocator.free(fix_log);

                const fix_log_path = try std.fmt.allocPrint(allocator, "{s}/fix_log.txt", .{result_dir});
                defer allocator.free(fix_log_path);

                const fix_log_file = try std.fs.cwd().createFile(fix_log_path, .{});
                defer fix_log_file.close();
                try fix_log_file.writeAll(fix_log);

                std.debug.print("\nElement {d} failed validation!\n", .{index});
                std.debug.print("Fix log saved to: {s}\n", .{fix_log_path});
                std.debug.print("\nPlease fix the issue and re-run the test...\n", .{});
                std.debug.print("Press Ctrl+C to exit, or fix the code and re-run.\n", .{});
                
                // 简化：直接退出，让用户修复后重新运行
                return error.FixRequired;
            }
        }

        if (!passed) {
            std.debug.print("Element {d} failed after {d} retries. Skipping to next element.\n", .{ index, retry_count });
        }
    }

    std.debug.print("\nAll elements tested!\n", .{});
}

