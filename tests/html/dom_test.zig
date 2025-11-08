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
