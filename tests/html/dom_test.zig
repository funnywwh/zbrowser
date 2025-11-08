const std = @import("std");
const dom = @import("dom");

test "create document" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const doc = try dom.Document.init(allocator);
    std.debug.assert(doc.node.node_type == .document);
}

test "create element node" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var elem_data = try dom.ElementData.init(allocator, "div");
    defer elem_data.deinit(allocator);

    const node = try allocator.create(dom.Node);
    defer allocator.destroy(node);
    node.* = .{
        .node_type = .element,
        .data = .{ .element = elem_data },
    };

    std.debug.assert(node.node_type == .element);
    const elem = node.asElement();
    std.debug.assert(elem != null);
    std.debug.assert(std.mem.eql(u8, elem.?.tag_name, "div"));
}

test "create text node" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const text_content = try allocator.dupe(u8, "Hello World");
    defer allocator.free(text_content);

    const node = try allocator.create(dom.Node);
    defer allocator.destroy(node);
    node.* = .{
        .node_type = .text,
        .data = .{ .text = text_content },
    };

    std.debug.assert(node.node_type == .text);
    const text = node.asText();
    std.debug.assert(text != null);
    std.debug.assert(std.mem.eql(u8, text.?, "Hello World"));
}

test "append child node" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parent_elem = try dom.ElementData.init(allocator, "div");
    defer parent_elem.deinit(allocator);
    const parent = try allocator.create(dom.Node);
    defer allocator.destroy(parent);
    parent.* = .{
        .node_type = .element,
        .data = .{ .element = parent_elem },
    };

    var child_elem = try dom.ElementData.init(allocator, "p");
    defer child_elem.deinit(allocator);
    const child = try allocator.create(dom.Node);
    defer allocator.destroy(child);
    child.* = .{
        .node_type = .element,
        .data = .{ .element = child_elem },
    };

    try parent.appendChild(child, allocator);

    std.debug.assert(parent.first_child == child);
    std.debug.assert(parent.last_child == child);
    std.debug.assert(child.parent == parent);
}

test "append multiple children" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parent_elem = try dom.ElementData.init(allocator, "div");
    defer parent_elem.deinit(allocator);
    const parent = try allocator.create(dom.Node);
    defer allocator.destroy(parent);
    parent.* = .{
        .node_type = .element,
        .data = .{ .element = parent_elem },
    };

    var child1_elem = try dom.ElementData.init(allocator, "p");
    defer child1_elem.deinit(allocator);
    const child1 = try allocator.create(dom.Node);
    defer allocator.destroy(child1);
    child1.* = .{
        .node_type = .element,
        .data = .{ .element = child1_elem },
    };

    var child2_elem = try dom.ElementData.init(allocator, "span");
    defer child2_elem.deinit(allocator);
    const child2 = try allocator.create(dom.Node);
    defer allocator.destroy(child2);
    child2.* = .{
        .node_type = .element,
        .data = .{ .element = child2_elem },
    };

    try parent.appendChild(child1, allocator);
    try parent.appendChild(child2, allocator);

    std.debug.assert(parent.first_child == child1);
    std.debug.assert(parent.last_child == child2);
    std.debug.assert(child1.next_sibling == child2);
    std.debug.assert(child2.prev_sibling == child1);
}

test "remove child node" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parent_elem = try dom.ElementData.init(allocator, "div");
    defer parent_elem.deinit(allocator);
    const parent = try allocator.create(dom.Node);
    defer allocator.destroy(parent);
    parent.* = .{
        .node_type = .element,
        .data = .{ .element = parent_elem },
    };

    var child_elem = try dom.ElementData.init(allocator, "p");
    defer child_elem.deinit(allocator);
    const child = try allocator.create(dom.Node);
    defer allocator.destroy(child);
    child.* = .{
        .node_type = .element,
        .data = .{ .element = child_elem },
    };

    try parent.appendChild(child, allocator);
    parent.removeChild(child);

    std.debug.assert(parent.first_child == null);
    std.debug.assert(parent.last_child == null);
    std.debug.assert(child.parent == null);
    std.debug.assert(child.prev_sibling == null);
    std.debug.assert(child.next_sibling == null);
}

