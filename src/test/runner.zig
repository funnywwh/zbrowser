const std = @import("std");
const html = @import("html");
const dom = @import("dom");
const tokenizer = @import("tokenizer");

/// 测试运行器
pub fn runTests(allocator: std.mem.Allocator) !void {
    std.debug.print("Running tests...\n", .{});

    try testHTMLTokenizer(allocator);
    try testHTMLParser(allocator);
    try testDOM(allocator);

    std.debug.print("All tests passed!\n", .{});
}

fn testHTMLTokenizer(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing HTML Tokenizer...\n", .{});

    const html_input = "<div class='test'>Hello</div>";
    var tok = tokenizer.Tokenizer.init(html_input, allocator);

    // 测试开始标签
    var token1 = (try tok.next()).?;
    defer token1.deinit();
    std.debug.assert(token1.token_type == .start_tag);
    std.debug.assert(std.mem.eql(u8, token1.data.start_tag.name, "div"));
    const class_attr = token1.data.start_tag.attributes.get("class");
    std.debug.assert(class_attr != null);

    // 测试文本
    var token2 = (try tok.next()).?;
    defer token2.deinit();
    std.debug.assert(token2.token_type == .text);
    std.debug.assert(std.mem.eql(u8, token2.data.text, "Hello"));

    // 测试结束标签
    var token3 = (try tok.next()).?;
    defer token3.deinit();
    std.debug.assert(token3.token_type == .end_tag);
    std.debug.assert(std.mem.eql(u8, token3.data.end_tag.name, "div"));

    std.debug.print("  HTML Tokenizer tests passed\n", .{});
}

fn testHTMLParser(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing HTML Parser...\n", .{});

    const html_input = "<html><head><title>Test</title></head><body><p>Hello</p></body></html>";
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        // 手动释放所有节点（因为使用GPA而非Arena）
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    var parser = html.Parser.init(html_input, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 验证文档结构
    const html_elem = doc_ptr.getDocumentElement();
    std.debug.assert(html_elem != null);

    const head = doc_ptr.getHead();
    std.debug.assert(head != null);

    const body = doc_ptr.getBody();
    std.debug.assert(body != null);

    std.debug.print("  HTML Parser tests passed\n", .{});
}

fn testDOM(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing DOM...\n", .{});

    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        // 手动释放所有节点（因为使用GPA而非Arena）
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    const html_node = try createElement(allocator, "html");
    try doc_ptr.node.appendChild(html_node, allocator);

    const body_node = try createElement(allocator, "body");
    try html_node.appendChild(body_node, allocator);

    const p_node = try createElement(allocator, "p");
    try body_node.appendChild(p_node, allocator);

    const text_node = try createTextNode(allocator, "Hello");
    try p_node.appendChild(text_node, allocator);

    // 验证结构
    std.debug.assert(html_node.first_child == body_node);
    std.debug.assert(body_node.first_child == p_node);
    std.debug.assert(p_node.first_child == text_node);

    std.debug.print("  DOM tests passed\n", .{});
}

fn freeAllNodes(allocator: std.mem.Allocator, node: *dom.Node) void {
    // 先释放所有子节点
    var current = node.first_child;
    while (current) |child| {
        const next = child.next_sibling;
        freeAllNodes(allocator, child);
        freeNode(allocator, child);
        current = next;
    }
    // 清空子节点指针
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
            // comment节点数据在node.data.comment中
            if (node.node_type == .comment) {
                allocator.free(node.data.comment);
            }
        },
        else => {},
    }
    allocator.destroy(node);
}

fn createElement(allocator: std.mem.Allocator, tag_name: []const u8) !*dom.Node {
    // ElementData.init 会复制 tag_name，所以直接传入 tag_name
    const node = try allocator.create(dom.Node);
    node.* = .{
        .node_type = .element,
        .data = .{
            .element = try dom.ElementData.init(allocator, tag_name),
        },
    };
    return node;
}

fn createTextNode(allocator: std.mem.Allocator, text: []const u8) !*dom.Node {
    const text_owned = try allocator.dupe(u8, text);
    const node = try allocator.create(dom.Node);
    node.* = .{
        .node_type = .text,
        .data = .{ .text = text_owned },
    };
    return node;
}

test "run all tests" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try runTests(allocator);
}
