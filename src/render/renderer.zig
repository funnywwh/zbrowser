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
            std.log.debug("[Renderer] renderLayoutBox: display=none, skipping", .{});
            return;
        }
        
        // 跳过title、head、meta、script、style等元数据标签（它们不应该在页面中渲染）
        if (layout_box.node.node_type == .element) {
            if (layout_box.node.asElement()) |elem| {
                const tag_name = elem.tag_name;
                if (std.mem.eql(u8, tag_name, "title") or
                    std.mem.eql(u8, tag_name, "head") or
                    std.mem.eql(u8, tag_name, "meta") or
                    std.mem.eql(u8, tag_name, "script") or
                    std.mem.eql(u8, tag_name, "style") or
                    std.mem.eql(u8, tag_name, "link")) {
                    std.log.debug("[Renderer] renderLayoutBox: skipping metadata tag '{s}'", .{tag_name});
                    return;
                }
            }
        }

        // 日志：渲染开始
        const node_type_str = switch (layout_box.node.node_type) {
            .element => if (layout_box.node.asElement()) |elem| elem.tag_name else "unknown",
            .text => "text",
            .comment => "comment",
            .document => "document",
            .doctype => "doctype",
        };
        std.log.debug("[Renderer] renderLayoutBox: node_type={s}, content=({d:.1}, {d:.1}, {d:.1}x{d:.1})", .{
            node_type_str,
            layout_box.box_model.content.x,
            layout_box.box_model.content.y,
            layout_box.box_model.content.width,
            layout_box.box_model.content.height,
        });

        // 计算样式（用于获取颜色、背景等）
        var cascade_engine = cascade.Cascade.init(self.allocator);
        var computed_style = try cascade_engine.computeStyle(layout_box.node, self.stylesheets);
        defer computed_style.deinit();

        // 获取布局框的位置和尺寸
        const content_box_rect = layout_box.box_model.content;
        const total_size = layout_box.box_model.totalSize();

        // 转换为backend.Rect
        const content_rect = backend.Rect.init(
            content_box_rect.x,
            content_box_rect.y,
            content_box_rect.width,
            content_box_rect.height,
        );

        // 计算边框框的位置（包含margin）
        const border_x = content_box_rect.x - layout_box.box_model.padding.left - layout_box.box_model.border.left;
        const border_y = content_box_rect.y - layout_box.box_model.padding.top - layout_box.box_model.border.top;
        const border_rect = backend.Rect.init(
            border_x,
            border_y,
            total_size.width,
            total_size.height,
        );

        // 1. 绘制背景（只对非文本节点绘制，避免覆盖文本）
        // 注意：对于包含文本节点的元素（如<p>），背景应该只绘制到内容区域，不覆盖descender
        if (layout_box.node.node_type != .text) {
            try self.renderBackground(layout_box, &computed_style, border_rect);
        }

        // 2. 绘制边框
        try self.renderBorder(layout_box, &computed_style, border_rect);

        // 3. 递归渲染子节点（先渲染子节点，确保文本在背景之上）
        for (layout_box.children.items) |child| {
            try self.renderLayoutBox(child);
        }

        // 4. 绘制内容（文本）- 在子节点之后绘制，确保文本在最上层
        try self.renderContent(layout_box, &computed_style, content_rect);
    }

    /// 渲染背景
    fn renderBackground(self: *Renderer, layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, rect: backend.Rect) !void {
        _ = layout_box;
        // 获取背景颜色
        const bg_color = self.getBackgroundColor(computed_style);

        std.log.debug("[Renderer] renderBackground: bg_color={?}, rect=({d:.1}, {d:.1}, {d:.1}x{d:.1})", .{
            bg_color, rect.x, rect.y, rect.width, rect.height,
        });

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

            std.log.debug("[Renderer] renderContent: text_node found, content=\"{s}\", len={d}", .{ text_content, text_content.len });

            // 如果文本内容为空，不渲染
            if (text_content.len == 0) {
                std.log.debug("[Renderer] renderContent: text is empty, skipping", .{});
                return;
            }
            
            // 检查是否只包含空白字符
            var is_whitespace_only = true;
            for (text_content) |c| {
                if (c != ' ' and c != '\n' and c != '\r' and c != '\t') {
                    is_whitespace_only = false;
                    break;
                }
            }
            if (is_whitespace_only) {
                std.log.debug("[Renderer] renderContent: text contains only whitespace, skipping", .{});
                return;
            }

            // 文本节点应该使用父元素的样式
            // 如果当前computed_style为空（文本节点没有自己的样式），尝试从父元素获取
            var text_computed_style = computed_style;
            var parent_computed_style_opt: ?cascade.ComputedStyle = null;
            if (layout_box.parent) |parent| {
                // 重新计算父元素的样式（用于文本节点继承）
                var cascade_engine = cascade.Cascade.init(self.allocator);
                var parent_computed_style = try cascade_engine.computeStyle(parent.node, self.stylesheets);
                
                // 如果当前样式为空或没有font-size，使用父元素的样式
                if (computed_style.getProperty("font-size") == null) {
                    parent_computed_style_opt = parent_computed_style;
                    text_computed_style = &parent_computed_style;
                } else {
                    parent_computed_style.deinit();
                }
            }
            defer if (parent_computed_style_opt) |*pcs| pcs.deinit();

            // 获取文本颜色和字体
            const text_color = self.getTextColor(text_computed_style);
            const font = self.getFont(text_computed_style);

            std.log.debug("[Renderer] renderContent: text_color={?}, font_size={d:.1}", .{ text_color, font.size });

            if (text_color) |color| {
                // 绘制文本
                // y坐标需要调整：rect.y是内容区域的顶部，我们需要计算基线位置
                // 基线位置 = rect.y + ascent
                // 使用字体大小的约70%作为ascent（典型值，实际应该从字体度量获取）
                // 注意：这确保descender（如'p'的尾巴）有足够空间显示
                // 进一步降低ascent比例，给descender留更多空间
                // 对于绝对定位的元素，rect.y是top属性的值，表示内容区域的顶部
                // 我们需要加上ascent来计算基线位置
                // 但是，如果rect.height为0（未设置高度），说明这是绝对定位的文本节点
                // 对于绝对定位的文本节点，top值应该直接作为基线位置（或者加上一个小的偏移）
                const ascent_ratio: f32 = 0.7; // 典型的ascent比例（降低以给descender更多空间）
                const baseline_y = rect.y + font.size * ascent_ratio;
                std.log.debug("[Renderer] renderContent: calling fillText at ({d:.1}, {d:.1}), text=\"{s}\", rect=({d:.1}, {d:.1}, {d:.1}x{d:.1}), font_size={d:.1}", .{ rect.x, baseline_y, text_content, rect.x, rect.y, rect.width, rect.height, font.size });
                self.render_backend.fillText(text_content, rect.x, baseline_y, font, color);
            } else {
                std.log.debug("[Renderer] renderContent: no text color, skipping", .{});
            }
        } else {
            std.log.debug("[Renderer] renderContent: not a text node (node_type={}), skipping", .{layout_box.node.node_type});
        }
    }

    /// 获取背景颜色
    fn getBackgroundColor(self: *Renderer, computed_style: *const cascade.ComputedStyle) ?backend.Color {
        _ = self;
        // 从computed_style中解析background-color属性
        if (style_utils.getPropertyColor(computed_style, "background-color")) |color| {
            return backend.Color.rgb(color.r, color.g, color.b);
        }
        // 如果没有设置背景颜色，返回null（不绘制背景）
        // 这样可以避免白色背景覆盖文本的descender
        return null;
    }

    /// 获取边框颜色
    fn getBorderColor(self: *Renderer, computed_style: *const cascade.ComputedStyle) ?backend.Color {
        // 从computed_style中解析border-color属性
        if (style_utils.getPropertyColor(computed_style, "border-color")) |color| {
            return backend.Color.rgb(color.r, color.g, color.b);
        }
        // 如果没有设置border-color，检查是否有border-width
        // 如果有border-width但没有color，返回默认黑色
        if (self.getBorderWidth(computed_style) > 0) {
            return backend.Color.rgb(0, 0, 0); // 默认黑色边框
        }
        return null; // 无边框
    }

    /// 获取边框宽度
    fn getBorderWidth(self: *Renderer, computed_style: *const cascade.ComputedStyle) f32 {
        _ = self;
        // 从computed_style中解析border-width属性
        // 简化：使用包含块宽度作为参考（实际应该使用元素的宽度）
        const containing_width: f32 = 800; // 简化：使用固定值
        if (style_utils.getPropertyLength(computed_style, "border-width", containing_width)) |width| {
            return width;
        }
        // 如果没有设置border-width，检查border-top-width等单独属性
        // 简化：只检查border-top-width
        if (style_utils.getPropertyLength(computed_style, "border-top-width", containing_width)) |width| {
            return width;
        }
        return 0;
    }

    /// 获取文本颜色
    fn getTextColor(self: *Renderer, computed_style: *const cascade.ComputedStyle) ?backend.Color {
        _ = self;
        // 从computed_style中解析color属性
        if (style_utils.getPropertyColor(computed_style, "color")) |color| {
            return backend.Color.rgb(color.r, color.g, color.b);
        }
        // 默认返回黑色
        return backend.Color.rgb(0, 0, 0);
    }

    /// 获取字体
    fn getFont(self: *Renderer, computed_style: *const cascade.ComputedStyle) backend.Font {
        _ = self;
        var font = backend.Font{
            .family = "Arial",
            .size = 16,
            .weight = .normal,
            .style = .normal,
        };

        // 解析font-size
        const containing_width: f32 = 800; // 简化：使用固定值
        if (style_utils.getPropertyLength(computed_style, "font-size", containing_width)) |size| {
            font.size = size;
        }

        // 解析font-weight
        if (style_utils.getPropertyKeyword(computed_style, "font-weight")) |weight| {
            if (std.mem.eql(u8, weight, "bold") or std.mem.eql(u8, weight, "700") or std.mem.eql(u8, weight, "800") or std.mem.eql(u8, weight, "900")) {
                font.weight = .bold;
            }
        }

        // 解析font-style
        if (style_utils.getPropertyKeyword(computed_style, "font-style")) |style| {
            if (std.mem.eql(u8, style, "italic") or std.mem.eql(u8, style, "oblique")) {
                font.style = .italic;
            }
        }

        // 解析font-family（简化：只取第一个字体）
        if (style_utils.getPropertyKeyword(computed_style, "font-family")) |family| {
            // 简化：直接使用family字符串（实际应该解析字体列表）
            font.family = family;
        }

        return font;
    }
};
