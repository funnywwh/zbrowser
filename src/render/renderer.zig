const std = @import("std");
const box = @import("box");
const dom = @import("dom");
const cascade = @import("cascade");
const css_parser = @import("parser");
const backend = @import("backend");
const style_utils = @import("style_utils");

/// 渲染器
/// 负责将布局树转换为像素数据
pub const Renderer = struct {
    allocator: std.mem.Allocator,
    render_backend: *backend.RenderBackend,
    stylesheets: []const css_parser.Stylesheet = &[_]css_parser.Stylesheet{},

    /// 初始化渲染器
    pub fn init(allocator: std.mem.Allocator, render_backend: *backend.RenderBackend) Renderer {
        return .{
            .allocator = allocator,
            .render_backend = render_backend,
        };
    }

    /// 渲染布局树到像素
    /// 遍历布局树，根据每个LayoutBox的样式和内容，调用渲染后端绘制
    pub fn renderLayoutTree(self: *Renderer, layout_tree: *box.LayoutBox, stylesheets: []const css_parser.Stylesheet) !void {
        self.stylesheets = stylesheets;

        // 递归渲染布局树
        try self.renderLayoutBox(layout_tree);
    }

    /// 渲染单个布局框
    fn renderLayoutBox(self: *Renderer, layout_box: *box.LayoutBox) !void {
        // 如果display为none，不渲染
        if (layout_box.display == .none) {
            return;
        }

        // 计算样式（用于获取颜色、背景等）
        var cascade_engine = cascade.Cascade.init(self.allocator);
        var computed_style = try cascade_engine.computeStyle(layout_box.node, self.stylesheets);
        defer computed_style.deinit();

        // 获取布局框的位置和尺寸
        const content_rect = layout_box.box_model.content;
        const total_size = layout_box.box_model.totalSize();

        // 计算边框框的位置（包含margin）
        const border_x = content_rect.x - layout_box.box_model.padding.left - layout_box.box_model.border.left;
        const border_y = content_rect.y - layout_box.box_model.padding.top - layout_box.box_model.border.top;
        const border_rect = backend.Rect.init(
            border_x,
            border_y,
            total_size.width,
            total_size.height,
        );

        // 1. 绘制背景
        try self.renderBackground(layout_box, &computed_style, border_rect);

        // 2. 绘制边框
        try self.renderBorder(layout_box, &computed_style, border_rect);

        // 3. 绘制内容（文本）
        try self.renderContent(layout_box, &computed_style, content_rect);

        // 4. 递归渲染子节点
        for (layout_box.children.items) |child| {
            try self.renderLayoutBox(child);
        }
    }

    /// 渲染背景
    fn renderBackground(self: *Renderer, layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, rect: backend.Rect) !void {
        _ = layout_box;
        // 获取背景颜色
        const bg_color = self.getBackgroundColor(computed_style);

        if (bg_color) |color| {
            // 绘制背景矩形
            self.render_backend.fillRect(rect, color);
        }
    }

    /// 渲染边框
    fn renderBorder(self: *Renderer, layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, rect: backend.Rect) !void {
        _ = layout_box;
        // 获取边框颜色和宽度
        const border_color = self.getBorderColor(computed_style);
        const border_width = self.getBorderWidth(computed_style);

        if (border_color) |color| {
            if (border_width > 0) {
                // 绘制边框
                self.render_backend.strokeRect(rect, color, border_width);
            }
        }
    }

    /// 渲染内容（文本）
    fn renderContent(self: *Renderer, layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, rect: backend.Rect) !void {
        // 如果节点是文本节点，渲染文本
        if (layout_box.node.node_type == .text) {
            // 从Node.data中获取文本内容
            const text_content = layout_box.node.data.text;

            // 获取文本颜色和字体
            const text_color = self.getTextColor(computed_style);
            const font = self.getFont(computed_style);

            if (text_color) |color| {
                // 绘制文本（简化：使用fillText）
                self.render_backend.fillText(text_content, rect.x, rect.y + font.size, font, color);
            }
        }
    }

    /// 获取背景颜色
    fn getBackgroundColor(self: *Renderer, computed_style: *const cascade.ComputedStyle) ?backend.Color {
        _ = self;
        _ = computed_style;
        // TODO: 简化实现 - 当前返回默认颜色
        // 完整实现需要：从computed_style中解析background-color属性
        return backend.Color.rgb(255, 255, 255); // 白色
    }

    /// 获取边框颜色
    fn getBorderColor(self: *Renderer, computed_style: *const cascade.ComputedStyle) ?backend.Color {
        _ = self;
        _ = computed_style;
        // TODO: 简化实现 - 当前返回默认颜色
        // 完整实现需要：从computed_style中解析border-color属性
        return null; // 无边框
    }

    /// 获取边框宽度
    fn getBorderWidth(self: *Renderer, computed_style: *const cascade.ComputedStyle) f32 {
        _ = self;
        _ = computed_style;
        // TODO: 简化实现 - 当前返回默认宽度
        // 完整实现需要：从computed_style中解析border-width属性
        return 0;
    }

    /// 获取文本颜色
    fn getTextColor(self: *Renderer, computed_style: *const cascade.ComputedStyle) ?backend.Color {
        _ = self;
        _ = computed_style;
        // TODO: 简化实现 - 当前返回默认颜色
        // 完整实现需要：从computed_style中解析color属性
        return backend.Color.rgb(0, 0, 0); // 黑色
    }

    /// 获取字体
    fn getFont(self: *Renderer, computed_style: *const cascade.ComputedStyle) backend.Font {
        _ = self;
        _ = computed_style;
        // TODO: 简化实现 - 当前返回默认字体
        // 完整实现需要：从computed_style中解析font-family、font-size等属性
        return backend.Font{
            .family = "Arial",
            .size = 16,
            .weight = .normal,
            .style = .normal,
        };
    }
};
