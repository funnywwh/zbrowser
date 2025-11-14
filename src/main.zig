const std = @import("std");
const builtin = @import("builtin");

/// 调试输出函数（只在Debug模式下输出）
/// 使用条件编译，在Release模式下完全移除，避免性能影响
inline fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        std.debug.print(fmt, args);
    }
}
const html = @import("html");
const dom = @import("dom");
const allocator_utils = @import("allocator");
const css_parser = @import("parser");
const layout_engine = @import("engine");
const box = @import("box");
const cpu_backend = @import("cpu_backend");
const renderer = @import("renderer");
const png = @import("png");
const cascade = @import("cascade");
const style_utils = @import("style_utils");
const backend = @import("backend");
const block = @import("block");

/// Headless浏览器主入口
pub const Browser = struct {
    allocator: std.mem.Allocator,
    browser_allocator: allocator_utils.BrowserAllocator,
    document: *dom.Document,
    stylesheets: std.ArrayList(css_parser.Stylesheet),
    /// 缓存的布局树（如果DOM和样式表未变化，可以复用）
    cached_layout_tree: ?*box.LayoutBox,
    /// 缓存的布局引擎实例（用于复用）
    cached_layout_engine: ?layout_engine.LayoutEngine,
    /// DOM版本号（用于检测DOM是否变化）
    dom_version: u64,

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
            .cached_layout_tree = null,
            .cached_layout_engine = null,
            .dom_version = 0,
        };
    }

    /// 加载和解析HTML
    pub fn loadHTML(self: *Browser, html_content: []const u8) !void {
        var parser = html.Parser.init(html_content, self.document, self.browser_allocator.arenaAllocator());
        defer parser.deinit();
        try parser.parse();

        // DOM已变化，清除缓存的布局树
        self.invalidateLayoutTreeCache();

        // 从HTML中提取内联样式（简化：暂时不处理）
        // TODO: 解析<style>标签和外部样式表
    }

    /// 添加CSS样式表
    pub fn addStylesheet(self: *Browser, css_content: []const u8) !void {
        var css_parser_instance = css_parser.Parser.init(css_content, self.allocator);
        defer css_parser_instance.deinit();

        const stylesheet = try css_parser_instance.parse();
        try self.stylesheets.append(self.allocator, stylesheet);

        // 样式表已变化，清除缓存的布局树
        self.invalidateLayoutTreeCache();
    }

    /// 清除缓存的布局树
    /// 当DOM或样式表变化时调用此方法
    pub fn invalidateLayoutTreeCache(self: *Browser) void {
        // 释放缓存的布局树
        if (self.cached_layout_tree) |tree| {
            // 清理formatting_context（必须在deinitAndDestroyChildren之前调用）
            cleanupFormattingContexts(tree);
            tree.deinitAndDestroyChildren();
            self.allocator.destroy(tree);
            self.cached_layout_tree = null;
        }
        // 布局引擎不需要释放（它只包含分配器引用）
        self.cached_layout_engine = null;
        // 更新DOM版本号
        self.dom_version += 1;
    }

    /// 清理布局树中的所有formatting_context
    /// 这是一个辅助函数，用于在释放布局树之前清理formatting_context
    fn cleanupFormattingContexts(layout_box: *box.LayoutBox) void {
        // 调用engine模块的清理函数
        layout_engine.LayoutEngine.cleanupFormattingContexts(layout_box);
    }

    /// 渲染页面
    /// 返回渲染后的像素数据（RGBA格式）
    pub fn render(self: *Browser, width: u32, height: u32) ![]u8 {
        // 1. 获取DOM根节点
        const html_node = self.document.getDocumentElement() orelse return error.NoDocumentElement;

        // 2. 构建或复用布局树
        // 布局树复用机制：
        // - 如果DOM和样式表未变化，可以复用缓存的布局树
        // - 布局计算每次都需要重新执行（因为视口大小可能变化）
        // - 布局引擎可以复用（它只包含分配器和Cascade实例，不包含状态）
        var layout_tree: *box.LayoutBox = undefined;
        var layout_engine_instance: layout_engine.LayoutEngine = undefined;
        var should_cache = false;

        if (self.cached_layout_tree) |cached_tree| {
            // 复用缓存的布局树
            layout_tree = cached_tree;
            // 复用缓存的布局引擎（如果存在）
            // 注意：布局引擎不包含状态，可以安全复用
            if (self.cached_layout_engine) |*cached_engine| {
                layout_engine_instance = cached_engine.*;
            } else {
                // 如果缓存中没有布局引擎，创建新的
                layout_engine_instance = layout_engine.LayoutEngine.init(self.allocator);
                self.cached_layout_engine = layout_engine_instance;
            }
            should_cache = false; // 已经缓存了，不需要再次缓存
        } else {
            // 构建新的布局树
            layout_engine_instance = layout_engine.LayoutEngine.init(self.allocator);
            layout_tree = try layout_engine_instance.buildLayoutTree(html_node, self.stylesheets.items);
            should_cache = true; // 标记需要缓存
        }

        // 注意：缓存的布局树不应该在这里defer释放，因为我们需要保留它以便下次复用
        // 只有在invalidateLayoutTreeCache时才会释放

        // 3. 执行布局计算
        // 注意：即使复用布局树，布局计算也需要重新执行（因为视口大小可能变化）
        // 注意：在复用布局树时，需要先清理旧的formatting_context，因为layout会创建新的
        if (self.cached_layout_tree) |_| {
            // 复用布局树时，先清理旧的formatting_context
            cleanupFormattingContexts(layout_tree);
        }
        const viewport = box.Size{ .width = @as(f32, @floatFromInt(width)), .height = @as(f32, @floatFromInt(height)) };
        try layout_engine_instance.layout(layout_tree, viewport, self.stylesheets.items);

        // 如果这是新构建的布局树，缓存它
        if (should_cache) {
            self.cached_layout_tree = layout_tree;
            self.cached_layout_engine = layout_engine_instance;
        }

        // 3.5. 输出元素的布局信息（用于与Chrome对比）
        // 先输出 html 元素
        try block.printElementLayoutInfo(layout_tree, self.allocator, self.stylesheets.items);

        // 查找body元素
        var body: ?*box.LayoutBox = null;
        for (layout_tree.children.items) |child| {
            if (child.node.node_type == .element) {
                if (child.node.asElement()) |elem| {
                    if (std.mem.eql(u8, elem.tag_name, "body")) {
                        body = child;
                        break;
                    }
                }
            }
        }
        
        // 调试：如果找不到 body，检查 html 的子节点
        if (body == null) {
            std.debug.print("DEBUG: body not found in html children, checking html children:\n", .{});
            for (layout_tree.children.items, 0..) |child, i| {
                const tag_name = if (child.node.node_type == .element)
                    if (child.node.asElement()) |elem| elem.tag_name else "unknown"
                else
                    "text";
                std.debug.print("  html child[{d}]: {s}\n", .{ i, tag_name });
            }
        }
        if (body) |b| {
            // 调试：打印 body 的所有子元素（在布局信息输出之前，用于诊断为什么找不到 h1）
            std.debug.print("\n=== DEBUG: Body children before printElementLayoutInfo ===\n", .{});
            std.debug.print("Body children count: {d}\n", .{b.children.items.len});
            
            // 同时检查 DOM 节点中的子元素
            std.debug.print("Body DOM node children:\n", .{});
            var dom_child = b.node.first_child;
            var dom_child_idx: usize = 0;
            while (dom_child) |dc| {
                const dom_tag_name = if (dc.node_type == .element)
                    if (dc.asElement()) |elem| elem.tag_name else "unknown"
                else if (dc.node_type == .text)
                    "text"
                else if (dc.node_type == .doctype)
                    "!DOCTYPE"
                else
                    "unknown";
                std.debug.print("  DOM Child[{d}]: {s} (node_type: {})\n", .{ dom_child_idx, dom_tag_name, dc.node_type });
                
                // 如果是元素节点且 tag_name 是 "!DOCTYPE"，这是错误的，应该跳过
                if (dc.node_type == .element) {
                    if (dc.asElement()) |elem| {
                        if (std.mem.eql(u8, elem.tag_name, "!DOCTYPE")) {
                            std.debug.print("    ERROR: Found element node with tag_name '!DOCTYPE' - this should not exist!\n", .{});
                        }
                    }
                }
                
                dom_child = dc.next_sibling;
                dom_child_idx += 1;
            }
            
            for (b.children.items, 0..) |child, i| {
                const tag_name = if (child.node.node_type == .element)
                    if (child.node.asElement()) |elem| elem.tag_name else "unknown"
                else
                    "text";
                std.debug.print("  Layout Child[{d}]: {s} (node_type: {})\n", .{ i, tag_name, child.node.node_type });
            }
            std.debug.print("=== END DEBUG ===\n\n", .{});

            // 输出 body 元素的布局信息（用于与Chrome对比）
            try block.printElementLayoutInfo(b, self.allocator, self.stylesheets.items);

            // 输出第一个 h1 元素的布局信息（用于与Chrome对比）
            // 注意：h1 元素可能不存在，这是正常的（某些页面可能没有 h1）
            if (block.findElement(b, "h1", null, null)) |h1_element| {
                std.debug.print("DEBUG: Found h1 element!\n", .{});
                try block.printElementLayoutInfo(h1_element, self.allocator, self.stylesheets.items);
            } else {
                std.debug.print("DEBUG: h1 element not found in body (children count: {d})\n", .{b.children.items.len});
                // 再次打印子元素，确认 h1 是否在子元素中
                for (b.children.items, 0..) |child, i| {
                    const tag_name = if (child.node.node_type == .element)
                        if (child.node.asElement()) |elem| elem.tag_name else "unknown"
                    else
                        "text";
                    if (std.mem.eql(u8, tag_name, "h1")) {
                        std.debug.print("  Found h1 at index {d}!\n", .{i});
                    }
                }
            }
        } else {
            debugPrint("Warning: body element not found\n", .{});
        }

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
        // 清理缓存的布局树
        self.invalidateLayoutTreeCache();

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

    // 解析命令行参数
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // 检查参数数量
    if (args.len < 2) {
        // 使用std.debug.print输出到stderr（在Zig 0.15.2中，std.debug.print默认输出到stderr）
        std.debug.print("用法: {s} <html文件路径> [输出PNG路径]\n示例: {s} test_page.html output.png\n", .{ args[0], args[0] });
        std.process.exit(1);
    }

    const html_file_path = args[1];
    const output_path = if (args.len >= 3) args[2] else "output.png";

    // 读取HTML文件
    const html_file = try std.fs.cwd().openFile(html_file_path, .{});
    defer html_file.close();

    const html_content = try html_file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 最大10MB
    defer allocator.free(html_content);

    var browser = try Browser.init(allocator);
    defer browser.deinit();

    // 加载HTML
    try browser.loadHTML(html_content);

    // 从HTML中提取CSS（从<style>标签）
    const css_content = try extractCSSFromHTML(allocator, html_content);
    defer if (css_content) |css| allocator.free(css);

    // 添加CSS样式表
    if (css_content) |css| {
        try browser.addStylesheet(css);
    } else {}

    // 检查body元素是否存在
    if (browser.document.getBody()) |_| {} else {}

    // 使用固定尺寸（匹配Chrome的视口宽度980px）
    // Chrome的body width是940px，padding是20px，所以视口宽度 = 940 + 20*2 = 980px
    const render_width: u32 = 980;
    const render_height: u32 = 8000;

    try browser.renderToPNG(render_width, render_height, output_path);
}