test "element getAttribute and setAttribute" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var elem = try dom.ElementData.init(allocator, "div");
    defer elem.deinit(allocator);

    try elem.setAttribute("class", "container", allocator);
    const class_attr = elem.getAttribute("class");
    std.debug.assert(class_attr != null);
    std.debug.assert(std.mem.eql(u8, class_attr.?, "container"));
}

test "element hasAttribute" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var elem = try dom.ElementData.init(allocator, "div");
    defer elem.deinit(allocator);

    std.debug.assert(!elem.hasAttribute("id"));
    try elem.setAttribute("id", "test", allocator);
    std.debug.assert(elem.hasAttribute("id"));
}

test "element getId" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var elem = try dom.ElementData.init(allocator, "div");
    defer elem.deinit(allocator);

    std.debug.assert(elem.getId() == null);
    try elem.setAttribute("id", "myId", allocator);
    const id = elem.getId();
    std.debug.assert(id != null);
    std.debug.assert(std.mem.eql(u8, id.?, "myId"));
}

test "element getClasses" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var elem = try dom.ElementData.init(allocator, "div");
    defer elem.deinit(allocator);

    try elem.setAttribute("class", "container main active", allocator);
    const classes = try elem.getClasses(allocator);
    defer allocator.free(classes);

    std.debug.assert(classes.len == 3);
    std.debug.assert(std.mem.eql(u8, classes[0], "container"));
    std.debug.assert(std.mem.eql(u8, classes[1], "main"));
    std.debug.assert(std.mem.eql(u8, classes[2], "active"));
}

test "element getClasses with empty class" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var elem = try dom.ElementData.init(allocator, "div");
    defer elem.deinit(allocator);

    const classes = try elem.getClasses(allocator);
    defer allocator.free(classes);

    std.debug.assert(classes.len == 0);
}

test "querySelector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parent_elem = try dom.ElementData.init(allocator, "div");
    defer parent_elem.deinit(allocator);
    const parent = try allocator.create(dom.Node);
    defer allocator.destroy(parent);
    parent.* = .{
        .node_type = .element,
        .data = .{ .element = parent_elem },
    };

    var child_elem = try dom.ElementData.init(allocator, "p");
    defer child_elem.deinit(allocator);
    const child = try allocator.create(dom.Node);
    defer allocator.destroy(child);
    child.* = .{
        .node_type = .element,
        .data = .{ .element = child_elem },
    };

    try parent.appendChild(child, allocator);

    const found = parent.querySelector("p");
    std.debug.assert(found != null);
    std.debug.assert(found == child);
}

test "getChildren" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parent_elem = try dom.ElementData.init(allocator, "div");
    defer parent_elem.deinit(allocator);
    const parent = try allocator.create(dom.Node);
    defer allocator.destroy(parent);
    parent.* = .{
        .node_type = .element,
        .data = .{ .element = parent_elem },
    };

    var child1_elem = try dom.ElementData.init(allocator, "p");
    defer child1_elem.deinit(allocator);
    const child1 = try allocator.create(dom.Node);
    defer allocator.destroy(child1);
    child1.* = .{
        .node_type = .element,
        .data = .{ .element = child1_elem },
    };

    var child2_elem = try dom.ElementData.init(allocator, "span");
    defer child2_elem.deinit(allocator);
    const child2 = try allocator.create(dom.Node);
    defer allocator.destroy(child2);
    child2.* = .{
        .node_type = .element,
        .data = .{ .element = child2_elem },
    };

    try parent.appendChild(child1, allocator);
    try parent.appendChild(child2, allocator);

    const children = try parent.getChildren(allocator);
    defer allocator.free(children);

    std.debug.assert(children.len == 2);
    std.debug.assert(children[0] == child1);
    std.debug.assert(children[1] == child2);
}

