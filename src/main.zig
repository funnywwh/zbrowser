const std = @import("std");
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

    // 解析命令行参数
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // 检查参数数量
    if (args.len < 2) {
        const stderr = std.fs.File.stderr();
        const usage_msg = try std.fmt.allocPrint(allocator, "用法: {s} <html文件路径> [输出PNG路径]\n示例: {s} test_page.html output.png\n", .{ args[0], args[0] });
        defer allocator.free(usage_msg);
        try stderr.writeAll(usage_msg);
        std.process.exit(1);
    }

    const html_file_path = args[1];
    const output_path = if (args.len >= 3) args[2] else "output.png";

    std.log.info("读取HTML文件: {s}", .{html_file_path});
    std.log.info("输出PNG文件: {s}", .{output_path});

    // 读取HTML文件
    const html_file = try std.fs.cwd().openFile(html_file_path, .{});
    defer html_file.close();

    const html_content = try html_file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 最大10MB
    defer allocator.free(html_content);

    std.log.info("HTML文件读取成功，大小: {d} 字节", .{html_content.len});

    var browser = try Browser.init(allocator);
    defer browser.deinit();

    // 加载HTML
    try browser.loadHTML(html_content);
    std.log.info("HTML解析成功!", .{});

    // 从HTML中提取CSS（从<style>标签）
    const css_content = try extractCSSFromHTML(allocator, html_content);
    defer if (css_content) |css| allocator.free(css);

    // 添加CSS样式表
    if (css_content) |css| {
        try browser.addStylesheet(css);
        std.log.info("CSS样式表添加成功!", .{});
    } else {
        std.log.warn("未找到<style>标签，使用默认样式", .{});
    }

    // 检查body元素是否存在
    if (browser.document.getBody()) |_| {
        std.log.debug("Body element found", .{});
    } else {
        std.log.warn("Body element not found", .{});
    }

    // 先进行一次布局计算，获取所有文本的实际位置和宽度
    // 使用一个较大的初始尺寸进行布局
    const initial_width: u32 = 5000;
    const initial_height: u32 = 2500;
    const initial_viewport = box.Size{ .width = @as(f32, @floatFromInt(initial_width)), .height = @as(f32, @floatFromInt(initial_height)) };
    
    // 获取DOM根节点
    const html_node = browser.document.getDocumentElement() orelse return error.NoDocumentElement;
    
    // 构建布局树
    var layout_engine_instance = layout_engine.LayoutEngine.init(allocator);
    const layout_tree = try layout_engine_instance.buildLayoutTree(html_node, browser.stylesheets.items);
    defer layout_tree.deinitAndDestroyChildren();
    defer allocator.destroy(layout_tree);
    
    // 执行布局计算
    try layout_engine_instance.layout(layout_tree, initial_viewport, browser.stylesheets.items);
    
    // 创建临时的CPU渲染后端用于计算文本宽度
    const temp_backend = try cpu_backend.CpuRenderBackend.init(allocator, initial_width, initial_height);
    defer temp_backend.deinit();
    
    // 遍历布局树，计算所有文本的实际结束位置
    var max_x: f32 = 0;
    var max_y: f32 = 0;
    try calculateMaxBounds(layout_tree, temp_backend, browser.stylesheets.items, &max_x, &max_y);
    
    // 根据实际边界计算页面尺寸（加上一些边距）
    const margin: f32 = 50;
    const calculated_width = @as(u32, @intFromFloat(max_x + margin));
    const calculated_height = @as(u32, @intFromFloat(max_y + margin));
    
    std.log.info("计算页面尺寸: {d}x{d} (max_x={d:.1}, max_y={d:.1})", .{ calculated_width, calculated_height, max_x, max_y });
    
    // 使用计算出的尺寸进行实际渲染
    std.log.info("渲染页面到PNG ({d}x{d})...", .{ calculated_width, calculated_height });
    try browser.renderToPNG(calculated_width, calculated_height, output_path);
    std.log.info("页面渲染成功，已保存到: {s}", .{output_path});
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
        const after_start = html_content[pos + style_start_tag.len..];
        
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

/// 计算布局树中所有文本节点的最大边界
fn calculateMaxBounds(
    layout_box: *box.LayoutBox,
    temp_backend: *cpu_backend.CpuRenderBackend,
    stylesheets: []const css_parser.Stylesheet,
    max_x: *f32,
    max_y: *f32,
) !void {
    // 如果是文本节点，计算文本宽度
    if (layout_box.node.node_type == .text) {
        const text_content = layout_box.node.data.text;
        
        // 跳过空白文本
        if (text_content.len == 0) return;
        var is_whitespace_only = true;
        for (text_content) |c| {
            if (c != ' ' and c != '\n' and c != '\r' and c != '\t') {
                is_whitespace_only = false;
                break;
            }
        }
        if (is_whitespace_only) return;
        
        // 计算文本的样式和字体
        var cascade_engine = cascade.Cascade.init(temp_backend.allocator);
        var computed_style = try cascade_engine.computeStyle(layout_box.node, stylesheets);
        defer computed_style.deinit();
        
        // 如果文本节点没有font-size，尝试从父元素获取
        var text_computed_style: *cascade.ComputedStyle = &computed_style;
        var parent_computed_style: cascade.ComputedStyle = undefined;
        var use_parent_style = false;
        if (layout_box.parent) |parent| {
            var parent_cascade_engine = cascade.Cascade.init(temp_backend.allocator);
            parent_computed_style = try parent_cascade_engine.computeStyle(parent.node, stylesheets);
            if (computed_style.getProperty("font-size") == null) {
                use_parent_style = true;
                text_computed_style = &parent_computed_style;
            } else {
                parent_computed_style.deinit();
            }
        }
        defer if (use_parent_style) parent_computed_style.deinit();
        
        // 获取字体
        var font = backend.Font{
            .family = "Arial",
            .size = 16,
            .weight = .normal,
            .style = .normal,
        };
        const containing_width: f32 = 800;
        if (style_utils.getPropertyLength(text_computed_style, "font-size", containing_width)) |size| {
            font.size = size;
        }
        
        // 计算文本的实际宽度
        const text_end_x = temp_backend.calculateTextWidth(text_content, layout_box.box_model.content.x, font) catch |err| {
            std.log.debug("[calculateMaxBounds] Failed to calculate text width: {}", .{err});
            // 如果计算失败，使用估算值
            const char_width = font.size * 0.7;
            const text_width = char_width * @as(f32, @floatFromInt(text_content.len));
            const text_end_x = layout_box.box_model.content.x + text_width;
            max_x.* = @max(max_x.*, text_end_x);
            return;
        };
        
        // 更新最大x坐标
        max_x.* = @max(max_x.*, text_end_x);
        
        // 计算文本高度（考虑字体大小和行高）
        const text_height = font.size * 1.5; // 行高约为字体大小的1.5倍
        const text_bottom = layout_box.box_model.content.y + text_height;
        max_y.* = @max(max_y.*, text_bottom);
    }
    
    // 递归处理子节点（只处理子节点，不计算容器本身的宽度）
    for (layout_box.children.items) |child| {
        try calculateMaxBounds(child, temp_backend, stylesheets, max_x, max_y);
    }
}