/// 从HTML内容中提取CSS（从<style>标签）
/// 返回提取的CSS内容，如果没有找到则返回null
fn extractCSSFromHTML(allocator: std.mem.Allocator, html_content: []const u8) !?[]u8 {
    const style_start_tag = "<style";
    const style_end_tag = "</style>";

    var start_pos: ?usize = null;
    var end_pos: ?usize = null;

    // 查找第一个<style>标签的开始位置
    if (std.mem.indexOf(u8, html_content, style_start_tag)) |pos| {
        // 找到开始标签，查找对应的结束标签
        const after_start = html_content[pos + style_start_tag.len ..];

        // 查找>符号（可能是<style>或<style ...>）
        const tag_end = std.mem.indexOf(u8, after_start, ">") orelse return null;
        const style_content_start = pos + style_start_tag.len + tag_end + 1;

        // 查找</style>标签
        if (std.mem.indexOf(u8, html_content[style_content_start..], style_end_tag)) |end_offset| {
            start_pos = style_content_start;
            end_pos = style_content_start + end_offset;
        }
    }

    if (start_pos) |start| {
        if (end_pos) |end| {
            const css_content = html_content[start..end];
            // 去除前后空白字符
            const trimmed = std.mem.trim(u8, css_content, " \t\n\r");
            if (trimmed.len > 0) {
                return try allocator.dupe(u8, trimmed);
            }
        }
    }

    return null;
}
