const std = @import("std");
const dom = @import("dom");
const html = @import("html");
const selector = @import("selector");

// 辅助函数：释放所有DOM节点
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
    std.debug.assert(node.first_child == null);
    std.debug.assert(node.last_child == null);

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

test "match type selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    // 解析HTML（需要完整的HTML文档结构）
    const html_input = "<html><head></head><body><div>Hello</div></body></html>";
    var parser = html.Parser.init(html_input, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 查找div元素（从body开始查找更可靠）
    const body = doc_ptr.getBody() orelse {
        std.debug.panic("body not found", .{});
    };
    const div = body.querySelector("div") orelse {
        std.debug.panic("div not found", .{});
    };

    // 创建类型选择器
    var type_selector = selector.SimpleSelector{
        .selector_type = .type,
        .value = try allocator.dupe(u8, "div"),
        .allocator = allocator,
    };
    defer type_selector.deinit();

    // 匹配
    var matcher = selector.Matcher.init(allocator);
    std.debug.assert(matcher.matchesSimpleSelector(div, &type_selector));
}

test "match class selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    // 解析HTML（需要完整的HTML文档结构）
    const html_input = "<html><head></head><body><div class=\"container\">Hello</div></body></html>";
    var parser = html.Parser.init(html_input, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 查找div元素（从body开始查找更可靠）
    const body = doc_ptr.getBody() orelse {
        std.debug.panic("body not found", .{});
    };
    const div = body.querySelector("div") orelse {
        std.debug.panic("div not found", .{});
    };

    // 创建类选择器
    var class_selector = selector.SimpleSelector{
        .selector_type = .class,
        .value = try allocator.dupe(u8, "container"),
        .allocator = allocator,
    };
    defer class_selector.deinit();

    // 匹配
    var matcher = selector.Matcher.init(allocator);
    std.debug.assert(matcher.matchesSimpleSelector(div, &class_selector));
}

test "match ID selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    // 解析HTML（需要完整的HTML文档结构）
    const html_input = "<html><head></head><body><div id=\"myId\">Hello</div></body></html>";
    var parser = html.Parser.init(html_input, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 查找div元素（从body开始查找更可靠）
    const body = doc_ptr.getBody() orelse {
        std.debug.panic("body not found", .{});
    };
    const div = body.querySelector("div") orelse {
        std.debug.panic("div not found", .{});
    };

    // 创建ID选择器
    var id_selector = selector.SimpleSelector{
        .selector_type = .id,
        .value = try allocator.dupe(u8, "myId"),
        .allocator = allocator,
    };
    defer id_selector.deinit();

    // 匹配
    var matcher = selector.Matcher.init(allocator);
    std.debug.assert(matcher.matchesSimpleSelector(div, &id_selector));
}

test "match attribute selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    defer {
        freeAllNodes(allocator, &doc_ptr.node);
        doc_ptr.node.first_child = null;
        doc_ptr.node.last_child = null;
        allocator.destroy(doc_ptr);
    }
    doc_ptr.* = doc;

    // 解析HTML（需要完整的HTML文档结构）
    const html_input = "<html><head></head><body><div data-test=\"value\">Hello</div></body></html>";
    var parser = html.Parser.init(html_input, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 查找div元素（从body开始查找更可靠）
    const body = doc_ptr.getBody() orelse {
        std.debug.panic("body not found", .{});
    };
    const div = body.querySelector("div") orelse {
        std.debug.panic("div not found", .{});
    };

    // 创建属性选择器
    var attr_selector = selector.SimpleSelector{
        .selector_type = .attribute,
        .value = try allocator.dupe(u8, ""),
        .attribute_name = try allocator.dupe(u8, "data-test"),
        .attribute_value = try allocator.dupe(u8, "value"),
        .allocator = allocator,
    };
    defer attr_selector.deinit();

    // 匹配
    var matcher = selector.Matcher.init(allocator);
    std.debug.assert(matcher.matchesSimpleSelector(div, &attr_selector));
}

test "calculate specificity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建选择器序列
    var sequence = selector.SelectorSequence.init(allocator);
    defer sequence.deinit();

    // 添加ID选择器
    try sequence.selectors.append(selector.SimpleSelector{
        .selector_type = .id,
        .value = try allocator.dupe(u8, "myId"),
        .allocator = allocator,
    });

    // 添加类选择器
    try sequence.selectors.append(selector.SimpleSelector{
        .selector_type = .class,
        .value = try allocator.dupe(u8, "container"),
        .allocator = allocator,
    });

    // 添加类型选择器
    try sequence.selectors.append(selector.SimpleSelector{
        .selector_type = .type,
        .value = try allocator.dupe(u8, "div"),
        .allocator = allocator,
    });

    // 计算specificity
    const spec = selector.calculateSequenceSpecificity(&sequence);
    std.debug.assert(spec.b == 1); // 1个ID
    std.debug.assert(spec.c == 1); // 1个类
    std.debug.assert(spec.d == 1); // 1个元素

    // 清理（sequence.deinit()会自动调用所有selector的deinit）
}