test "document getElementById" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        doc_ptr.deinit();
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    const html_elem_data = try dom.ElementData.init(allocator, "html");
    // 注意：不要在这里调用 deinit，因为数据会被移动到节点中
    const html_node = try allocator.create(dom.Node);
    // 注意：不要使用 defer destroy，因为节点会被 doc_ptr.deinit() 释放
    html_node.* = .{
        .node_type = .element,
        .data = .{ .element = html_elem_data },
    };

    var body_elem_data = try dom.ElementData.init(allocator, "body");
    // 注意：不要在这里调用 deinit，因为数据会被移动到节点中
    try body_elem_data.setAttribute("id", "main-body", allocator);
    const body_node = try allocator.create(dom.Node);
    // 注意：不要使用 defer destroy，因为节点会被 doc_ptr.deinit() 释放
    body_node.* = .{
        .node_type = .element,
        .data = .{ .element = body_elem_data },
    };

    try doc_ptr.node.appendChild(html_node, allocator);
    try html_node.appendChild(body_node, allocator);

    const found = doc_ptr.getElementById("main-body");
    std.debug.assert(found != null);
    std.debug.assert(found == body_node);

    // 在 doc_ptr.deinit() 之前，先从文档树中移除节点
    // 然后手动释放节点（因为节点是通过 allocator.create 创建的）
    doc_ptr.node.removeChild(html_node);
    // 释放节点数据（因为 doc_ptr.deinit() 不会释放这些节点）
    if (body_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    if (html_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    allocator.destroy(body_node);
    allocator.destroy(html_node);
}

test "document querySelectorAll" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        doc_ptr.deinit();
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    const html_elem_data = try dom.ElementData.init(allocator, "html");
    // 注意：不要在这里调用 deinit，因为数据会被移动到节点中
    const html_node = try allocator.create(dom.Node);
    // 注意：不要使用 defer destroy，因为节点会被 doc_ptr.deinit() 释放
    html_node.* = .{
        .node_type = .element,
        .data = .{ .element = html_elem_data },
    };

    const div1_elem_data = try dom.ElementData.init(allocator, "div");
    // 注意：不要在这里调用 deinit，因为数据会被移动到节点中
    const div1_node = try allocator.create(dom.Node);
    // 注意：不要使用 defer destroy，因为节点会被 doc_ptr.deinit() 释放
    div1_node.* = .{
        .node_type = .element,
        .data = .{ .element = div1_elem_data },
    };

    const div2_elem_data = try dom.ElementData.init(allocator, "div");
    // 注意：不要在这里调用 deinit，因为数据会被移动到节点中
    const div2_node = try allocator.create(dom.Node);
    // 注意：不要使用 defer destroy，因为节点会被 doc_ptr.deinit() 释放
    div2_node.* = .{
        .node_type = .element,
        .data = .{ .element = div2_elem_data },
    };

    try doc_ptr.node.appendChild(html_node, allocator);
    try html_node.appendChild(div1_node, allocator);
    try html_node.appendChild(div2_node, allocator);

    const divs = try doc_ptr.querySelectorAll("div", allocator);
    defer allocator.free(divs);

    std.debug.assert(divs.len == 2);

    // 在 doc_ptr.deinit() 之前，先从文档树中移除节点
    // 然后手动释放节点（因为节点是通过 allocator.create 创建的）
    html_node.removeChild(div2_node);
    html_node.removeChild(div1_node);
    doc_ptr.node.removeChild(html_node);
    // 释放节点数据（因为 doc_ptr.deinit() 不会释放这些节点）
    if (div2_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    if (div1_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    if (html_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    allocator.destroy(div2_node);
    allocator.destroy(div1_node);
    allocator.destroy(html_node);
}

test "document getElementsByClassName" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        doc_ptr.deinit();
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    const html_elem_data = try dom.ElementData.init(allocator, "html");
    // 注意：不要在这里调用 deinit，因为数据会被移动到节点中
    const html_node = try allocator.create(dom.Node);
    // 注意：不要使用 defer destroy，因为节点会被 doc_ptr.deinit() 释放
    html_node.* = .{
        .node_type = .element,
        .data = .{ .element = html_elem_data },
    };

    var div1_elem_data = try dom.ElementData.init(allocator, "div");
    // 注意：不要在这里调用 deinit，因为数据会被移动到节点中
    try div1_elem_data.setAttribute("class", "container", allocator);
    const div1_node = try allocator.create(dom.Node);
    // 注意：不要使用 defer destroy，因为节点会被 doc_ptr.deinit() 释放
    div1_node.* = .{
        .node_type = .element,
        .data = .{ .element = div1_elem_data },
    };

    var div2_elem_data = try dom.ElementData.init(allocator, "div");
    // 注意：不要在这里调用 deinit，因为数据会被移动到节点中
    try div2_elem_data.setAttribute("class", "container main", allocator);
    const div2_node = try allocator.create(dom.Node);
    // 注意：不要使用 defer destroy，因为节点会被 doc_ptr.deinit() 释放
    div2_node.* = .{
        .node_type = .element,
        .data = .{ .element = div2_elem_data },
    };

    try doc_ptr.node.appendChild(html_node, allocator);
    try html_node.appendChild(div1_node, allocator);
    try html_node.appendChild(div2_node, allocator);

    const containers = try doc_ptr.getElementsByClassName("container", allocator);
    defer allocator.free(containers);

    std.debug.assert(containers.len == 2);

    // 在 doc_ptr.deinit() 之前，先从文档树中移除节点
    // 然后手动释放节点（因为节点是通过 allocator.create 创建的）
    html_node.removeChild(div2_node);
    html_node.removeChild(div1_node);
    doc_ptr.node.removeChild(html_node);
    // 释放节点数据（因为 doc_ptr.deinit() 不会释放这些节点）
    if (div2_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    if (div1_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    if (html_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    allocator.destroy(div2_node);
    allocator.destroy(div1_node);
    allocator.destroy(html_node);
}

test "document getDocumentElement" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        doc_ptr.deinit();
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    // 测试没有html元素时返回null
    const html_elem1 = doc_ptr.getDocumentElement();
    try std.testing.expect(html_elem1 == null);

    // 添加html元素
    const html_elem_data = try dom.ElementData.init(allocator, "html");
    const html_node = try allocator.create(dom.Node);
    html_node.* = .{
        .node_type = .element,
        .data = .{ .element = html_elem_data },
    };

    try doc_ptr.node.appendChild(html_node, allocator);

    // 测试有html元素时返回正确节点
    const html_elem2 = doc_ptr.getDocumentElement();
    try std.testing.expect(html_elem2 != null);
    try std.testing.expect(html_elem2 == html_node);

    // 清理
    doc_ptr.node.removeChild(html_node);
    if (html_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    allocator.destroy(html_node);
}

test "document getHead" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        doc_ptr.deinit();
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    // 测试没有html元素时返回null
    const head1 = doc_ptr.getHead();
    try std.testing.expect(head1 == null);

    // 添加html和head元素
    const html_elem_data = try dom.ElementData.init(allocator, "html");
    const html_node = try allocator.create(dom.Node);
    html_node.* = .{
        .node_type = .element,
        .data = .{ .element = html_elem_data },
    };

    const head_elem_data = try dom.ElementData.init(allocator, "head");
    const head_node = try allocator.create(dom.Node);
    head_node.* = .{
        .node_type = .element,
        .data = .{ .element = head_elem_data },
    };

    try doc_ptr.node.appendChild(html_node, allocator);
    try html_node.appendChild(head_node, allocator);

    // 测试有head元素时返回正确节点
    const head2 = doc_ptr.getHead();
    try std.testing.expect(head2 != null);
    try std.testing.expect(head2 == head_node);

    // 测试没有head元素时返回null
    html_node.removeChild(head_node);
    const head3 = doc_ptr.getHead();
    try std.testing.expect(head3 == null);

    // 清理
    if (head_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    allocator.destroy(head_node);
    doc_ptr.node.removeChild(html_node);
    if (html_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    allocator.destroy(html_node);
}

test "document getBody" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        doc_ptr.deinit();
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    // 测试没有html元素时返回null
    const body1 = doc_ptr.getBody();
    try std.testing.expect(body1 == null);

    // 添加html和body元素
    const html_elem_data = try dom.ElementData.init(allocator, "html");
    const html_node = try allocator.create(dom.Node);
    html_node.* = .{
        .node_type = .element,
        .data = .{ .element = html_elem_data },
    };

    const body_elem_data = try dom.ElementData.init(allocator, "body");
    const body_node = try allocator.create(dom.Node);
    body_node.* = .{
        .node_type = .element,
        .data = .{ .element = body_elem_data },
    };

    try doc_ptr.node.appendChild(html_node, allocator);
    try html_node.appendChild(body_node, allocator);

    // 测试有body元素时返回正确节点
    const body2 = doc_ptr.getBody();
    try std.testing.expect(body2 != null);
    try std.testing.expect(body2 == body_node);

    // 测试没有body元素时返回null
    html_node.removeChild(body_node);
    const body3 = doc_ptr.getBody();
    try std.testing.expect(body3 == null);

    // 清理
    if (body_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    allocator.destroy(body_node);
    doc_ptr.node.removeChild(html_node);
    if (html_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    allocator.destroy(html_node);
}

test "document getElementsByTagName" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        doc_ptr.deinit();
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    // 测试没有匹配元素时返回空数组
    const empty_divs = try doc_ptr.getElementsByTagName("div", allocator);
    defer allocator.free(empty_divs);
    try std.testing.expect(empty_divs.len == 0);

    // 添加html和多个div元素
    const html_elem_data = try dom.ElementData.init(allocator, "html");
    const html_node = try allocator.create(dom.Node);
    html_node.* = .{
        .node_type = .element,
        .data = .{ .element = html_elem_data },
    };

    const div1_elem_data = try dom.ElementData.init(allocator, "div");
    const div1_node = try allocator.create(dom.Node);
    div1_node.* = .{
        .node_type = .element,
        .data = .{ .element = div1_elem_data },
    };

    const div2_elem_data = try dom.ElementData.init(allocator, "div");
    const div2_node = try allocator.create(dom.Node);
    div2_node.* = .{
        .node_type = .element,
        .data = .{ .element = div2_elem_data },
    };

    const span_elem_data = try dom.ElementData.init(allocator, "span");
    const span_node = try allocator.create(dom.Node);
    span_node.* = .{
        .node_type = .element,
        .data = .{ .element = span_elem_data },
    };

    try doc_ptr.node.appendChild(html_node, allocator);
    try html_node.appendChild(div1_node, allocator);
    try html_node.appendChild(div2_node, allocator);
    try html_node.appendChild(span_node, allocator);

    // 测试找到多个匹配元素
    const divs = try doc_ptr.getElementsByTagName("div", allocator);
    defer allocator.free(divs);
    try std.testing.expect(divs.len == 2);
    try std.testing.expect(divs[0] == div1_node);
    try std.testing.expect(divs[1] == div2_node);

    // 测试查找span元素
    const spans = try doc_ptr.getElementsByTagName("span", allocator);
    defer allocator.free(spans);
    try std.testing.expect(spans.len == 1);
    try std.testing.expect(spans[0] == span_node);

    // 清理
    html_node.removeChild(span_node);
    html_node.removeChild(div2_node);
    html_node.removeChild(div1_node);
    doc_ptr.node.removeChild(html_node);
    if (span_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    if (div2_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    if (div1_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    if (html_node.asElement()) |elem| {
        elem.deinit(allocator);
    }
    allocator.destroy(span_node);
    allocator.destroy(div2_node);
    allocator.destroy(div1_node);
    allocator.destroy(html_node);
}

test "elementData getClasses edge cases" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var elem = try dom.ElementData.init(allocator, "div");
    defer elem.deinit(allocator);

    // 测试多个连续空格
    try elem.setAttribute("class", "container    main  active", allocator);
    const classes1 = try elem.getClasses(allocator);
    defer allocator.free(classes1);
    try std.testing.expect(classes1.len == 3);
    try std.testing.expect(std.mem.eql(u8, classes1[0], "container"));
    try std.testing.expect(std.mem.eql(u8, classes1[1], "main"));
    try std.testing.expect(std.mem.eql(u8, classes1[2], "active"));

    // 测试只有空格的class属性（setAttribute现在会正确释放旧值）
    try elem.setAttribute("class", "   ", allocator);
    const classes2 = try elem.getClasses(allocator);
    defer allocator.free(classes2);
    try std.testing.expect(classes2.len == 0);

    // 测试前后有空格的class属性
    try elem.setAttribute("class", "  container main  ", allocator);
    const classes3 = try elem.getClasses(allocator);
    defer allocator.free(classes3);
    try std.testing.expect(classes3.len == 2);
    try std.testing.expect(std.mem.eql(u8, classes3[0], "container"));
    try std.testing.expect(std.mem.eql(u8, classes3[1], "main"));
}

test "node removeChild edge cases" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parent_elem = try dom.ElementData.init(allocator, "div");
    defer parent_elem.deinit(allocator);
    const parent = try allocator.create(dom.Node);
    defer allocator.destroy(parent);
    parent.* = .{
        .node_type = .element,
        .data = .{ .element = parent_elem },
    };

    var child_elem = try dom.ElementData.init(allocator, "p");
    defer child_elem.deinit(allocator);
    const child = try allocator.create(dom.Node);
    defer allocator.destroy(child);
    child.* = .{
        .node_type = .element,
        .data = .{ .element = child_elem },
    };

    // 测试移除不存在的子节点（应该不会崩溃）
    parent.removeChild(child);
    try std.testing.expect(parent.first_child == null);

    // 测试移除不是直接子节点的节点
    var grandchild_elem = try dom.ElementData.init(allocator, "span");
    defer grandchild_elem.deinit(allocator);
    const grandchild = try allocator.create(dom.Node);
    defer allocator.destroy(grandchild);
    grandchild.* = .{
        .node_type = .element,
        .data = .{ .element = grandchild_elem },
    };

    try parent.appendChild(child, allocator);
    try child.appendChild(grandchild, allocator);

    // 尝试从parent移除grandchild（不是直接子节点）
    parent.removeChild(grandchild);
    // grandchild应该仍然存在，因为removeChild会检查parent关系
    try std.testing.expect(grandchild.parent == child);
    try std.testing.expect(child.first_child == grandchild);
}

test "node querySelector edge cases" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试在空节点上查找
    var empty_elem = try dom.ElementData.init(allocator, "div");
    defer empty_elem.deinit(allocator);
    const empty_node = try allocator.create(dom.Node);
    defer allocator.destroy(empty_node);
    empty_node.* = .{
        .node_type = .element,
        .data = .{ .element = empty_elem },
    };

    const found1 = empty_node.querySelector("p");
    try std.testing.expect(found1 == null);

    // 测试查找不存在的元素
    var parent_elem = try dom.ElementData.init(allocator, "div");
    defer parent_elem.deinit(allocator);
    const parent = try allocator.create(dom.Node);
    defer allocator.destroy(parent);
    parent.* = .{
        .node_type = .element,
        .data = .{ .element = parent_elem },
    };

    var child_elem = try dom.ElementData.init(allocator, "p");
    defer child_elem.deinit(allocator);
    const child = try allocator.create(dom.Node);
    defer allocator.destroy(child);
    child.* = .{
        .node_type = .element,
        .data = .{ .element = child_elem },
    };

    try parent.appendChild(child, allocator);

    const found2 = parent.querySelector("span");
    try std.testing.expect(found2 == null);

    const found3 = parent.querySelector("p");
    try std.testing.expect(found3 != null);
    try std.testing.expect(found3 == child);
}

// 辅助函数：递归释放节点（在deinit之后释放节点本身的内存）
fn freeNodeAfterDeinit(allocator: std.mem.Allocator, node: *dom.Node) void {
    var current = node.first_child;
    while (current) |child| {
        const next = child.next_sibling;
        freeNodeAfterDeinit(allocator, child);
        allocator.destroy(child);
        current = next;
    }
}

test "document deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建文档
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    doc_ptr.* = doc;
    defer allocator.destroy(doc_ptr);

    // 创建html元素
    const html_elem_data = try dom.ElementData.init(allocator, "html");
    const html_node = try allocator.create(dom.Node);
    html_node.* = .{
        .node_type = .element,
        .data = .{ .element = html_elem_data },
    };
    try doc_ptr.node.appendChild(html_node, allocator);

    // 创建head元素
    const head_elem_data = try dom.ElementData.init(allocator, "head");
    const head_node = try allocator.create(dom.Node);
    head_node.* = .{
        .node_type = .element,
        .data = .{ .element = head_elem_data },
    };
    try html_node.appendChild(head_node, allocator);

    // 创建body元素
    var body_elem_data = try dom.ElementData.init(allocator, "body");
    try body_elem_data.setAttribute("id", "main-body", allocator);
    try body_elem_data.setAttribute("class", "container", allocator);
    const body_node = try allocator.create(dom.Node);
    body_node.* = .{
        .node_type = .element,
        .data = .{ .element = body_elem_data },
    };
    try html_node.appendChild(body_node, allocator);

    // 创建文本节点
    const text_content = try allocator.dupe(u8, "Hello World");
    const text_node = try allocator.create(dom.Node);
    text_node.* = .{
        .node_type = .text,
        .data = .{ .text = text_content },
    };
    try body_node.appendChild(text_node, allocator);

    // 创建注释节点
    const comment_content = try allocator.dupe(u8, "This is a comment");
    const comment_node = try allocator.create(dom.Node);
    comment_node.* = .{
        .node_type = .comment,
        .data = .{ .comment = comment_content },
    };
    try body_node.appendChild(comment_node, allocator);

    // 创建div元素（嵌套）
    var div_elem_data = try dom.ElementData.init(allocator, "div");
    try div_elem_data.setAttribute("class", "nested", allocator);
    const div_node = try allocator.create(dom.Node);
    div_node.* = .{
        .node_type = .element,
        .data = .{ .element = div_elem_data },
    };
    try body_node.appendChild(div_node, allocator);

    // 创建div内的文本节点
    const div_text_content = try allocator.dupe(u8, "Nested text");
    const div_text_node = try allocator.create(dom.Node);
    div_text_node.* = .{
        .node_type = .text,
        .data = .{ .text = div_text_content },
    };
    try div_node.appendChild(div_text_node, allocator);

    // 调用deinit，应该递归释放所有节点的数据（element数据、text内容、comment内容）
    doc_ptr.deinit();

    // 手动释放所有节点本身的内存
    if (doc_ptr.node.first_child) |html_elem| {
        freeNodeAfterDeinit(allocator, html_elem);
        allocator.destroy(html_elem);
    }

    // 如果使用GPA，deinit()会检查内存泄漏
    // 如果所有内存都被正确释放，gpa.deinit()不会报告泄漏
}

test "elementData deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建元素数据
    var elem_data = try dom.ElementData.init(allocator, "div");

    // 设置多个属性
    try elem_data.setAttribute("id", "test-id", allocator);
    try elem_data.setAttribute("class", "test-class", allocator);
    try elem_data.setAttribute("data-value", "test-value", allocator);
    try elem_data.setAttribute("title", "Test Title", allocator);

    // 验证属性存在
    try std.testing.expect(elem_data.hasAttribute("id"));
    try std.testing.expect(elem_data.hasAttribute("class"));
    try std.testing.expect(elem_data.hasAttribute("data-value"));
    try std.testing.expect(elem_data.hasAttribute("title"));

    // 调用deinit，应该释放tag_name和所有属性的key和value
    elem_data.deinit(allocator);

    // 如果使用GPA，deinit()会检查内存泄漏
    // 如果所有内存都被正确释放，gpa.deinit()不会报告泄漏
}

test "elementData deinit with multiple attribute updates" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建元素数据
    var elem_data = try dom.ElementData.init(allocator, "div");

    // 设置属性
    try elem_data.setAttribute("id", "old-id", allocator);
    // 更新属性（应该释放旧值）
    try elem_data.setAttribute("id", "new-id", allocator);
    try elem_data.setAttribute("class", "old-class", allocator);
    // 更新属性（应该释放旧值）
    try elem_data.setAttribute("class", "new-class", allocator);

    // 验证新值
    const id_attr = elem_data.getAttribute("id");
    try std.testing.expect(id_attr != null);
    try std.testing.expect(std.mem.eql(u8, id_attr.?, "new-id"));

    const class_attr = elem_data.getAttribute("class");
    try std.testing.expect(class_attr != null);
    try std.testing.expect(std.mem.eql(u8, class_attr.?, "new-class"));

    // 调用deinit，应该释放tag_name和所有属性的key和value
    elem_data.deinit(allocator);

    // 如果使用GPA，deinit()会检查内存泄漏
    // 如果所有内存都被正确释放，gpa.deinit()不会报告泄漏
}
