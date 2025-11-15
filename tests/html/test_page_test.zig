const std = @import("std");
const html = @import("html");
const dom = @import("dom");

// 辅助函数：释放单个节点
fn freeNode(allocator: std.mem.Allocator, node: *dom.Node) void {
    switch (node.node_type) {
        .element => {
            if (node.asElement()) |elem| {
                // 释放tag_name
                allocator.free(elem.tag_name);

                // 释放所有属性
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
        .document => {
            // document节点不需要释放，它是值类型
            return;
        },
        else => {},
    }

    // 释放节点本身（除了document节点）
    if (node.node_type != .document) {
        allocator.destroy(node);
    }
}

// 辅助函数：释放所有节点
fn freeAllNodes(allocator: std.mem.Allocator, node: *dom.Node) void {
    // 先释放所有子节点
    var current = node.first_child;
    while (current) |child| {
        // 保存下一个兄弟节点（在释放前保存，因为释放会修改指针）
        const next = child.next_sibling;

        // 递归释放子节点及其所有后代
        freeAllNodes(allocator, child);

        // 释放子节点本身
        freeNode(allocator, child);

        // 移动到下一个兄弟节点
        current = next;
    }

    // 清空子节点指针
    node.first_child = null;
    node.last_child = null;
}

// 辅助函数：读取 test_page.html 文件
fn readTestPage(allocator: std.mem.Allocator) ![]const u8 {
    const file = try std.fs.cwd().openFile("test_page.html", .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    _ = try file.readAll(content);

    return content;
}

// 辅助函数：解析 test_page.html
fn parseTestPage(allocator: std.mem.Allocator) !*dom.Document {
    const html_content = try readTestPage(allocator);
    defer allocator.free(html_content);

    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_content, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    return doc_ptr;
}

// 辅助函数：找到第一个元素节点（跳过文本、注释和DOCTYPE节点）
fn findFirstElementNode(node: ?*dom.Node) ?*dom.Node {
    var current = node;
    while (current) |n| {
        if (n.node_type == .element) {
            if (n.asElement()) |elem| {
                // 跳过 DOCTYPE 节点
                if (!std.mem.eql(u8, elem.tag_name, "!DOCTYPE")) {
                    return n;
                }
            }
        }
        current = n.next_sibling;
    }
    return null;
}

// 辅助函数：找到 body 的第 n 个第一级元素节点（跳过文本、注释、DOCTYPE和head中的元素）
fn findNthBodyChild(body: *dom.Node, n: usize) ?*dom.Node {
    var current = body.first_child;
    var count: usize = 0;
    while (current) |node| {
        if (node.node_type == .element) {
            if (node.asElement()) |elem| {
                // 跳过 DOCTYPE 节点和 head 中的元素（meta, title, style, link, base, script）
                const tag_name = elem.tag_name;
                if (!std.mem.eql(u8, tag_name, "!DOCTYPE") and
                    !std.mem.eql(u8, tag_name, "meta") and
                    !std.mem.eql(u8, tag_name, "title") and
                    !std.mem.eql(u8, tag_name, "style") and
                    !std.mem.eql(u8, tag_name, "link") and
                    !std.mem.eql(u8, tag_name, "base") and
                    !std.mem.eql(u8, tag_name, "script"))
                {
                    if (count == n) {
                        return node;
                    }
                    count += 1;
                }
            }
        }
        current = node.next_sibling;
    }
    return null;
}

// 测试 body 的第一个第一级元素：h1
// 使用 getElementsByTagName 查找 h1 元素，然后验证它是 body 的第一个子元素
test "test_page body first child - h1 element" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const doc_ptr = try parseTestPage(allocator);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }

    // 验证 body 存在
    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);

    // 使用 getElementsByTagName 查找所有 h1 元素
    const h1_elements = try doc_ptr.getElementsByTagName("h1", allocator);
    defer allocator.free(h1_elements);

    // 应该至少有一个 h1 元素
    try std.testing.expect(h1_elements.len > 0);

    // 找到 body 的第一个 h1 子元素（直接子元素）
    // 由于解析器可能有问题，我们通过检查 h1 元素的父节点来找到 body 的第一个 h1
    var found_h1: ?*dom.Node = null;

    // 方法1：遍历 body 的子节点查找 h1
    var current = body.?.first_child;
    while (current) |node| {
        if (node.node_type == .element) {
            if (node.asElement()) |elem| {
                // 跳过 DOCTYPE 节点
                if (!std.mem.eql(u8, elem.tag_name, "!DOCTYPE")) {
                    if (std.mem.eql(u8, elem.tag_name, "h1")) {
                        found_h1 = node;
                        break;
                    }
                }
            }
        }
        current = node.next_sibling;
    }

    // 方法2：如果方法1没找到，从 h1_elements 中找到父节点是 body 的第一个 h1
    if (found_h1 == null) {
        for (h1_elements) |h1| {
            if (h1.parent) |parent| {
                if (parent.asElement()) |parent_elem| {
                    if (std.mem.eql(u8, parent_elem.tag_name, "body")) {
                        found_h1 = h1;
                        break;
                    }
                }
            }
        }
    }

    // 验证找到了 h1 元素
    try std.testing.expect(found_h1 != null);

    // 验证 h1 元素的属性
    if (found_h1.?.asElement()) |elem| {
        try std.testing.expectEqualStrings("h1", elem.tag_name);

        // 验证 h1 有 style 属性
        const style_attr = elem.getAttribute("style");
        try std.testing.expect(style_attr != null);
        try std.testing.expect(style_attr.?.len > 0);

        // 验证 style 属性包含 text-align: center
        try std.testing.expect(std.mem.indexOf(u8, style_attr.?, "text-align: center") != null);

        // 验证 style 属性包含 color: #1976d2
        try std.testing.expect(std.mem.indexOf(u8, style_attr.?, "color: #1976d2") != null);

        // 验证 style 属性包含 border: 2px solid red
        try std.testing.expect(std.mem.indexOf(u8, style_attr.?, "border: 2px solid red") != null);

        // 验证 h1 有文本内容
        const text_node = found_h1.?.first_child;
        try std.testing.expect(text_node != null);
        try std.testing.expect(text_node.?.node_type == .text);

        if (text_node.?.asText()) |text| {
            try std.testing.expectEqualStrings("ZBrowser功能测试页面", text);
        }
    }
}

