const std = @import("std");
const html = @import("../../src/html/parser.zig");
const dom = @import("../../src/html/dom.zig");

test "parse simple HTML" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "<html><body><p>Hello</p></body></html>";
    const doc = try dom.Document.init(allocator);
    defer doc.deinit();

    var parser = html.Parser.init(html_content, doc, allocator);
    defer parser.deinit();
    try parser.parse();

    const html_elem = doc.getDocumentElement();
    try std.testing.expect(html_elem != null);

    const body = doc.getBody();
    try std.testing.expect(body != null);
}

test "parse HTML with attributes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "<div class='container' id='main'></div>";
    const doc = try dom.Document.init(allocator);
    defer doc.deinit();

    var parser = html.Parser.init(html_content, doc, allocator);
    defer parser.deinit();
    try parser.parse();

    const body = doc.getBody();
    try std.testing.expect(body != null);

    if (body.?.first_child) |div| {
        if (div.asElement()) |elem| {
            try std.testing.expect(std.mem.eql(u8, elem.tag_name, "div"));
            try std.testing.expect(elem.getAttribute("class").? != null);
            try std.testing.expect(elem.getAttribute("id").? != null);
        }
    }
}

test "parse HTML with text content" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "<p>Hello, World!</p>";
    const doc = try dom.Document.init(allocator);
    defer doc.deinit();

    var parser = html.Parser.init(html_content, doc, allocator);
    defer parser.deinit();
    try parser.parse();

    const body = doc.getBody();
    try std.testing.expect(body != null);

    if (body.?.first_child) |p| {
        if (p.first_child) |text| {
            try std.testing.expect(text.node_type == .text);
            try std.testing.expect(std.mem.eql(u8, text.asText().?, "Hello, World!"));
        }
    }
}

test "parse HTML with comments" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "<!-- This is a comment --><p>Text</p>";
    const doc = try dom.Document.init(allocator);
    defer doc.deinit();

    var parser = html.Parser.init(html_content, doc, allocator);
    defer parser.deinit();
    try parser.parse();

    const body = doc.getBody();
    try std.testing.expect(body != null);
}

test "parse self-closing tags" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = "<br/><img src='test.jpg'/>";
    const doc = try dom.Document.init(allocator);
    defer doc.deinit();

    var parser = html.Parser.init(html_content, doc, allocator);
    defer parser.deinit();
    try parser.parse();

    const body = doc.getBody();
    try std.testing.expect(body != null);
}
