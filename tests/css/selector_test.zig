const std = @import("std");
const dom = @import("dom");
const html = @import("html");
const selector = @import("selector");

test "match type selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM
    var doc = try dom.Document.init(allocator);
    defer doc.deinit();
    const doc_ptr = try allocator.create(dom.Document);
    defer allocator.destroy(doc_ptr);
    doc_ptr.* = doc;

    // 解析HTML
    const html_input = "<div>Hello</div>";
    var parser = html.Parser.init(html_input, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 查找div元素
    const div = doc_ptr.querySelector("div");
    std.debug.assert(div != null);

    // 创建类型选择器
    var type_selector = selector.SimpleSelector{
        .selector_type = .type,
        .value = try allocator.dupe(u8, "div"),
        .allocator = allocator,
    };
    defer type_selector.deinit();

    // 匹配
    var matcher = selector.Matcher.init(allocator);
    std.debug.assert(matcher.matchesSimpleSelector(div.?, &type_selector));
}

test "match class selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM
    var doc = try dom.Document.init(allocator);
    defer doc.deinit();
    const doc_ptr = try allocator.create(dom.Document);
    defer allocator.destroy(doc_ptr);
    doc_ptr.* = doc;

    // 解析HTML
    const html_input = "<div class=\"container\">Hello</div>";
    var parser = html.Parser.init(html_input, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 查找div元素
    const div = doc_ptr.querySelector("div");
    std.debug.assert(div != null);

    // 创建类选择器
    var class_selector = selector.SimpleSelector{
        .selector_type = .class,
        .value = try allocator.dupe(u8, "container"),
        .allocator = allocator,
    };
    defer class_selector.deinit();

    // 匹配
    var matcher = selector.Matcher.init(allocator);
    std.debug.assert(matcher.matchesSimpleSelector(div.?, &class_selector));
}

test "match ID selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM
    var doc = try dom.Document.init(allocator);
    defer doc.deinit();
    const doc_ptr = try allocator.create(dom.Document);
    defer allocator.destroy(doc_ptr);
    doc_ptr.* = doc;

    // 解析HTML
    const html_input = "<div id=\"myId\">Hello</div>";
    var parser = html.Parser.init(html_input, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 查找div元素
    const div = doc_ptr.querySelector("div");
    std.debug.assert(div != null);

    // 创建ID选择器
    var id_selector = selector.SimpleSelector{
        .selector_type = .id,
        .value = try allocator.dupe(u8, "myId"),
        .allocator = allocator,
    };
    defer id_selector.deinit();

    // 匹配
    var matcher = selector.Matcher.init(allocator);
    std.debug.assert(matcher.matchesSimpleSelector(div.?, &id_selector));
}

test "match attribute selector" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM
    var doc = try dom.Document.init(allocator);
    defer doc.deinit();
    const doc_ptr = try allocator.create(dom.Document);
    defer allocator.destroy(doc_ptr);
    doc_ptr.* = doc;

    // 解析HTML
    const html_input = "<div data-test=\"value\">Hello</div>";
    var parser = html.Parser.init(html_input, doc_ptr, allocator);
    defer parser.deinit();
    try parser.parse();

    // 查找div元素
    const div = doc_ptr.querySelector("div");
    std.debug.assert(div != null);

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
    std.debug.assert(matcher.matchesSimpleSelector(div.?, &attr_selector));
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

    // 清理
    for (sequence.selectors.items) |*sel| {
        sel.deinit();
    }
}