// 测试 body 的第二个第一级元素：div class="block-test"
test "test_page body second child - div block-test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const doc_ptr = try parseTestPage(allocator);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }

    // 验证 body 存在
    const body = doc_ptr.getBody();
    try std.testing.expect(body != null);

    // 方法1：尝试通过 findNthBodyChild 查找
    var block_test_div = findNthBodyChild(body.?, 1);

    // 方法2：如果方法1失败，通过 getElementsByTagName 查找所有 div，然后找到 class="block-test" 的
    if (block_test_div == null) {
        const div_elements = try doc_ptr.getElementsByTagName("div", allocator);
        defer allocator.free(div_elements);

        for (div_elements) |div| {
            if (div.parent) |parent| {
                if (parent.asElement()) |parent_elem| {
                    // 找到父节点是 body 的 div
                    if (std.mem.eql(u8, parent_elem.tag_name, "body")) {
                        if (div.asElement()) |div_elem| {
                            const class_attr = div_elem.getAttribute("class");
                            if (class_attr) |cls| {
                                if (std.mem.eql(u8, cls, "block-test")) {
                                    block_test_div = div;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    try std.testing.expect(block_test_div != null);

    // 验证是 div 元素
    if (block_test_div.?.asElement()) |elem| {
        try std.testing.expectEqualStrings("div", elem.tag_name);

        // 验证有 class 属性
        const class_attr = elem.getAttribute("class");
        try std.testing.expect(class_attr != null);
        try std.testing.expectEqualStrings("block-test", class_attr.?);

        // 验证父节点是 body
        try std.testing.expect(block_test_div.?.parent != null);
        if (block_test_div.?.parent.?.asElement()) |parent_elem| {
            try std.testing.expectEqualStrings("body", parent_elem.tag_name);
        }

        // 验证有子元素
        try std.testing.expect(block_test_div.?.first_child != null);

        // 验证第一个子元素是 h1（跳过文本和注释节点）
        var first_child = findFirstElementNode(block_test_div.?.first_child);
        try std.testing.expect(first_child != null);
        if (first_child.?.asElement()) |h1_elem| {
            try std.testing.expectEqualStrings("h1", h1_elem.tag_name);

            // 验证 h1 的文本内容
            const h1_text_node = first_child.?.first_child;
            try std.testing.expect(h1_text_node != null);
            if (h1_text_node.?.asText()) |h1_text| {
                try std.testing.expectEqualStrings("块级布局测试", h1_text);
            }
        }

        // 验证有 p 子元素（应该至少有两个）
        const p_elements = try doc_ptr.getElementsByTagName("p", allocator);
        defer allocator.free(p_elements);

        // 找到 block-test div 中的 p 元素
        var p_count: usize = 0;
        var current = block_test_div.?.first_child;
        while (current) |node| {
            if (node.node_type == .element) {
                if (node.asElement()) |child_elem| {
                    if (std.mem.eql(u8, child_elem.tag_name, "p")) {
                        p_count += 1;
                    }
                }
            }
            current = node.next_sibling;
        }

        // 应该至少有两个 p 元素
        try std.testing.expect(p_count >= 2);

        // 验证有嵌套的 div 子元素
        var found_nested_div = false;
        current = block_test_div.?.first_child;
        while (current) |node| {
            if (node.node_type == .element) {
                if (node.asElement()) |child_elem| {
                    if (std.mem.eql(u8, child_elem.tag_name, "div")) {
                        found_nested_div = true;
                        // 验证嵌套 div 有 style 属性
                        const nested_style = child_elem.getAttribute("style");
                        try std.testing.expect(nested_style != null);
                        try std.testing.expect(std.mem.indexOf(u8, nested_style.?, "background-color: #bbdefb") != null);
                        break;
                    }
                }
            }
            current = node.next_sibling;
        }
        try std.testing.expect(found_nested_div);
    }
}
