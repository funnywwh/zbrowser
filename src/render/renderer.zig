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
                    std.mem.eql(u8, tag_name, "link"))
                {
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

        // 2. 处理overflow属性（如果为hidden、scroll或auto，需要裁剪）
        const needs_clip = layout_box.overflow != .visible;
        if (needs_clip) {
            // 保存当前状态
            self.render_backend.save();
            // 设置裁剪区域为内容区域（包含padding）
            const clip_rect = backend.Rect.init(
                content_box_rect.x,
                content_box_rect.y,
                content_box_rect.width,
                content_box_rect.height,
            );
            self.render_backend.clip(clip_rect);
        }

        // 3. 递归渲染子节点（先渲染子节点，确保文本在背景之上）
        for (layout_box.children.items) |child| {
            try self.renderLayoutBox(child);
        }

        // 4. 绘制内容（文本）- 在子节点之后绘制，确保文本在最上层
        try self.renderContent(layout_box, &computed_style, content_rect);

        // 5. 恢复裁剪状态（如果设置了）
        if (needs_clip) {
            self.render_backend.restore();
        }

        // 6. 绘制边框（最后绘制，确保边框在最上层）
        try self.renderBorder(layout_box, &computed_style, border_rect);
    }

    /// 绘制圆角矩形路径
    /// 使用路径API绘制圆角矩形
    fn drawRoundedRectPath(self: *Renderer, rect: backend.Rect, radius: f32) void {
        const x = rect.x;
        const y = rect.y;
        const w = rect.width;
        const h = rect.height;
        
        // 限制圆角半径不超过矩形宽度和高度的一半
        const max_radius = @min(w / 2.0, h / 2.0);
        const r = @min(radius, max_radius);
        
        // 如果圆角半径为0或很小，使用普通矩形
        if (r < 0.5) {
            // 使用普通矩形路径
            self.render_backend.beginPath();
            self.render_backend.moveTo(x, y);
            self.render_backend.lineTo(x + w, y);
            self.render_backend.lineTo(x + w, y + h);
            self.render_backend.lineTo(x, y + h);
            self.render_backend.closePath();
            return;
        }
        
        // 绘制圆角矩形路径（顺时针）
        self.render_backend.beginPath();
        
        // 左上角圆弧（从180度到270度，即从左边到上边）
        self.render_backend.arc(x + r, y + r, r, std.math.pi, 3.0 * std.math.pi / 2.0);
        
        // 上边直线
        self.render_backend.lineTo(x + w - r, y);
        
        // 右上角圆弧（从270度到0度，即从上边到右边）
        self.render_backend.arc(x + w - r, y + r, r, 3.0 * std.math.pi / 2.0, 0);
        
        // 右边直线
        self.render_backend.lineTo(x + w, y + h - r);
        
        // 右下角圆弧（从0度到90度，即从右边到下边）
        self.render_backend.arc(x + w - r, y + h - r, r, 0, std.math.pi / 2.0);
        
        // 下边直线
        self.render_backend.lineTo(x + r, y + h);
        
        // 左下角圆弧（从90度到180度，即从下边到左边）
        self.render_backend.arc(x + r, y + h - r, r, std.math.pi / 2.0, std.math.pi);
        
        // 左边直线（回到起点）
        self.render_backend.closePath();
    }

    /// 渲染背景
    fn renderBackground(self: *Renderer, layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, rect: backend.Rect) !void {
        // 获取背景颜色
        const bg_color = self.getBackgroundColor(computed_style);

        std.log.debug("[Renderer] renderBackground: bg_color={?}, rect=({d:.1}, {d:.1}, {d:.1}x{d:.1})", .{
            bg_color, rect.x, rect.y, rect.width, rect.height,
        });

        if (bg_color) |color| {
            // 检查是否有圆角
            if (layout_box.box_model.border_radius) |radius| {
                // 绘制圆角背景
                self.drawRoundedRectPath(rect, radius);
                self.render_backend.fill(color);
            } else {
                // 绘制普通矩形背景
                self.render_backend.fillRect(rect, color);
            }
        }
    }

    /// 获取边框样式
    fn getBorderStyle(self: *Renderer, computed_style: *const cascade.ComputedStyle) ?[]const u8 {
        // 先检查单独的border-style属性
        if (style_utils.getPropertyKeyword(computed_style, "border-style")) |style| {
            return style;
        }
        // 如果没有单独的border-style，尝试从border简写属性中提取
        if (style_utils.getPropertyKeyword(computed_style, "border")) |border_value| {
            if (self.parseBorderShorthand(border_value)) |border_info| {
                if (border_info.style) |style| {
                    return style;
                }
            }
        }
        // 默认返回solid
        return "solid";
    }

    /// 渲染边框
    fn renderBorder(self: *Renderer, layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, rect: backend.Rect) !void {
        // 获取边框颜色、宽度和样式
        const border_color = self.getBorderColor(computed_style);
        const border_width = self.getBorderWidth(computed_style);
        const border_style = self.getBorderStyle(computed_style);

        std.log.debug("[Renderer] renderBorder: border_color={?}, border_width={d:.1}, border_style={?s}, rect=({d:.1}, {d:.1}, {d:.1}x{d:.1})", .{
            border_color, border_width, border_style, rect.x, rect.y, rect.width, rect.height,
        });

        if (border_color) |color| {
            if (border_width > 0) {
                // 检查边框样式
                const style = border_style orelse "solid";
                const is_dashed = std.mem.eql(u8, style, "dashed");
                
                // 检查是否有圆角
                if (layout_box.box_model.border_radius) |radius| {
                    // 绘制圆角边框
                    self.drawRoundedRectPath(rect, radius);
                    if (is_dashed) {
                        // TODO: 圆角虚线边框需要更复杂的实现
                        // 当前简化：使用实线
                        self.render_backend.stroke(color, border_width);
                    } else {
                        self.render_backend.stroke(color, border_width);
                    }
                } else {
                    // 绘制矩形边框
                    if (is_dashed) {
                        // 绘制虚线边框
                        self.render_backend.strokeDashedRect(rect, color, border_width);
                    } else {
                        // 绘制实线边框
                        std.log.debug("[Renderer] renderBorder: calling strokeRect with color=#{x:0>2}{x:0>2}{x:0>2}, width={d:.1}", .{
                            color.r, color.g, color.b, border_width,
                        });
                        self.render_backend.strokeRect(rect, color, border_width);
                    }
                }
            } else {
                std.log.debug("[Renderer] renderBorder: border_width is 0, skipping", .{});
            }
        } else {
            std.log.debug("[Renderer] renderBorder: border_color is null, skipping", .{});
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
                    // 注意：必须使用parent_computed_style_opt的地址，而不是parent_computed_style的地址
                    // 因为parent_computed_style在if块结束后会被销毁
                    text_computed_style = &parent_computed_style_opt.?;
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
                // 计算文本对齐后的x坐标
                var text_x = rect.x;
                
                // 获取父元素的text-align属性（如果存在）
                if (layout_box.parent) |parent| {
                    // 计算文本宽度（使用估算值）
                    // TODO: 完整实现需要从render_backend获取准确的文本宽度
                    // 当前使用简化的估算：每个字符宽度约为字体大小的0.7倍
                    const char_width = font.size * 0.7;
                    const text_width = char_width * @as(f32, @floatFromInt(text_content.len));
                    
                    // 根据text-align调整x坐标
                    switch (parent.text_align) {
                        .left => {
                            // 左对齐（默认），不需要调整
                            text_x = rect.x;
                        },
                        .center => {
                            // 居中对齐：x = 容器左边界 + (容器宽度 - 文本宽度) / 2
                            text_x = rect.x + (rect.width - text_width) / 2.0;
                        },
                        .right => {
                            // 右对齐：x = 容器右边界 - 文本宽度
                            text_x = rect.x + rect.width - text_width;
                        },
                        .justify => {
                            // 两端对齐（简化实现：暂时按左对齐处理）
                            // TODO: 完整实现需要调整字符间距
                            text_x = rect.x;
                        },
                    }
                }
                
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
                
                // 获取line-height（从父元素继承）
                const line_height = if (layout_box.parent) |parent| parent.line_height else .normal;
                const actual_line_height = style_utils.computeLineHeight(line_height, font.size);
                
                // 如果line-height大于字体大小，文本应该垂直居中在行高内
                // 基线位置 = rect.y + (line-height - font.size) / 2 + ascent
                // 如果line-height小于等于字体大小，使用原来的计算方式
                const baseline_y = if (actual_line_height > font.size) 
                    rect.y + (actual_line_height - font.size) / 2.0 + font.size * ascent_ratio
                else
                    rect.y + font.size * ascent_ratio;
                // 获取letter-spacing（从父元素继承）
                const letter_spacing = if (layout_box.parent) |parent| parent.letter_spacing else null;
                
                std.log.debug("[Renderer] renderContent: calling fillText at ({d:.1}, {d:.1}), text=\"{s}\", rect=({d:.1}, {d:.1}, {d:.1}x{d:.1}), font_size={d:.1}, text_align={}, letter_spacing={?}", .{ text_x, baseline_y, text_content, rect.x, rect.y, rect.width, rect.height, font.size, if (layout_box.parent) |p| p.text_align else .left, letter_spacing });
                self.render_backend.fillText(text_content, text_x, baseline_y, font, color, letter_spacing);
                
                // 绘制文本装饰（text-decoration）
                // 获取父元素的text-decoration属性（文本节点继承父元素的装饰）
                const text_decoration = if (layout_box.parent) |parent| parent.text_decoration else .none;
                if (text_decoration != .none) {
                    // 计算文本宽度（使用估算值）
                    const char_width = font.size * 0.7;
                    const text_width = char_width * @as(f32, @floatFromInt(text_content.len));
                    
                    // 计算装饰线的位置和宽度
                    const decoration_width = @max(1.0, font.size * 0.05); // 装饰线宽度约为字体大小的5%
                    
                    switch (text_decoration) {
                        .underline => {
                            // 下划线：在基线下方
                            const underline_y = baseline_y + font.size * 0.2; // 基线下方约20%字体大小
                            const decoration_rect = backend.Rect.init(text_x, underline_y, text_width, decoration_width);
                            self.render_backend.fillRect(decoration_rect, color);
                        },
                        .line_through => {
                            // 删除线：在文本中间
                            const strikethrough_y = baseline_y - font.size * 0.3; // 基线下方约30%字体大小（文本中间）
                            const decoration_rect = backend.Rect.init(text_x, strikethrough_y, text_width, decoration_width);
                            self.render_backend.fillRect(decoration_rect, color);
                        },
                        .overline => {
                            // 上划线：在文本上方
                            const overline_y = baseline_y - font.size * 0.7; // 基线下方约70%字体大小（文本上方）
                            const decoration_rect = backend.Rect.init(text_x, overline_y, text_width, decoration_width);
                            self.render_backend.fillRect(decoration_rect, color);
                        },
                        .none => {}, // 不会到达这里
                    }
                }
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
            std.log.debug("[Renderer] getBorderColor: found border-color property", .{});
            return backend.Color.rgb(color.r, color.g, color.b);
        }
        // 如果没有设置border-color，尝试从border简写属性中提取颜色
        // 先检查computed_style中是否有border属性
        if (computed_style.getProperty("border")) |decl| {
            std.log.debug("[Renderer] getBorderColor: found border property in computed_style, value type = {s}", .{@tagName(decl.value)});
            if (decl.value == .keyword) {
                const border_value = decl.value.keyword;
                std.log.debug("[Renderer] getBorderColor: found border shorthand property = '{s}'", .{border_value});
                if (self.parseBorderShorthand(border_value)) |border_info| {
                    if (border_info.color) |color| {
                        std.log.debug("[Renderer] getBorderColor: parsed color from border shorthand = #{x:0>2}{x:0>2}{x:0>2}", .{ color.r, color.g, color.b });
                        return backend.Color.rgb(color.r, color.g, color.b);
                    } else {
                        std.log.debug("[Renderer] getBorderColor: border shorthand has no color", .{});
                    }
                } else {
                    std.log.debug("[Renderer] getBorderColor: failed to parse border shorthand", .{});
                }
            }
        }
        // 也尝试使用style_utils.getPropertyKeyword（兼容性检查）
        if (style_utils.getPropertyKeyword(computed_style, "border")) |border_value| {
            std.log.debug("[Renderer] getBorderColor: found border shorthand property via style_utils = '{s}'", .{border_value});
            if (self.parseBorderShorthand(border_value)) |border_info| {
                if (border_info.color) |color| {
                    std.log.debug("[Renderer] getBorderColor: parsed color from border shorthand = #{x:0>2}{x:0>2}{x:0>2}", .{ color.r, color.g, color.b });
                    return backend.Color.rgb(color.r, color.g, color.b);
                }
            }
        } else {
            std.log.debug("[Renderer] getBorderColor: no border property found", .{});
        }
        // 如果没有设置border-color，检查是否有border-width
        // 如果有border-width但没有color，返回默认黑色
        const border_width = self.getBorderWidth(computed_style);
        if (border_width > 0) {
            std.log.debug("[Renderer] getBorderColor: border-width > 0, using default black", .{});
            return backend.Color.rgb(0, 0, 0); // 默认黑色边框
        }
        return null; // 无边框
    }

    /// 获取边框宽度
    fn getBorderWidth(self: *Renderer, computed_style: *const cascade.ComputedStyle) f32 {
        // 从computed_style中解析border-width属性
        // 简化：使用包含块宽度作为参考（实际应该使用元素的宽度）
        const containing_width: f32 = 800; // 简化：使用固定值
        const border_context = style_utils.createUnitContext(containing_width);
        if (style_utils.getPropertyLength(computed_style, "border-width", border_context)) |width| {
            std.log.debug("[Renderer] getBorderWidth: found border-width property = {d:.1}", .{width});
            return width;
        }
        // 如果没有设置border-width，尝试从border简写属性中提取宽度
        if (style_utils.getPropertyKeyword(computed_style, "border")) |border_value| {
            std.log.debug("[Renderer] getBorderWidth: found border shorthand property = '{s}'", .{border_value});
            if (self.parseBorderShorthand(border_value)) |border_info| {
                if (border_info.width) |width| {
                    std.log.debug("[Renderer] getBorderWidth: parsed width from border shorthand = {d:.1}", .{width});
                    return width;
                } else {
                    std.log.debug("[Renderer] getBorderWidth: border shorthand has no width", .{});
                }
            } else {
                std.log.debug("[Renderer] getBorderWidth: failed to parse border shorthand", .{});
            }
        } else {
            std.log.debug("[Renderer] getBorderWidth: no border property found", .{});
        }
        // 如果没有设置border-width，检查border-top-width等单独属性
        // 简化：只检查border-top-width
        const border_top_context = style_utils.createUnitContext(containing_width);
        if (style_utils.getPropertyLength(computed_style, "border-top-width", border_top_context)) |width| {
            std.log.debug("[Renderer] getBorderWidth: found border-top-width property = {d:.1}", .{width});
            return width;
        }
        std.log.debug("[Renderer] getBorderWidth: no border width found, returning 0", .{});
        return 0;
    }

    /// 解析border简写属性
    /// 格式：border: <width> <style> <color>
    /// 例如：border: 2px solid #2196f3
    fn parseBorderShorthand(self: *Renderer, border_value: []const u8) ?struct { width: ?f32, style: ?[]const u8, color: ?css_parser.Value.Color } {
        _ = self;
        // 按空格分割值
        var parts = std.mem.splitSequence(u8, border_value, " ");
        var width: ?f32 = null;
        var style: ?[]const u8 = null;
        var color: ?css_parser.Value.Color = null;

        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t\n\r");
            if (trimmed.len == 0) continue;

            // 检查是否是长度值（如 "2px"）
            if (std.mem.indexOfScalar(u8, trimmed, 'p') != null and std.mem.indexOfScalar(u8, trimmed, 'x') != null) {
                const px_pos = std.mem.indexOfScalar(u8, trimmed, 'p') orelse continue;
                if (px_pos + 1 < trimmed.len and trimmed[px_pos + 1] == 'x') {
                    const num_str = std.mem.trim(u8, trimmed[0..px_pos], " \t\n\r");
                    if (std.fmt.parseFloat(f64, num_str)) |num| {
                        width = @as(f32, @floatCast(num));
                        continue;
                    } else |_| {}
                }
            }

            // 检查是否是颜色值（以#开头）
            if (trimmed.len > 0 and trimmed[0] == '#') {
                const color_hash = trimmed[1..]; // 去掉#号
                if (parseColorFromHashStatic(color_hash) catch null) |c| {
                    color = c;
                    continue;
                }
            }

            // 检查是否是边框样式关键字（solid, dashed, dotted等）
            if (std.mem.eql(u8, trimmed, "solid") or
                std.mem.eql(u8, trimmed, "dashed") or
                std.mem.eql(u8, trimmed, "dotted") or
                std.mem.eql(u8, trimmed, "double") or
                std.mem.eql(u8, trimmed, "none"))
            {
                style = trimmed;
                continue;
            }
        }

        return .{ .width = width, .style = style, .color = color };
    }

    /// 从十六进制字符串解析颜色值（静态辅助函数）
    fn parseColorFromHashStatic(hash: []const u8) !css_parser.Value.Color {
        // 解析#rgb或#rrggbb格式
        if (hash.len == 3) {
            // #rgb格式
            const r = try std.fmt.parseInt(u8, &[_]u8{ hash[0], hash[0] }, 16);
            const g = try std.fmt.parseInt(u8, &[_]u8{ hash[1], hash[1] }, 16);
            const b = try std.fmt.parseInt(u8, &[_]u8{ hash[2], hash[2] }, 16);
            return css_parser.Value.Color{ .r = r, .g = g, .b = b };
        } else if (hash.len == 6) {
            // #rrggbb格式
            const r = try std.fmt.parseInt(u8, hash[0..2], 16);
            const g = try std.fmt.parseInt(u8, hash[2..4], 16);
            const b = try std.fmt.parseInt(u8, hash[4..6], 16);
            return css_parser.Value.Color{ .r = r, .g = g, .b = b };
        }
        return error.InvalidColor;
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
        const font_size_context = style_utils.createUnitContext(containing_width);
        if (style_utils.getPropertyLength(computed_style, "font-size", font_size_context)) |size| {
            font.size = size;
        }

        // 解析font-weight
        if (style_utils.getPropertyKeyword(computed_style, "font-weight")) |weight| {
            if (std.mem.eql(u8, weight, "bold") or std.mem.eql(u8, weight, "700") or std.mem.eql(u8, weight, "800") or std.mem.eql(u8, weight, "900")) {
                font.weight = .bold;
            } else if (std.mem.eql(u8, weight, "lighter") or std.mem.eql(u8, weight, "100") or std.mem.eql(u8, weight, "200") or std.mem.eql(u8, weight, "300")) {
                font.weight = .lighter;
            } else if (std.mem.eql(u8, weight, "normal") or std.mem.eql(u8, weight, "400")) {
                font.weight = .normal;
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
