const std = @import("std");
const html = @import("html/parser.zig");
const dom = @import("html/dom.zig");
const allocator_utils = @import("utils/allocator.zig");

/// Headless浏览器主入口
pub const Browser = struct {
    allocator: std.mem.Allocator,
    browser_allocator: allocator_utils.BrowserAllocator,
    document: *dom.Document,

    pub fn init(allocator: std.mem.Allocator) !Browser {
        var browser_allocator = allocator_utils.BrowserAllocator.init(allocator);
        const doc = try dom.Document.init(browser_allocator.arenaAllocator());
        const doc_ptr = try browser_allocator.arenaAllocator().create(dom.Document);
        doc_ptr.* = doc;

        return .{
            .allocator = allocator,
            .browser_allocator = browser_allocator,
            .document = doc_ptr,
        };
    }

    /// 加载和解析HTML
    pub fn loadHTML(self: *Browser, html_content: []const u8) !void {
        var parser = html.Parser.init(html_content, self.document, self.browser_allocator.arenaAllocator());
        defer parser.deinit();
        try parser.parse();
    }

    /// 渲染页面（占位实现）
    pub fn render(self: *Browser, width: u32, height: u32) !void {
        _ = self;
        _ = width;
        _ = height;
        // TODO: 实现渲染逻辑
    }

    /// 渲染并保存为PNG（占位实现）
    pub fn renderToPNG(self: *Browser, width: u32, height: u32, path: []const u8) !void {
        _ = self;
        _ = width;
        _ = height;
        _ = path;
        // TODO: 实现PNG输出
    }

    pub fn deinit(self: *Browser) void {
        self.document.deinit();
        self.browser_allocator.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var browser = try Browser.init(allocator);
    defer browser.deinit();

    const html_content =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <title>Test Page</title>
        \\</head>
        \\<body>
        \\  <h1>Hello, World!</h1>
        \\  <p>This is a test page.</p>
        \\</body>
        \\</html>
    ;

    try browser.loadHTML(html_content);

    std.debug.print("HTML parsed successfully!\n", .{});

    if (browser.document.getBody()) |_| {
        std.debug.print("Body element found\n", .{});
    }
}
