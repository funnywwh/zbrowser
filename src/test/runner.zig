const std = @import("std");
const html = @import("../html/parser.zig");
const dom = @import("../html/dom.zig");
const tokenizer = @import("../html/tokenizer.zig");

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
    const token1 = (try tok.next()).?;
    std.debug.assert(token1.token_type == .start_tag);
    std.debug.assert(std.mem.eql(u8, token1.data.start_tag.name, "div"));
    std.debug.assert(token1.data.start_tag.attributes.get("class").? != null);

    // 测试文本
    const token2 = (try tok.next()).?;
    std.debug.assert(token2.token_type == .text);
    std.debug.assert(std.mem.eql(u8, token2.data.text, "Hello"));

    // 测试结束标签
    const token3 = (try tok.next()).?;
    std.debug.assert(token3.token_type == .end_tag);
    std.debug.assert(std.mem.eql(u8, token3.data.end_tag.name, "div"));

    std.debug.print("  HTML Tokenizer tests passed\n", .{});
}

fn testHTMLParser(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing HTML Parser...\n", .{});

    const html_input = "<html><head><title>Test</title></head><body><p>Hello</p></body></html>";
    const doc = try dom.Document.init(allocator);
    defer doc.deinit();

    var parser = html.Parser.init(html_input, doc, allocator);
    defer parser.deinit();
    try parser.parse();

    // 验证文档结构
    const html_elem = doc.getDocumentElement();
    std.debug.assert(html_elem != null);

    const head = doc.getHead();
    std.debug.assert(head != null);

    const body = doc.getBody();
    std.debug.assert(body != null);

    std.debug.print("  HTML Parser tests passed\n", .{});
}

fn testDOM(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing DOM...\n", .{});

    const doc = try dom.Document.init(allocator);
    defer doc.deinit();

    const html_node = try createElement(allocator, "html");
    try doc.node.appendChild(html_node, allocator);

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

fn createElement(allocator: std.mem.Allocator, tag_name: []const u8) !*dom.Node {
    const tag_owned = try allocator.dupe(u8, tag_name);
    const node = try allocator.create(dom.Node);
    node.* = .{
        .node_type = .element,
        .data = .{
            .element = dom.ElementData.init(allocator, tag_owned),
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
