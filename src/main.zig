const std = @import("std");
const html = @import("html");
const dom = @import("dom");
const allocator_utils = @import("utils/allocator.zig");
const css_parser = @import("parser");
const layout_engine = @import("engine");
const box = @import("box");
const cpu_backend = @import("cpu_backend");
const renderer = @import("renderer");
const png = @import("png");

/// Headless浏览器主入口
pub const Browser = struct {
    allocator: std.mem.Allocator,
    browser_allocator: allocator_utils.BrowserAllocator,
    document: *dom.Document,
    stylesheets: std.ArrayList(css_parser.Stylesheet),

    pub fn init(allocator: std.mem.Allocator) !Browser {
        var browser_allocator = allocator_utils.BrowserAllocator.init(allocator);
        const doc = try dom.Document.init(browser_allocator.arenaAllocator());
        const doc_ptr = try browser_allocator.arenaAllocator().create(dom.Document);
        doc_ptr.* = doc;

        return .{
            .allocator = allocator,
            .browser_allocator = browser_allocator,
            .document = doc_ptr,
            .stylesheets = std.ArrayList(css_parser.Stylesheet){},
        };
    }

    /// 加载和解析HTML
    pub fn loadHTML(self: *Browser, html_content: []const u8) !void {
        var parser = html.Parser.init(html_content, self.document, self.browser_allocator.arenaAllocator());
        defer parser.deinit();
        try parser.parse();

        // 从HTML中提取内联样式（简化：暂时不处理）
        // TODO: 解析<style>标签和外部样式表
    }

    /// 添加CSS样式表
    pub fn addStylesheet(self: *Browser, css_content: []const u8) !void {
        var css_parser_instance = css_parser.Parser.init(css_content, self.allocator);
        defer css_parser_instance.deinit();

        const stylesheet = try css_parser_instance.parse();
        try self.stylesheets.append(self.allocator, stylesheet);
    }

    /// 渲染页面
    /// 返回渲染后的像素数据（RGBA格式）
    pub fn render(self: *Browser, width: u32, height: u32) ![]u8 {
        // 1. 获取DOM根节点
        const html_node = self.document.getDocumentElement() orelse return error.NoDocumentElement;

        // 2. 构建布局树
        var layout_engine_instance = layout_engine.LayoutEngine.init(self.allocator);
        const layout_tree = try layout_engine_instance.buildLayoutTree(html_node, self.stylesheets.items);
        defer layout_tree.deinitAndDestroyChildren();
        defer self.allocator.destroy(layout_tree);

        // 3. 执行布局计算
        const viewport = box.Size{ .width = @as(f32, @floatFromInt(width)), .height = @as(f32, @floatFromInt(height)) };
        try layout_engine_instance.layout(layout_tree, viewport, self.stylesheets.items);

        // 4. 创建CPU渲染后端
        const render_backend = try cpu_backend.CpuRenderBackend.init(self.allocator, width, height);
        defer render_backend.deinit();

        // 5. 创建渲染器并渲染布局树
        var renderer_instance = renderer.Renderer.init(self.allocator, &render_backend.base);
        try renderer_instance.renderLayoutTree(layout_tree, self.stylesheets.items);

        // 6. 获取渲染后的像素数据
        return try render_backend.getPixels(self.allocator);
    }

    /// 渲染并保存为PNG
    pub fn renderToPNG(self: *Browser, width: u32, height: u32, path: []const u8) !void {
        // 1. 渲染页面获取像素数据
        const pixels = try self.render(width, height);
        defer self.allocator.free(pixels);

        // 2. 使用PNG编码器编码像素数据
        var png_encoder = png.PngEncoder.init(self.allocator);
        const png_data = try png_encoder.encode(pixels, width, height);
        defer self.allocator.free(png_data);

        // 3. 写入文件
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(png_data);
    }

    pub fn deinit(self: *Browser) void {
        // 清理样式表
        for (self.stylesheets.items) |*stylesheet| {
            stylesheet.deinit();
        }
        self.stylesheets.deinit(self.allocator);

        // 注意：如果使用 arena allocator，Document.deinit 应该什么都不做
        // 因为 arena 会在 BrowserAllocator.deinit 时自动释放所有内存
        // 所以，我们先调用 browser_allocator.deinit() 来释放 arena
        // 然后就不需要调用 document.deinit() 了
        self.browser_allocator.deinit();
        // self.document.deinit(); // 不需要调用，因为 arena 已经释放了所有内存
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
