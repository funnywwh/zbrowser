const std = @import("std");
const builtin = @import("builtin");

/// 调试输出函数（只在Debug模式下输出）
/// 使用条件编译，在Release模式下完全移除，避免性能影响
inline fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        std.debug.print(fmt, args);
    }
}
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
    cascade_engine: cascade.Cascade, // 复用的Cascade实例，避免重复创建（用于向后兼容场景）
    // 复用的ArrayList，避免在renderLayoutBox中重复分配
    // 注意：当前实现使用混合排序，不再需要单独的缓冲区
    // 保留children_buffer以备将来使用（如果需要优化）
    children_buffer: std.ArrayList(*box.LayoutBox), // 保留以备将来使用

    /// 初始化渲染器
    pub fn init(allocator: std.mem.Allocator, render_backend: *backend.RenderBackend) Renderer {
        return .{
            .allocator = allocator,
            .render_backend = render_backend,
            .cascade_engine = cascade.Cascade.init(allocator),
            .children_buffer = std.ArrayList(*box.LayoutBox){},
        };
    }

    /// 清理渲染器
    pub fn deinit(self: *Renderer) void {
        self.children_buffer.deinit(self.allocator);
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
                    return;
                }
            }
        }

        // 使用布局阶段已计算的样式（避免重复计算）
        // 如果LayoutBox中没有存储样式，则重新计算（向后兼容）
        var computed_style: *cascade.ComputedStyle = undefined;
        var temp_style: cascade.ComputedStyle = undefined;
        var needs_deinit = false;
        if (layout_box.computed_style) |*cs| {
            computed_style = cs;
            needs_deinit = false;
        } else {
            // 向后兼容：如果样式未计算，则重新计算
            // 复用Renderer的cascade_engine实例，避免重复创建
            temp_style = try self.cascade_engine.computeStyle(layout_box.node, self.stylesheets);
            computed_style = &temp_style;
            needs_deinit = true;
        }
        errdefer if (needs_deinit) computed_style.deinit();
        defer if (needs_deinit) computed_style.deinit();

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

        // 计算边框框的位置（包含padding和border，但不包含margin）
        // border_rect用于绘制背景和边框，margin是元素外部的空间，不应该影响绘制位置
        const border_x = content_box_rect.x - layout_box.box_model.padding.left - layout_box.box_model.border.left;
        const border_y = content_box_rect.y - layout_box.box_model.padding.top - layout_box.box_model.border.top;
        const border_rect = backend.Rect.init(
            border_x,
            border_y,
            total_size.width,
            total_size.height,
        );

        // 1. 应用opacity（如果小于1.0，需要设置全局透明度）
        const needs_opacity = layout_box.opacity < 1.0;
        var state_saved = false;
        if (needs_opacity) {
            // 保存当前状态（包括透明度）
            self.render_backend.save();
            state_saved = true;
            // 设置全局透明度（opacity会影响整个元素及其子元素）
            self.render_backend.setGlobalAlpha(layout_box.opacity);
        }

        // 4. 处理overflow属性（如果为hidden、scroll或auto，需要裁剪）
        // CSS规范说明：
        // - overflow: visible - 不裁剪溢出内容（默认值）
        // - overflow: hidden - 裁剪溢出内容，不显示滚动条
        // - overflow: scroll - 总是显示滚动条（即使内容不溢出），并裁剪溢出内容
        // - overflow: auto - 只在内容溢出时显示滚动条，并裁剪溢出内容
        // 
        // 对于headless浏览器（只输出PNG图片），我们只需要正确裁剪内容即可
        // TODO: 完整实现需要：
        // 1. 检测内容是否溢出（计算子元素的实际尺寸）
        // 2. 对于overflow: auto，只在内容溢出时应用裁剪
        // 3. 对于overflow: scroll，可以考虑渲染滚动条（视觉上）
        // 4. 处理滚动偏移（但这需要交互，对于headless浏览器可能不需要）
        const needs_clip = layout_box.overflow != .visible;
        if (needs_clip) {
            // 保存当前状态（如果还没有保存）
            if (!needs_opacity) {
                self.render_backend.save();
                state_saved = true;
            }
            // 设置裁剪区域为内容区域（包含padding）
            // 注意：对于overflow: auto，理论上应该只在内容溢出时应用裁剪
            // 但为了简化实现，我们总是应用裁剪（与hidden和scroll相同）
            const clip_rect = backend.Rect.init(
                content_box_rect.x,
                content_box_rect.y,
                content_box_rect.width,
                content_box_rect.height,
            );
            self.render_backend.clip(clip_rect);
        }
        
        // 确保在错误路径上也恢复状态
        errdefer {
            if (state_saved) {
                self.render_backend.restore();
            }
        }

        // 按照CSS规范确定渲染顺序（根据层叠上下文规则）
        // CSS规范定义的渲染顺序（从下到上）：
        // 1. 形成层叠上下文的元素的背景和边框（背景在边框下方）
        // 2. z-index < 0 的子元素
        // 3. 非定位的块级元素
        // 4. 非定位的浮动元素
        // 5. 非定位的内联元素
        // 6. z-index = 0 的子元素
        // 7. z-index > 0 的子元素
        // 8. 内容（文本）
        // 9. 边框（在内容上方）
        //
        // 对于单个元素的渲染顺序：
        // 1. box-shadow（阴影在背景下方）
        // 2. background（背景在内容下方）
        // 3. 子元素（按z-index排序，已在下面实现）
        // 4. 内容（文本）
        // 5. border（边框在内容上方）
        
        // 步骤1：绘制阴影（box-shadow在背景下方）
        if (layout_box.box_shadow) |shadow| {
            try self.renderBoxShadow(layout_box, shadow, border_rect);
        }

        // 步骤2：绘制背景（background在内容下方）
        // 注意：对于包含文本节点的元素（如<p>），背景应该只绘制到内容区域，不覆盖descender
        if (layout_box.node.node_type != .text) {
            try self.renderBackground(layout_box, computed_style, border_rect);
        }

        // 步骤3：递归渲染子节点（按z-index排序）
        // 按照CSS规范实现z-index混合渲染顺序：
        // 1. 所有元素（包括普通元素和positioned元素）按照z-index值排序
        // 2. 相同z-index的元素按照DOM顺序排序
        // 3. z-index为auto的positioned元素应该按照DOM顺序，与z-index为0的元素一起处理
        
        // 收集所有子元素，并记录它们的z-index值和DOM顺序
        // 使用结构体存储元素和其z-index值，以便排序
        const ChildWithZIndex = struct {
            child: *box.LayoutBox,
            z_index: i32, // 使用i32以支持负值
            dom_order: usize, // DOM顺序（用于相同z-index时的排序）
        };
        
        // 临时存储所有子元素及其z-index信息
        var children_with_z: std.ArrayList(ChildWithZIndex) = std.ArrayList(ChildWithZIndex){};
        defer children_with_z.deinit(self.allocator);
        
        // 收集所有子元素
        for (layout_box.children.items, 0..) |child, dom_order| {
            const is_positioned = child.position != .static;
            // 计算z-index值：
            // - 如果是positioned元素且有z-index，使用z-index值
            // - 如果是positioned元素但z-index为auto（null），使用0（与普通元素相同）
            // - 如果是普通元素（static），使用0
            const z_index_value: i32 = if (is_positioned) 
                (child.z_index orelse 0)
            else 
                0;
            try children_with_z.append(self.allocator, ChildWithZIndex{
                .child = child,
                .z_index = z_index_value,
                .dom_order = dom_order,
            });
        }
        
        // 按照z-index值排序，相同z-index按DOM顺序排序
        std.mem.sort(ChildWithZIndex, children_with_z.items, {}, struct {
            fn lessThan(_: void, a: ChildWithZIndex, b: ChildWithZIndex) bool {
                // 首先按z-index排序
                if (a.z_index != b.z_index) {
                    return a.z_index < b.z_index;
                }
                // 相同z-index时，按DOM顺序排序
                return a.dom_order < b.dom_order;
            }
        }.lessThan);
        
        // 按排序后的顺序渲染所有子元素
        for (children_with_z.items) |item| {
            try self.renderLayoutBox(item.child);
        }

        // 步骤4：绘制内容（文本在子节点之后，确保文本在最上层）
        try self.renderContent(layout_box, computed_style, content_rect);

        // 步骤5：绘制边框（border在内容上方，确保边框在最上层）
        try self.renderBorder(layout_box, computed_style, border_rect);

        // 7. 恢复状态（如果应用了opacity或clip）
        // 注意：正常路径恢复状态，错误路径通过errdefer恢复
        if (state_saved) {
            self.render_backend.restore();
        }
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
        // 从左上角开始，移动到上边左端（圆弧起点）
        self.render_backend.beginPath();
        self.render_backend.moveTo(x + r, y);
        
        // 上边直线（从左端到右端）
        self.render_backend.lineTo(x + w - r, y);
        
        // 右上角圆弧（从270度到360度/0度，即从上边到右边）
        // 圆弧中心：(x + w - r, y + r)，半径：r
        // 起点：(x + w - r, y) 对应角度270度（3π/2）
        // 终点：(x + w, y + r) 对应角度0度（2π）
        // 注意：arc函数会从start角度开始添加点，第一个点应该正好是当前点
        // 但为了确保连续性，我们需要确保arc的第一个点与当前点匹配
        // 由于arc函数直接添加点而不检查当前点，我们需要确保路径连续
        // 使用2π而不是0，确保角度递增（从270度到360度）
        const pi = std.math.pi;
        const pi_2 = pi / 2.0;
        const pi_3_2 = 3.0 * pi / 2.0;
        const pi_2x = 2.0 * pi;
        
        // 右上角圆弧：从270度到360度（0度）
        // arc函数会添加从start到end的所有点，包括start和end
        // 第一个点：(x + w - r + r*cos(3π/2), y + r + r*sin(3π/2)) = (x + w - r, y)
        // 最后一个点：(x + w - r + r*cos(2π), y + r + r*sin(2π)) = (x + w, y + r)
        self.render_backend.arc(x + w - r, y + r, r, pi_3_2, pi_2x);
        
        // 右边直线（从上端到下端）
        self.render_backend.lineTo(x + w, y + h - r);
        
        // 右下角圆弧（从0度到90度，即从右边到下边）
        self.render_backend.arc(x + w - r, y + h - r, r, 0, pi_2);
        
        // 下边直线（从右端到左端）
        self.render_backend.lineTo(x + r, y + h);
        
        // 左下角圆弧（从90度到180度，即从下边到左边）
        self.render_backend.arc(x + r, y + h - r, r, pi_2, pi);
        
        // 左上角圆弧（从180度到270度，即从左边到上边）
        self.render_backend.arc(x + r, y + r, r, pi, pi_3_2);
        
        // 闭合路径（回到起点）
        self.render_backend.closePath();
    }

    /// 绘制圆角虚线边框
    /// 沿着圆角矩形的路径分段绘制虚线
    /// 实现思路：
    /// 1. 将圆角矩形路径分成多个段（上边、右上角、右边、右下角、下边、左下角、左边、左上角）
    /// 2. 对每段分别绘制虚线
    /// 3. 对于直线段，使用现有的虚线绘制逻辑
    /// 4. 对于圆弧段，沿着圆弧分段绘制虚线
    fn renderDashedRoundedRect(self: *Renderer, rect: backend.Rect, radius: f32, color: backend.Color, width: f32) !void {
        const x = rect.x;
        const y = rect.y;
        const w = rect.width;
        const h = rect.height;
        
        // 限制圆角半径不超过矩形宽度和高度的一半
        const max_radius = @min(w / 2.0, h / 2.0);
        const r = @min(radius, max_radius);
        
        // 如果圆角半径为0或很小，使用普通虚线矩形
        if (r < 0.5) {
            self.render_backend.strokeDashedRect(rect, color, width);
            return;
        }

        // 虚线模式：每段长度约为边框宽度的3倍，间隔为边框宽度的2倍
        const dash_length = @max(3.0, width * 3.0);
        const gap_length = @max(2.0, width * 2.0);
        const dash_pattern_length = dash_length + gap_length;

        // 计算圆角矩形的各段长度
        const top_length = w - r * 2.0;
        const right_length = h - r * 2.0;
        const bottom_length = w - r * 2.0;
        const left_length = h - r * 2.0;
        const arc_length = std.math.pi * r / 2.0; // 每个圆弧的长度（90度）

        // 沿着路径绘制虚线
        var current_distance: f32 = 0.0;
        var is_dash = true; // 当前是否在绘制虚线（true=绘制，false=间隔）

        // 1. 上边（从左到右）
        const top_start_x = x + r;
        var segment_pos: f32 = 0.0;
        while (segment_pos < top_length) {
            const remaining_in_segment = top_length - segment_pos;
            const pattern_offset = @mod(current_distance, dash_pattern_length);
            const remaining_in_pattern = if (is_dash) (dash_length - pattern_offset) else (gap_length - (pattern_offset - dash_length));
            const draw_length = @min(remaining_in_segment, remaining_in_pattern);
            
            if (is_dash and draw_length > 0) {
                // 绘制虚线段
                const start_x = top_start_x + segment_pos;
                const end_x = start_x + draw_length;
                // 使用路径API绘制线段
                self.render_backend.beginPath();
                self.render_backend.moveTo(start_x, y);
                self.render_backend.lineTo(end_x, y);
                self.render_backend.stroke(color, width);
            }
            
            segment_pos += draw_length;
            current_distance += draw_length;
            
            // 检查是否需要切换模式
            if (draw_length >= remaining_in_pattern) {
                is_dash = !is_dash;
            }
        }

        // 2. 右上角圆弧（从270度到360度/0度）
        const arc_center_x = x + w - r;
        const arc_center_y = y + r;
        const arc_start_angle = 3.0 * std.math.pi / 2.0;
        const arc_end_angle = 2.0 * std.math.pi;
        segment_pos = 0.0;
        while (segment_pos < arc_length) {
            const remaining_in_segment = arc_length - segment_pos;
            const pattern_offset = @mod(current_distance, dash_pattern_length);
            const remaining_in_pattern = if (is_dash) (dash_length - pattern_offset) else (gap_length - (pattern_offset - dash_length));
            const draw_length = @min(remaining_in_segment, remaining_in_pattern);
            
            if (is_dash and draw_length > 0) {
                // 绘制圆弧段
                const start_angle = arc_start_angle + (segment_pos / arc_length) * (arc_end_angle - arc_start_angle);
                const end_angle = start_angle + (draw_length / arc_length) * (arc_end_angle - arc_start_angle);
                self.render_backend.beginPath();
                self.render_backend.arc(arc_center_x, arc_center_y, r, start_angle, end_angle);
                self.render_backend.stroke(color, width);
            }
            
            segment_pos += draw_length;
            current_distance += draw_length;
            
            if (draw_length >= remaining_in_pattern) {
                is_dash = !is_dash;
            }
        }

        // 3. 右边（从上到下）
        const right_start_y = y + r;
        segment_pos = 0.0;
        while (segment_pos < right_length) {
            const remaining_in_segment = right_length - segment_pos;
            const pattern_offset = @mod(current_distance, dash_pattern_length);
            const remaining_in_pattern = if (is_dash) (dash_length - pattern_offset) else (gap_length - (pattern_offset - dash_length));
            const draw_length = @min(remaining_in_segment, remaining_in_pattern);
            
            if (is_dash and draw_length > 0) {
                const start_y = right_start_y + segment_pos;
                const end_y = start_y + draw_length;
                self.render_backend.beginPath();
                self.render_backend.moveTo(x + w, start_y);
                self.render_backend.lineTo(x + w, end_y);
                self.render_backend.stroke(color, width);
            }
            
            segment_pos += draw_length;
            current_distance += draw_length;
            
            if (draw_length >= remaining_in_pattern) {
                is_dash = !is_dash;
            }
        }

        // 4. 右下角圆弧（从0度到90度）
        const arc_center_x2 = x + w - r;
        const arc_center_y2 = y + h - r;
        const arc_start_angle2 = 0.0;
        const arc_end_angle2 = std.math.pi / 2.0;
        segment_pos = 0.0;
        while (segment_pos < arc_length) {
            const remaining_in_segment = arc_length - segment_pos;
            const pattern_offset = @mod(current_distance, dash_pattern_length);
            const remaining_in_pattern = if (is_dash) (dash_length - pattern_offset) else (gap_length - (pattern_offset - dash_length));
            const draw_length = @min(remaining_in_segment, remaining_in_pattern);
            
            if (is_dash and draw_length > 0) {
                const start_angle = arc_start_angle2 + (segment_pos / arc_length) * (arc_end_angle2 - arc_start_angle2);
                const end_angle = start_angle + (draw_length / arc_length) * (arc_end_angle2 - arc_start_angle2);
                self.render_backend.beginPath();
                self.render_backend.arc(arc_center_x2, arc_center_y2, r, start_angle, end_angle);
                self.render_backend.stroke(color, width);
            }
            
            segment_pos += draw_length;
            current_distance += draw_length;
            
            if (draw_length >= remaining_in_pattern) {
                is_dash = !is_dash;
            }
        }

        // 5. 下边（从右到左）
        const bottom_start_x = x + w - r;
        segment_pos = 0.0;
        while (segment_pos < bottom_length) {
            const remaining_in_segment = bottom_length - segment_pos;
            const pattern_offset = @mod(current_distance, dash_pattern_length);
            const remaining_in_pattern = if (is_dash) (dash_length - pattern_offset) else (gap_length - (pattern_offset - dash_length));
            const draw_length = @min(remaining_in_segment, remaining_in_pattern);
            
            if (is_dash and draw_length > 0) {
                const start_x = bottom_start_x - segment_pos;
                const end_x = start_x - draw_length;
                self.render_backend.beginPath();
                self.render_backend.moveTo(start_x, y + h);
                self.render_backend.lineTo(end_x, y + h);
                self.render_backend.stroke(color, width);
            }
            
            segment_pos += draw_length;
            current_distance += draw_length;
            
            if (draw_length >= remaining_in_pattern) {
                is_dash = !is_dash;
            }
        }

        // 6. 左下角圆弧（从90度到180度）
        const arc_center_x3 = x + r;
        const arc_center_y3 = y + h - r;
        const arc_start_angle3 = std.math.pi / 2.0;
        const arc_end_angle3 = std.math.pi;
        segment_pos = 0.0;
        while (segment_pos < arc_length) {
            const remaining_in_segment = arc_length - segment_pos;
            const pattern_offset = @mod(current_distance, dash_pattern_length);
            const remaining_in_pattern = if (is_dash) (dash_length - pattern_offset) else (gap_length - (pattern_offset - dash_length));
            const draw_length = @min(remaining_in_segment, remaining_in_pattern);
            
            if (is_dash and draw_length > 0) {
                const start_angle = arc_start_angle3 + (segment_pos / arc_length) * (arc_end_angle3 - arc_start_angle3);
                const end_angle = start_angle + (draw_length / arc_length) * (arc_end_angle3 - arc_start_angle3);
                self.render_backend.beginPath();
                self.render_backend.arc(arc_center_x3, arc_center_y3, r, start_angle, end_angle);
                self.render_backend.stroke(color, width);
            }
            
            segment_pos += draw_length;
            current_distance += draw_length;
            
            if (draw_length >= remaining_in_pattern) {
                is_dash = !is_dash;
            }
        }

        // 7. 左边（从下到上）
        const left_start_y = y + h - r;
        segment_pos = 0.0;
        while (segment_pos < left_length) {
            const remaining_in_segment = left_length - segment_pos;
            const pattern_offset = @mod(current_distance, dash_pattern_length);
            const remaining_in_pattern = if (is_dash) (dash_length - pattern_offset) else (gap_length - (pattern_offset - dash_length));
            const draw_length = @min(remaining_in_segment, remaining_in_pattern);
            
            if (is_dash and draw_length > 0) {
                const start_y = left_start_y - segment_pos;
                const end_y = start_y - draw_length;
                self.render_backend.beginPath();
                self.render_backend.moveTo(x, start_y);
                self.render_backend.lineTo(x, end_y);
                self.render_backend.stroke(color, width);
            }
            
            segment_pos += draw_length;
            current_distance += draw_length;
            
            if (draw_length >= remaining_in_pattern) {
                is_dash = !is_dash;
            }
        }

        // 8. 左上角圆弧（从180度到270度）
        const arc_center_x4 = x + r;
        const arc_center_y4 = y + r;
        const arc_start_angle4 = std.math.pi;
        const arc_end_angle4 = 3.0 * std.math.pi / 2.0;
        segment_pos = 0.0;
        while (segment_pos < arc_length) {
            const remaining_in_segment = arc_length - segment_pos;
            const pattern_offset = @mod(current_distance, dash_pattern_length);
            const remaining_in_pattern = if (is_dash) (dash_length - pattern_offset) else (gap_length - (pattern_offset - dash_length));
            const draw_length = @min(remaining_in_segment, remaining_in_pattern);
            
            if (is_dash and draw_length > 0) {
                const start_angle = arc_start_angle4 + (segment_pos / arc_length) * (arc_end_angle4 - arc_start_angle4);
                const end_angle = start_angle + (draw_length / arc_length) * (arc_end_angle4 - arc_start_angle4);
                self.render_backend.beginPath();
                self.render_backend.arc(arc_center_x4, arc_center_y4, r, start_angle, end_angle);
                self.render_backend.stroke(color, width);
            }
            
            segment_pos += draw_length;
            current_distance += draw_length;
            
            if (draw_length >= remaining_in_pattern) {
                is_dash = !is_dash;
            }
        }
    }

    /// 渲染box-shadow阴影
    /// 支持模糊效果（使用简化的Box Blur算法）
    /// CSS规范说明：
    /// - blur_radius: 模糊半径，影响阴影的模糊程度
    /// - 如果blur_radius为0，不应用模糊
    /// - 如果blur_radius > 0，应用模糊效果
    /// 
    /// 实现思路：
    /// 1. 如果blur_radius很小（< 1px），不应用模糊，直接绘制
    /// 2. 如果blur_radius较大，使用Box Blur算法（高斯模糊的简化版本）
    /// 3. 对于内阴影，模糊效果在元素内部应用
    /// 4. 对于外阴影，模糊效果在元素外部应用
    /// 
    /// TODO: 完整实现需要：
    /// 1. 实现真正的高斯模糊算法（当前使用Box Blur作为近似）
    /// 2. 优化性能（使用可分离的高斯模糊，分两步：水平模糊+垂直模糊）
    /// 3. 支持更大的blur_radius值（当前实现可能对很大的blur_radius性能不佳）
    fn renderBoxShadow(self: *Renderer, layout_box: *box.LayoutBox, shadow: box.BoxShadow, rect: backend.Rect) !void {
        // 创建阴影颜色
        const shadow_color = backend.Color.init(shadow.color_r, shadow.color_g, shadow.color_b, shadow.color_a);

        if (shadow.inset) {
            // 内阴影（inset）：在元素内部绘制阴影
            // CSS规范说明：
            // - 内阴影绘制在元素内部，而不是外部
            // - offset_x和offset_y影响阴影的位置（向内偏移）
            // - spread_radius影响阴影的尺寸（向内收缩）
            // 
            // 实现思路：
            // 1. 计算内阴影的位置和尺寸（考虑offset和spread）
            // 2. 使用clip确保阴影只在元素内部显示
            // 3. 绘制阴影矩形（或圆角矩形）
            
            // 保存当前状态（用于clip）
            self.render_backend.save();
            defer self.render_backend.restore();
            
            // 设置裁剪区域为元素边界（确保阴影只在元素内部）
            self.render_backend.clip(rect);
            
            // 计算内阴影的位置和尺寸
            // CSS规范说明：
            // - 内阴影从元素边缘向内绘制
            // - offset_x和offset_y影响阴影的偏移方向（正值向右下，负值向左上）
            // - spread_radius影响阴影的扩散（正值向内收缩，负值向外扩展）
            // 
            // 内阴影的位置：从元素边缘向内偏移
            // 内阴影的尺寸：元素尺寸减去两倍的spread（向内收缩）
            // 注意：offset只影响阴影的位置，不影响尺寸
            const inset_x = rect.x + shadow.offset_x + shadow.spread_radius;
            const inset_y = rect.y + shadow.offset_y + shadow.spread_radius;
            // 内阴影的宽度和高度：元素尺寸减去两倍的spread（向内收缩）
            // 注意：这里使用绝对值，因为spread可能是负值
            const inset_width = rect.width - @abs(shadow.spread_radius) * 2.0;
            const inset_height = rect.height - @abs(shadow.spread_radius) * 2.0;
            
            // 确保尺寸不为负
            const final_width = @max(0.0, inset_width);
            const final_height = @max(0.0, inset_height);
            
            const inset_rect = backend.Rect.init(inset_x, inset_y, final_width, final_height);
            
            // 简化实现：如果border-radius存在，使用圆角矩形；否则使用普通矩形
            // 注意：内阴影的圆角半径应该小于元素的圆角半径
            if (layout_box.box_model.border_radius) |radius| {
                // 内阴影的圆角半径应该小于元素的圆角半径
                // 简化实现：使用相同的圆角半径（减去spread_radius）
                const inset_radius = @max(0.0, radius - shadow.spread_radius);
                if (inset_radius > 0.5) {
                    // 绘制圆角内阴影
                    self.drawRoundedRectPath(inset_rect, inset_radius);
                    self.render_backend.fill(shadow_color);
                } else {
                    // 圆角半径太小，使用普通矩形
                    self.render_backend.fillRect(inset_rect, shadow_color);
                }
            } else {
                // 绘制普通矩形内阴影
                self.render_backend.fillRect(inset_rect, shadow_color);
            }
        } else {
            // 外阴影（outset）：在元素外部绘制阴影
            // 计算阴影矩形的位置和尺寸（考虑blur_radius的扩展）
            // CSS规范说明：blur_radius会影响阴影的尺寸，阴影应该向外扩展blur_radius的距离
            const blur_expansion = shadow.blur_radius;
            const shadow_x = rect.x + shadow.offset_x - shadow.spread_radius - blur_expansion;
            const shadow_y = rect.y + shadow.offset_y - shadow.spread_radius - blur_expansion;
            const shadow_width = rect.width + shadow.spread_radius * 2.0 + blur_expansion * 2.0;
            const shadow_height = rect.height + shadow.spread_radius * 2.0 + blur_expansion * 2.0;

            const shadow_rect = backend.Rect.init(shadow_x, shadow_y, shadow_width, shadow_height);

            // 检查是否需要应用模糊效果
            if (shadow.blur_radius < 1.0) {
                // blur_radius很小，不应用模糊，直接绘制
                if (layout_box.box_model.border_radius) |radius| {
                    // 绘制圆角阴影
                    self.drawRoundedRectPath(shadow_rect, radius);
                    self.render_backend.fill(shadow_color);
                } else {
                    // 绘制普通矩形阴影
                    self.render_backend.fillRect(shadow_rect, shadow_color);
                }
            } else {
                // blur_radius较大，需要应用模糊效果
                // TODO: 完整实现需要：
                // 1. 创建一个临时图像缓冲区
                // 2. 在缓冲区中绘制阴影形状（矩形或圆角矩形）
                // 3. 对缓冲区应用高斯模糊算法（或Box Blur作为近似）
                // 4. 将模糊后的结果混合到主画布上
                // 
                // 当前简化实现：使用多层绘制来近似模糊效果
                // 注意：这不是真正的高斯模糊，只是一个简化的近似
                const blur_radius_int = @as(u32, @intFromFloat(@ceil(shadow.blur_radius)));
                const blur_layers = @min(blur_radius_int, 10); // 限制层数，避免性能问题
                
                // 使用多层绘制，每层透明度递减，位置稍微偏移，来近似模糊效果
                var layer: u32 = 0;
                while (layer < blur_layers) : (layer += 1) {
                    const layer_alpha = @as(f32, @floatFromInt(shadow.color_a)) * (1.0 - @as(f32, @floatFromInt(layer)) / @as(f32, @floatFromInt(blur_layers))) * 0.3; // 每层透明度递减
                    const layer_offset = @as(f32, @floatFromInt(layer)) * 0.5; // 每层位置稍微偏移
                    
                    const layer_shadow_x = shadow_x - layer_offset;
                    const layer_shadow_y = shadow_y - layer_offset;
                    const layer_shadow_width = shadow_width + layer_offset * 2.0;
                    const layer_shadow_height = shadow_height + layer_offset * 2.0;
                    const layer_shadow_rect = backend.Rect.init(layer_shadow_x, layer_shadow_y, layer_shadow_width, layer_shadow_height);
                    
                    const layer_color = backend.Color.init(shadow.color_r, shadow.color_g, shadow.color_b, @as(u8, @intFromFloat(layer_alpha)));
                    
                    if (layout_box.box_model.border_radius) |radius| {
                        // 绘制圆角阴影层
                        self.drawRoundedRectPath(layer_shadow_rect, radius);
                        self.render_backend.fill(layer_color);
                    } else {
                        // 绘制普通矩形阴影层
                        self.render_backend.fillRect(layer_shadow_rect, layer_color);
                    }
                }
            }
        }
    }

    /// 渲染背景
    /// 支持背景颜色、渐变背景（linear-gradient、radial-gradient）和背景图片（background-image: url(...)）
    fn renderBackground(self: *Renderer, layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, rect: backend.Rect) !void {
        // 首先检查是否有渐变背景（background-image属性中的linear-gradient或radial-gradient）
        if (self.hasGradientBackground(computed_style)) {
            // 渲染渐变背景
            try self.renderGradientBackground(layout_box, computed_style, rect);
            return;
        }

        // 然后检查是否有背景图片（background-image: url(...)）
        if (self.hasImageBackground(computed_style)) {
            // 渲染背景图片
            try self.renderImageBackground(layout_box, computed_style, rect);
            // 注意：背景图片渲染后，可能还需要渲染背景颜色（如果设置了background-color）
            // CSS规范：背景图片在背景颜色上方，但如果图片有透明区域，背景颜色会显示
        }

        // 最后渲染背景颜色（如果设置了background-color）
        // 注意：如果已经有背景图片，背景颜色会作为fallback或填充透明区域
        const bg_color = self.getBackgroundColor(computed_style);

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

        if (border_color) |color| {
            if (border_width > 0) {
                // 检查边框样式
                const style = border_style orelse "solid";
                const is_dashed = std.mem.eql(u8, style, "dashed");
                
                // 检查是否有圆角
                if (layout_box.box_model.border_radius) |radius| {
                    // 绘制圆角边框
                    if (is_dashed) {
                        // 绘制圆角虚线边框
                        try self.renderDashedRoundedRect(rect, radius, color, border_width);
                    } else {
                        // 绘制圆角实线边框
                        self.drawRoundedRectPath(rect, radius);
                        self.render_backend.stroke(color, border_width);
                    }
                } else {
                    // 绘制矩形边框
                    if (is_dashed) {
                        // 绘制虚线边框
                        self.render_backend.strokeDashedRect(rect, color, border_width);
                    } else {
                        // 绘制实线边框
                        self.render_backend.strokeRect(rect, color, border_width);
                    }
                }
            }
        }
    }

    /// 渲染内容（文本）
    fn renderContent(self: *Renderer, layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, rect: backend.Rect) !void {
        // 如果节点是文本节点，渲染文本
        if (layout_box.node.node_type == .text) {
            // 从Node.data中获取文本内容
            const text_content = layout_box.node.data.text;


            // 如果文本内容为空，不渲染
            if (text_content.len == 0) {
                return;
            }

            // 应用white-space处理（空白字符处理）
            // 获取父元素的white-space属性（文本节点继承父元素的处理方式）
            const white_space = if (layout_box.parent) |parent| parent.white_space else .normal;
            var processed_text = text_content;
            var processed_buffer: [2048]u8 = undefined;
            const processed_len = self.processWhiteSpace(text_content, white_space, &processed_buffer);
            if (processed_len > 0) {
                processed_text = processed_buffer[0..processed_len];
            }

            // 应用text-transform转换
            // 获取父元素的text-transform属性（文本节点继承父元素的转换）
            const text_transform = if (layout_box.parent) |parent| parent.text_transform else .none;
            var transformed_text = processed_text;
            var transformed_buffer: [2048]u8 = undefined;
            if (text_transform != .none) {
                // 应用文本转换
                const transformed_len = self.applyTextTransform(processed_text, text_transform, &transformed_buffer);
                if (transformed_len > 0) {
                    transformed_text = transformed_buffer[0..transformed_len];
                }
            }

            // 检查是否只包含空白字符（使用转换后的文本）
            var is_whitespace_only = true;
            for (transformed_text) |c| {
                if (c != ' ' and c != '\n' and c != '\r' and c != '\t') {
                    is_whitespace_only = false;
                    break;
                }
            }
            if (is_whitespace_only) {
                return;
            }

            // 文本节点应该使用父元素的样式
            // 文本节点本身没有样式，应该继承父元素的所有样式属性（如color、font-size等）
            // 优化：直接使用父元素的computed_style（避免重复计算）
            var text_computed_style = computed_style;
            if (layout_box.parent) |parent| {
                // 优先使用父元素的已计算样式（避免重复计算）
                if (parent.computed_style) |*parent_cs| {
                    // 检查当前样式是否有color属性（文本节点最重要的属性）
                    // 如果没有color属性，使用父元素的样式
                    // 文本节点应该总是继承父元素的样式，特别是color属性
                    if (computed_style.getProperty("color") == null) {
                        text_computed_style = parent_cs;
                    }
                } else {
                    // 向后兼容：如果父元素样式未计算，则重新计算
                    // 复用Renderer的cascade_engine实例，避免重复创建
                    var parent_computed_style = try self.cascade_engine.computeStyle(parent.node, self.stylesheets);
                    defer parent_computed_style.deinit();
                    
                    // 检查当前样式是否有color属性
                    if (computed_style.getProperty("color") == null) {
                        text_computed_style = &parent_computed_style;
                    }
                }
            }

            // 获取文本颜色和字体
            const text_color = self.getTextColor(text_computed_style);
            const font = self.getFont(text_computed_style);


            if (text_color) |color| {
                // 计算文本对齐后的x坐标
                var text_x = rect.x;
                var text_width: f32 = 0; // 缓存文本宽度，避免重复计算
                
                // 获取父元素的text-align属性（如果存在）
                if (layout_box.parent) |parent| {
                    // 计算文本宽度（使用准确的文本宽度计算）
                    // calculateTextWidth返回文本结束位置的x坐标，所以宽度 = 结束位置 - 起始位置
                    const text_end_x = try self.render_backend.calculateTextWidth(transformed_text, rect.x, font);
                    text_width = text_end_x - rect.x; // 缓存文本宽度
                    
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
                            // 两端对齐：调整单词之间的间距，使文本两端对齐
                            // 注意：对于单行文本，如果文本宽度小于容器宽度，才应用justify
                            // 如果文本宽度大于等于容器宽度，按左对齐处理（因为无法调整）
                            if (text_width < rect.width and text_width > 0) {
                                // 文本宽度小于容器宽度，可以应用justify
                                // 将在下面使用renderTextJustified函数处理
                                text_x = rect.x;
                            } else {
                                // 文本宽度大于等于容器宽度，按左对齐处理
                                text_x = rect.x;
                            }
                        },
                    }
                } else {
                    // 如果没有父元素，也需要计算文本宽度（用于text-decoration）
                    const text_end_x = try self.render_backend.calculateTextWidth(transformed_text, rect.x, font);
                    text_width = text_end_x - rect.x; // 缓存文本宽度
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
                // 注意：ascent_ratio应该更大，以确保文本不会被遮挡
                // 对于大字体（如h1），使用更大的ascent_ratio
                // 调整：对于大字体，使用更小的偏移，让文本更靠近顶部
                const adjusted_ascent_ratio = if (font.size > 24.0) 0.85 else ascent_ratio;
                // 对于大字体，减少垂直居中的偏移，让文本更靠近顶部
                const vertical_offset = if (font.size > 24.0 and actual_line_height > font.size)
                    (actual_line_height - font.size) / 3.0  // 减少偏移，从/2改为/3
                else if (actual_line_height > font.size)
                    (actual_line_height - font.size) / 2.0
                else
                    0.0;
                const baseline_y = rect.y + vertical_offset + font.size * adjusted_ascent_ratio;
                // 获取letter-spacing（从父元素继承）
                const letter_spacing = if (layout_box.parent) |parent| parent.letter_spacing else null;
                
                // 获取word-wrap和word-break属性（从父元素继承）
                const word_wrap = if (layout_box.parent) |parent| parent.word_wrap else .normal;
                const word_break = if (layout_box.parent) |parent| parent.word_break else .normal;
                
                // 检查是否需要处理文本断行
                // 如果white-space是nowrap或pre，不处理断行
                const should_wrap = white_space != .nowrap and white_space != .pre;
                
                // 检查是否需要justify对齐
                const needs_justify = if (layout_box.parent) |parent| 
                    (parent.text_align == .justify and text_width < rect.width and text_width > 0)
                else 
                    false;
                
                if (should_wrap and rect.width > 0) {
                    // 处理文本断行（word-wrap和word-break）
                    // 如果使用justify，在renderTextWithWordWrap中处理
                    try self.renderTextWithWordWrap(transformed_text, text_x, baseline_y, font, color, letter_spacing, rect.width, word_wrap, word_break, actual_line_height, needs_justify);
                } else {
                    // 不处理断行，直接渲染整个文本
                    if (needs_justify) {
                        // 使用justify对齐渲染单行文本
                        try self.renderTextJustified(transformed_text, text_x, baseline_y, font, color, letter_spacing, rect.width);
                    } else {
                        // 普通渲染
                        self.render_backend.fillText(transformed_text, text_x, baseline_y, font, color, letter_spacing);
                    }
                }
                
                // 绘制文本装饰（text-decoration）
                // 获取父元素的text-decoration属性（文本节点继承父元素的装饰）
                const text_decoration = if (layout_box.parent) |parent| parent.text_decoration else .none;
                if (text_decoration != .none) {
                    // 使用缓存的文本宽度（避免重复计算）
                    // 注意：如果text-align不是left，text_width是基于rect.x计算的，但text-decoration应该基于text_x
                    // 对于text-align center/right，需要重新计算基于text_x的宽度
                    var decoration_text_width = text_width;
                    if (layout_box.parent) |parent| {
                        if (parent.text_align != .left) {
                            // text-align不是left时，需要基于text_x重新计算宽度
                            const text_end_x = try self.render_backend.calculateTextWidth(transformed_text, text_x, font);
                            decoration_text_width = text_end_x - text_x;
                        }
                    }
                    
                    // 计算装饰线的位置和宽度
                    const decoration_width = @max(1.0, font.size * 0.05); // 装饰线宽度约为字体大小的5%
                    
                    switch (text_decoration) {
                        .underline => {
                            // 下划线：在基线下方
                            const underline_y = baseline_y + font.size * 0.2; // 基线下方约20%字体大小
                            const decoration_rect = backend.Rect.init(text_x, underline_y, decoration_text_width, decoration_width);
                            self.render_backend.fillRect(decoration_rect, color);
                        },
                        .line_through => {
                            // 删除线：在文本中间
                            const strikethrough_y = baseline_y - font.size * 0.3; // 基线下方约30%字体大小（文本中间）
                            const decoration_rect = backend.Rect.init(text_x, strikethrough_y, decoration_text_width, decoration_width);
                            self.render_backend.fillRect(decoration_rect, color);
                        },
                        .overline => {
                            // 上划线：在文本上方
                            const overline_y = baseline_y - font.size * 0.7; // 基线下方约70%字体大小（文本上方）
                            const decoration_rect = backend.Rect.init(text_x, overline_y, decoration_text_width, decoration_width);
                            self.render_backend.fillRect(decoration_rect, color);
                        },
                        .none => {}, // 不会到达这里
                    }
                }
            } else {
            }
        } else {
        }
    }

    /// 检查是否有渐变背景
    /// 检查background-image属性是否包含linear-gradient或radial-gradient
    fn hasGradientBackground(self: *Renderer, computed_style: *const cascade.ComputedStyle) bool {
        _ = self;
        // 检查background-image属性
        if (computed_style.getProperty("background-image")) |decl| {
            // 检查是否是字符串值（渐变通常以字符串形式存储）
            if (decl.value == .keyword) {
                const value = decl.value.keyword;
                // 检查是否包含linear-gradient或radial-gradient
                if (std.mem.indexOf(u8, value, "linear-gradient") != null) {
                    return true;
                }
                if (std.mem.indexOf(u8, value, "radial-gradient") != null) {
                    return true;
                }
            }
        }
        return false;
    }

    /// 检查是否有背景图片
    /// 检查background-image属性是否包含url(...)
    fn hasImageBackground(self: *Renderer, computed_style: *const cascade.ComputedStyle) bool {
        _ = self;
        // 检查background-image属性
        if (computed_style.getProperty("background-image")) |decl| {
            // 检查是否是字符串值
            if (decl.value == .keyword) {
                const value = decl.value.keyword;
                // 检查是否包含url(，且不包含linear-gradient或radial-gradient（避免与渐变混淆）
                if (std.mem.indexOf(u8, value, "url(") != null) {
                    // 确保不是渐变
                    if (std.mem.indexOf(u8, value, "linear-gradient") == null and
                        std.mem.indexOf(u8, value, "radial-gradient") == null)
                    {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /// 渲染背景图片
    /// 支持background-image: url(...)语法
    /// CSS规范说明：
    /// - background-image: 可以指定一个或多个背景图片
    /// - background-position: 控制背景图片的位置
    /// - background-size: 控制背景图片的尺寸
    /// - background-repeat: 控制背景图片的重复方式
    /// 
    /// 实现思路：
    /// 1. 解析background-image中的url(...)语法，提取图片路径
    /// 2. 加载图片文件（支持PNG格式）
    /// 3. 根据background-position、background-size、background-repeat计算图片的绘制位置和尺寸
    /// 4. 调用drawImage渲染图片
    /// 
    /// TODO: 完整实现需要：
    /// 1. 实现PNG解码器（当前只有PNG编码器，需要添加解码器）
    /// 2. 支持其他图片格式（JPEG、GIF、WebP等）
    /// 3. 支持background-position、background-size、background-repeat属性
    /// 4. 支持多个背景图片（用逗号分隔）
    /// 5. 图片缓存机制（避免重复加载相同图片）
    fn renderImageBackground(self: *Renderer, layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, rect: backend.Rect) !void {
        // 获取background-image属性值
        const image_value = if (computed_style.getProperty("background-image")) |decl|
            if (decl.value == .keyword) decl.value.keyword else return
        else
            return;

        // 解析url(...)语法
        // 格式：url("path/to/image.png") 或 url('path/to/image.png') 或 url(path/to/image.png)
        const url_start = std.mem.indexOf(u8, image_value, "url(") orelse return;
        const url_content_start = url_start + 4; // "url("的长度
        if (url_content_start >= image_value.len) return;

        // 查找url的结束位置（查找匹配的右括号）
        var url_end: ?usize = null;
        var paren_count: u32 = 1;
        var i = url_content_start;
        while (i < image_value.len) : (i += 1) {
            if (image_value[i] == '(') {
                paren_count += 1;
            } else if (image_value[i] == ')') {
                paren_count -= 1;
                if (paren_count == 0) {
                    url_end = i;
                    break;
                }
            }
        }

        const url_content_end = url_end orelse return;
        var url_content = std.mem.trim(u8, image_value[url_content_start..url_content_end], " \t\n\r");

        // 移除引号（如果有）
        if (url_content.len >= 2) {
            if ((url_content[0] == '"' and url_content[url_content.len - 1] == '"') or
                (url_content[0] == '\'' and url_content[url_content.len - 1] == '\''))
            {
                url_content = url_content[1..url_content.len - 1];
            }
        }

        // TODO: 加载图片文件
        // 当前简化实现：只解析URL，不实际加载图片
        // 完整实现需要：
        // 1. 解析相对路径（相对于HTML文件位置）
        // 2. 加载图片文件
        // 3. 解码PNG格式（需要实现PNG解码器）
        // 4. 创建backend.Image对象
        // 5. 调用render_backend.drawImage渲染图片
        
        // 简化实现：如果检测到背景图片，使用占位符颜色（半透明灰色）表示
        // 这样可以验证背景图片检测逻辑是否正确
        const placeholder_color = backend.Color.init(200, 200, 200, 128); // 半透明灰色
        if (layout_box.box_model.border_radius) |radius| {
            self.drawRoundedRectPath(rect, radius);
            self.render_backend.fill(placeholder_color);
        } else {
            self.render_backend.fillRect(rect, placeholder_color);
        }
    }

    /// 颜色值（RGBA）
    const ColorValue = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    };

    /// 渐变颜色停止点
    const GradientColorStop = struct {
        color: ColorValue,
        position: ?f32, // 位置（0.0-1.0），如果为null表示自动分布
    };

    /// 线性渐变信息
    const LinearGradient = struct {
        direction: enum { to_top, to_right, to_bottom, to_left, angle }, // 渐变方向
        angle: f32, // 角度（当direction为angle时使用，单位：度）
        color_stops: std.ArrayList(GradientColorStop),
        allocator: std.mem.Allocator,

        fn deinit(self: *LinearGradient, allocator: std.mem.Allocator) void {
            self.color_stops.deinit(allocator);
        }
    };

    /// 径向渐变信息（简化实现）
    const RadialGradient = struct {
        color_stops: std.ArrayList(GradientColorStop),
        allocator: std.mem.Allocator,

        fn deinit(self: *RadialGradient, allocator: std.mem.Allocator) void {
            self.color_stops.deinit(allocator);
        }
    };

    /// 渲染渐变背景
    /// 支持linear-gradient和radial-gradient
    /// CSS规范说明：
    /// - linear-gradient: 线性渐变，从起点到终点按方向渐变
    /// - radial-gradient: 径向渐变，从中心点向外渐变
    /// 
    /// 实现思路：
    /// 1. 解析渐变语法（方向、颜色停止点）
    /// 2. 根据渐变类型选择渲染算法
    /// 3. 逐像素计算颜色值并绘制
    /// 
    /// TODO: 完整实现需要：
    /// 1. 支持更多渐变方向（角度、关键字如to top、to right等）
    /// 2. 支持颜色停止点的位置（百分比、长度值）
    /// 3. 支持radial-gradient（当前只实现linear-gradient）
    /// 4. 优化性能（使用更高效的算法，避免逐像素计算）
    fn renderGradientBackground(self: *Renderer, layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, rect: backend.Rect) !void {
        // 获取background-image属性值
        const gradient_value = if (computed_style.getProperty("background-image")) |decl|
            if (decl.value == .keyword) decl.value.keyword else return
        else
            return;

        // 解析渐变类型和参数
        if (std.mem.indexOf(u8, gradient_value, "linear-gradient") != null) {
            // 解析线性渐变
            if (try self.parseLinearGradient(gradient_value)) |gradient| {
                var mutable_gradient = gradient;
                defer mutable_gradient.deinit(self.allocator);
                try self.renderLinearGradient(layout_box, &mutable_gradient, rect);
            }
        } else if (std.mem.indexOf(u8, gradient_value, "radial-gradient") != null) {
            // TODO: 实现radial-gradient
            // 当前简化实现：如果检测到radial-gradient，使用第一个颜色作为背景色
            if (try self.parseRadialGradient(gradient_value)) |gradient| {
                var mutable_gradient = gradient;
                defer mutable_gradient.deinit(self.allocator);
                // 简化实现：使用第一个颜色作为背景色
                if (mutable_gradient.color_stops.items.len > 0) {
                    const first_color = mutable_gradient.color_stops.items[0].color;
                    const bg_color = backend.Color.rgb(first_color.r, first_color.g, first_color.b);
                    if (layout_box.box_model.border_radius) |radius| {
                        self.drawRoundedRectPath(rect, radius);
                        self.render_backend.fill(bg_color);
                    } else {
                        self.render_backend.fillRect(rect, bg_color);
                    }
                }
            }
        }
    }

    /// 解析linear-gradient语法
    /// 格式：linear-gradient([direction], color-stop1, color-stop2, ...)
    /// 例如：linear-gradient(to right, #ff0000, #0000ff)
    ///      linear-gradient(90deg, #ff0000, #0000ff)
    ///      linear-gradient(#ff0000, #0000ff) // 默认to bottom
    fn parseLinearGradient(self: *Renderer, value: []const u8) !?LinearGradient {
        // 移除linear-gradient(和)
        const start = std.mem.indexOf(u8, value, "(") orelse return null;
        const end = std.mem.lastIndexOf(u8, value, ")") orelse return null;
        const content = std.mem.trim(u8, value[start + 1..end], " \t\n\r");

        var gradient = LinearGradient{
            .direction = .to_bottom, // 默认方向
            .angle = 0.0,
            .color_stops = std.ArrayList(GradientColorStop){},
            .allocator = self.allocator,
        };
        errdefer gradient.color_stops.deinit(self.allocator);

        // 解析参数（按逗号分割）
        var parts = std.mem.splitSequence(u8, content, ",");
        var first_part = true;
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t\n\r");
            if (trimmed.len == 0) continue;

            if (first_part) {
                // 第一个参数可能是方向或第一个颜色
                first_part = false;
                // 检查是否是方向关键字
                if (std.mem.eql(u8, trimmed, "to top")) {
                    gradient.direction = .to_top;
                    continue;
                } else if (std.mem.eql(u8, trimmed, "to right")) {
                    gradient.direction = .to_right;
                    continue;
                } else if (std.mem.eql(u8, trimmed, "to bottom")) {
                    gradient.direction = .to_bottom;
                    continue;
                } else if (std.mem.eql(u8, trimmed, "to left")) {
                    gradient.direction = .to_left;
                    continue;
                } else if (std.mem.endsWith(u8, trimmed, "deg")) {
                    // 角度值，如"90deg"
                    const angle_str = trimmed[0..trimmed.len - 3];
                    if (std.fmt.parseFloat(f32, angle_str)) |angle| {
                        gradient.direction = .angle;
                        gradient.angle = angle;
                        continue;
                    } else |_| {
                        // 解析失败，当作颜色处理
                    }
                }
                // 如果不是方向，当作第一个颜色处理（继续到下面的颜色解析）
            }

            // 解析颜色停止点
            // 格式：color [position]
            // 例如：#ff0000 或 #ff0000 50%
            var color_stop = GradientColorStop{
                .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
                .position = null,
            };

            // 按空格分割，查找颜色和位置
            var color_parts = std.mem.splitSequence(u8, trimmed, " ");
            var color_str: ?[]const u8 = null;
            while (color_parts.next()) |color_part| {
                const color_trimmed = std.mem.trim(u8, color_part, " \t\n\r");
                if (color_trimmed.len == 0) continue;

                // 检查是否是位置值（百分比或长度）
                if (std.mem.endsWith(u8, color_trimmed, "%")) {
                    const percent_str = color_trimmed[0..color_trimmed.len - 1];
                    if (std.fmt.parseFloat(f32, percent_str)) |percent| {
                        color_stop.position = percent / 100.0;
                        continue;
                    } else |_| {
                        // 解析失败，继续处理
                    }
                }

                // 当作颜色处理
                if (color_str == null) {
                    color_str = color_trimmed;
                }
            }

            // 解析颜色（使用style_utils的parseColor，但它是私有的，所以我们需要自己实现一个简单的解析）
            if (color_str) |c_str| {
                if (self.parseColorValue(c_str)) |color| {
                    color_stop.color = color;
                    try gradient.color_stops.append(self.allocator, color_stop);
                }
            }
        }

        // 如果没有颜色停止点，返回null
        if (gradient.color_stops.items.len == 0) {
            gradient.color_stops.deinit(self.allocator);
            return null;
        }

        // 如果没有指定位置，自动分布
        var has_position = false;
        for (gradient.color_stops.items) |stop| {
            if (stop.position != null) {
                has_position = true;
                break;
            }
        }
        if (!has_position) {
            // 自动分布颜色停止点
            for (gradient.color_stops.items, 0..) |*stop, i| {
                stop.position = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(gradient.color_stops.items.len - 1));
            }
        }

        return gradient;
    }

    /// 解析radial-gradient语法（简化实现）
    /// 格式：radial-gradient([shape] [size] at [position], color-stop1, color-stop2, ...)
    /// 例如：radial-gradient(circle, #ff0000, #0000ff)
    fn parseRadialGradient(self: *Renderer, value: []const u8) !?RadialGradient {
        // 移除radial-gradient(和)
        const start = std.mem.indexOf(u8, value, "(") orelse return null;
        const end = std.mem.lastIndexOf(u8, value, ")") orelse return null;
        const content = std.mem.trim(u8, value[start + 1..end], " \t\n\r");

        var gradient = RadialGradient{
            .color_stops = std.ArrayList(GradientColorStop){},
            .allocator = self.allocator,
        };
        errdefer gradient.color_stops.deinit(self.allocator);

        // 解析参数（按逗号分割）
        var parts = std.mem.splitSequence(u8, content, ",");
        var first_part = true;
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t\n\r");
            if (trimmed.len == 0) continue;

            if (first_part) {
                // 第一个参数可能是形状或位置，暂时跳过
                first_part = false;
                // 简化实现：如果第一个参数是颜色，直接解析
                if (self.parseColorValue(trimmed)) |color| {
                    try gradient.color_stops.append(self.allocator, GradientColorStop{
                        .color = color,
                        .position = null,
                    });
                    continue;
                }
                // 否则跳过（可能是circle、ellipse等关键字）
                continue;
            }

            // 解析颜色停止点（简化实现，与linear-gradient类似）
            var color_stop = GradientColorStop{
                .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
                .position = null,
            };

            var color_parts = std.mem.splitSequence(u8, trimmed, " ");
            var color_str: ?[]const u8 = null;
            while (color_parts.next()) |color_part| {
                const color_trimmed = std.mem.trim(u8, color_part, " \t\n\r");
                if (color_trimmed.len == 0) continue;

                if (std.mem.endsWith(u8, color_trimmed, "%")) {
                    const percent_str = color_trimmed[0..color_trimmed.len - 1];
                    if (std.fmt.parseFloat(f32, percent_str)) |percent| {
                        color_stop.position = percent / 100.0;
                        continue;
                    } else |_| {
                        // 解析失败，继续处理
                    }
                }

                if (color_str == null) {
                    color_str = color_trimmed;
                }
            }

            if (color_str) |c_str| {
                if (self.parseColorValue(c_str)) |color| {
                    color_stop.color = color;
                    try gradient.color_stops.append(self.allocator, color_stop);
                }
            }
        }

        if (gradient.color_stops.items.len == 0) {
            gradient.color_stops.deinit(self.allocator);
            return null;
        }

        // 自动分布颜色停止点
        for (gradient.color_stops.items, 0..) |*stop, i| {
            if (stop.position == null) {
                stop.position = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(gradient.color_stops.items.len - 1));
            }
        }

        return gradient;
    }

    /// 解析颜色值（简化实现，支持#rgb和#rrggbb格式）
    fn parseColorValue(self: *Renderer, value: []const u8) ?ColorValue {
        _ = self;
        const trimmed = std.mem.trim(u8, value, " \t\n\r");
        if (trimmed.len == 0) return null;

        // 解析十六进制颜色 #rgb 或 #rrggbb
        if (trimmed[0] == '#') {
            const hex_str = trimmed[1..];
            if (hex_str.len == 3) {
                // #rgb格式
                const r_hex = hex_str[0..1];
                const g_hex = hex_str[1..2];
                const b_hex = hex_str[2..3];
                const r = std.fmt.parseInt(u8, r_hex, 16) catch return null;
                const g = std.fmt.parseInt(u8, g_hex, 16) catch return null;
                const b = std.fmt.parseInt(u8, b_hex, 16) catch return null;
                return .{
                    .r = r * 17, // 扩展3位到8位
                    .g = g * 17,
                    .b = b * 17,
                    .a = 255,
                };
            } else if (hex_str.len == 6) {
                // #rrggbb格式
                const r_hex = hex_str[0..2];
                const g_hex = hex_str[2..4];
                const b_hex = hex_str[4..6];
                const r = std.fmt.parseInt(u8, r_hex, 16) catch return null;
                const g = std.fmt.parseInt(u8, g_hex, 16) catch return null;
                const b = std.fmt.parseInt(u8, b_hex, 16) catch return null;
                return .{ .r = r, .g = g, .b = b, .a = 255 };
            }
        }

        return null;
    }

    /// 渲染线性渐变
    /// 根据渐变方向和颜色停止点，逐像素计算颜色并绘制
    fn renderLinearGradient(self: *Renderer, layout_box: *box.LayoutBox, gradient: *LinearGradient, rect: backend.Rect) !void {
        // 计算渐变方向向量
        var dir_x: f32 = 0.0;
        var dir_y: f32 = 0.0;
        switch (gradient.direction) {
            .to_top => {
                dir_x = 0.0;
                dir_y = -1.0;
            },
            .to_right => {
                dir_x = 1.0;
                dir_y = 0.0;
            },
            .to_bottom => {
                dir_x = 0.0;
                dir_y = 1.0;
            },
            .to_left => {
                dir_x = -1.0;
                dir_y = 0.0;
            },
            .angle => {
                // 角度转换为方向向量
                const angle_rad = gradient.angle * std.math.pi / 180.0;
                dir_x = @cos(angle_rad);
                dir_y = @sin(angle_rad);
            },
        }

        // 计算渐变长度（沿方向向量的距离）
        const gradient_length = @abs(dir_x * rect.width) + @abs(dir_y * rect.height);

        // 检查是否有圆角
        const has_radius = layout_box.box_model.border_radius != null;
        const radius = if (has_radius) layout_box.box_model.border_radius.? else 0.0;

        // 逐像素绘制渐变
        // 优化：使用更粗的步长（每2-3像素）以提高性能
        const step = 2.0;
        var y = rect.y;
        while (y < rect.y + rect.height) : (y += step) {
            var x = rect.x;
            while (x < rect.x + rect.width) : (x += step) {
                // 计算当前像素在渐变方向上的位置（0.0-1.0）
                const center_x = rect.x + rect.width / 2.0;
                const center_y = rect.y + rect.height / 2.0;
                const offset_x = x - center_x;
                const offset_y = y - center_y;
                const dot_product = offset_x * dir_x + offset_y * dir_y;
                const normalized_pos = (dot_product / gradient_length) + 0.5; // 归一化到0.0-1.0

                // 根据位置计算颜色（在颜色停止点之间插值）
                const color = self.interpolateGradientColor(gradient.color_stops.items, normalized_pos);

                // 绘制像素（考虑圆角）
                const pixel_rect = backend.Rect.init(x, y, step, step);
                self.render_backend.fillRect(pixel_rect, color);
            }
        }

        // 如果有圆角，使用路径绘制来确保圆角正确
        if (has_radius) {
            // 重新绘制圆角矩形，使用渐变颜色（简化实现：使用平均颜色）
            const avg_color = if (gradient.color_stops.items.len > 0)
                backend.Color.rgb(
                    gradient.color_stops.items[0].color.r,
                    gradient.color_stops.items[0].color.g,
                    gradient.color_stops.items[0].color.b,
                )
            else
                backend.Color.rgb(255, 255, 255);
            self.drawRoundedRectPath(rect, radius);
            self.render_backend.fill(avg_color);
        }
    }

    /// 在颜色停止点之间插值计算颜色
    fn interpolateGradientColor(self: *Renderer, color_stops: []const GradientColorStop, position: f32) backend.Color {
        _ = self;
        // 限制position在0.0-1.0范围内
        const clamped_pos = @max(0.0, @min(1.0, position));

        // 找到包含position的两个颜色停止点
        var prev_stop: ?*const GradientColorStop = null;
        var next_stop: ?*const GradientColorStop = null;

        for (color_stops) |stop| {
            const stop_pos = stop.position orelse 0.0;
            if (stop_pos <= clamped_pos) {
                prev_stop = &stop;
            } else {
                next_stop = &stop;
                break;
            }
        }

        // 如果没有找到前一个停止点，使用第一个
        if (prev_stop == null and color_stops.len > 0) {
            prev_stop = &color_stops[0];
        }

        // 如果没有找到下一个停止点，使用最后一个
        if (next_stop == null and color_stops.len > 0) {
            next_stop = &color_stops[color_stops.len - 1];
        }

        // 如果只有一个停止点，直接返回
        if (prev_stop != null and next_stop != null and prev_stop == next_stop) {
            const stop = prev_stop.?;
            return backend.Color.rgb(stop.color.r, stop.color.g, stop.color.b);
        }

        // 在两个停止点之间插值
        if (prev_stop != null and next_stop != null) {
            const prev = prev_stop.?;
            const next = next_stop.?;
            const prev_pos = prev.position orelse 0.0;
            const next_pos = next.position orelse 1.0;

            // 计算插值因子
            const range = next_pos - prev_pos;
            const t = if (range > 0.0001) (clamped_pos - prev_pos) / range else 0.0;

            // 线性插值RGB值
            const r = @as(u8, @intFromFloat(@as(f32, @floatFromInt(prev.color.r)) * (1.0 - t) + @as(f32, @floatFromInt(next.color.r)) * t));
            const g = @as(u8, @intFromFloat(@as(f32, @floatFromInt(prev.color.g)) * (1.0 - t) + @as(f32, @floatFromInt(next.color.g)) * t));
            const b = @as(u8, @intFromFloat(@as(f32, @floatFromInt(prev.color.b)) * (1.0 - t) + @as(f32, @floatFromInt(next.color.b)) * t));

            return backend.Color.rgb(r, g, b);
        }

        // 默认返回白色
        return backend.Color.rgb(255, 255, 255);
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
        // 如果没有设置border-color，尝试从border简写属性中提取颜色
        // 先检查computed_style中是否有border属性
        if (computed_style.getProperty("border")) |decl| {
            if (decl.value == .keyword) {
                const border_value = decl.value.keyword;
                if (self.parseBorderShorthand(border_value)) |border_info| {
                    if (border_info.color) |color| {
                        return backend.Color.rgb(color.r, color.g, color.b);
                    } else {
                    }
                } else {
                }
            }
        }
        // 也尝试使用style_utils.getPropertyKeyword（兼容性检查）
        if (style_utils.getPropertyKeyword(computed_style, "border")) |border_value| {
            if (self.parseBorderShorthand(border_value)) |border_info| {
                if (border_info.color) |color| {
                    return backend.Color.rgb(color.r, color.g, color.b);
                }
            }
        } else {
        }
        // 如果没有设置border-color，检查是否有border-width
        // 如果有border-width但没有color，返回默认黑色
        const border_width = self.getBorderWidth(computed_style);
        if (border_width > 0) {
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
            return width;
        }
        // 如果没有设置border-width，尝试从border简写属性中提取宽度
        if (style_utils.getPropertyKeyword(computed_style, "border")) |border_value| {
            if (self.parseBorderShorthand(border_value)) |border_info| {
                if (border_info.width) |width| {
                    return width;
                } else {
                }
            } else {
            }
        } else {
        }
        // 如果没有设置border-width，检查border-top-width等单独属性
        // 简化：只检查border-top-width
        const border_top_context = style_utils.createUnitContext(containing_width);
        if (style_utils.getPropertyLength(computed_style, "border-top-width", border_top_context)) |width| {
            return width;
        }
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

            // 检查是否是颜色关键字（red, blue, green等）
            if (parseColorKeywordStatic(trimmed)) |c| {
                color = c;
                continue;
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

    /// 解析颜色关键字（静态辅助函数）
    fn parseColorKeywordStatic(keyword: []const u8) ?css_parser.Value.Color {
        const trimmed = std.mem.trim(u8, keyword, " \t\n\r");
        // 转换为小写进行比较（CSS颜色关键字不区分大小写）
        var lower_buffer: [32]u8 = undefined;
        if (trimmed.len > lower_buffer.len) return null;
        for (trimmed, 0..) |c, i| {
            lower_buffer[i] = std.ascii.toLower(c);
        }
        const lower_keyword = lower_buffer[0..trimmed.len];
        
        // 常见颜色关键字（CSS标准颜色）
        if (std.mem.eql(u8, lower_keyword, "red")) {
            return css_parser.Value.Color{ .r = 255, .g = 0, .b = 0 };
        } else if (std.mem.eql(u8, lower_keyword, "blue")) {
            return css_parser.Value.Color{ .r = 0, .g = 0, .b = 255 };
        } else if (std.mem.eql(u8, lower_keyword, "green")) {
            return css_parser.Value.Color{ .r = 0, .g = 128, .b = 0 };
        } else if (std.mem.eql(u8, lower_keyword, "yellow")) {
            return css_parser.Value.Color{ .r = 255, .g = 255, .b = 0 };
        } else if (std.mem.eql(u8, lower_keyword, "black")) {
            return css_parser.Value.Color{ .r = 0, .g = 0, .b = 0 };
        } else if (std.mem.eql(u8, lower_keyword, "white")) {
            return css_parser.Value.Color{ .r = 255, .g = 255, .b = 255 };
        } else if (std.mem.eql(u8, lower_keyword, "orange")) {
            return css_parser.Value.Color{ .r = 255, .g = 165, .b = 0 };
        } else if (std.mem.eql(u8, lower_keyword, "purple")) {
            return css_parser.Value.Color{ .r = 128, .g = 0, .b = 128 };
        } else if (std.mem.eql(u8, lower_keyword, "pink")) {
            return css_parser.Value.Color{ .r = 255, .g = 192, .b = 203 };
        } else if (std.mem.eql(u8, lower_keyword, "cyan")) {
            return css_parser.Value.Color{ .r = 0, .g = 255, .b = 255 };
        } else if (std.mem.eql(u8, lower_keyword, "magenta")) {
            return css_parser.Value.Color{ .r = 255, .g = 0, .b = 255 };
        } else if (std.mem.eql(u8, lower_keyword, "gray") or std.mem.eql(u8, lower_keyword, "grey")) {
            return css_parser.Value.Color{ .r = 128, .g = 128, .b = 128 };
        }
        // 更多颜色关键字可以在这里添加
        return null;
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
            // 调试日志：记录font-size（仅对h1等大字体元素）
            if (size > 24.0) {
                debugPrint("[FONT] font-size parsed: {d:.1}px\n", .{size});
            }
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

    /// 处理white-space属性
    /// 根据white-space属性处理空白字符（合并、保留、换行等）
    /// TODO: 完整实现需要：
    /// 1. 在布局阶段处理换行（nowrap、pre等）
    /// 2. 处理pre-wrap和pre-line的换行逻辑
    /// 3. 与word-wrap和word-break配合使用
    fn processWhiteSpace(self: *Renderer, text: []const u8, white_space: box.WhiteSpace, buffer: []u8) usize {
        _ = self; // 未使用
        var i: usize = 0;
        var j: usize = 0;
        var prev_was_whitespace = false;

        switch (white_space) {
            .normal => {
                // normal: 合并空白字符，将连续的空白字符合并为一个空格
                while (i < text.len and j < buffer.len) : (i += 1) {
                    const c = text[i];
                    if (c == ' ' or c == '\n' or c == '\r' or c == '\t') {
                        if (!prev_was_whitespace) {
                            buffer[j] = ' ';
                            j += 1;
                            prev_was_whitespace = true;
                        }
                    } else {
                        buffer[j] = c;
                        j += 1;
                        prev_was_whitespace = false;
                    }
                }
            },
            .nowrap => {
                // nowrap: 合并空白字符，但不换行（在渲染阶段只处理空白字符合并）
                // 换行逻辑在布局阶段处理
                while (i < text.len and j < buffer.len) : (i += 1) {
                    const c = text[i];
                    if (c == ' ' or c == '\n' or c == '\r' or c == '\t') {
                        if (!prev_was_whitespace) {
                            buffer[j] = ' ';
                            j += 1;
                            prev_was_whitespace = true;
                        }
                    } else {
                        buffer[j] = c;
                        j += 1;
                        prev_was_whitespace = false;
                    }
                }
            },
            .pre => {
                // pre: 保留所有空白字符（包括空格、换行符、制表符）
                const len = @min(text.len, buffer.len);
                @memcpy(buffer[0..len], text[0..len]);
                return len;
            },
            .pre_wrap => {
                // pre-wrap: 保留所有空白字符，但允许自动换行
                const len = @min(text.len, buffer.len);
                @memcpy(buffer[0..len], text[0..len]);
                return len;
            },
            .pre_line => {
                // pre-line: 保留换行符，但合并空格
                while (i < text.len and j < buffer.len) : (i += 1) {
                    const c = text[i];
                    if (c == '\n' or c == '\r') {
                        // 保留换行符
                        buffer[j] = '\n';
                        j += 1;
                        prev_was_whitespace = false;
                    } else if (c == ' ' or c == '\t') {
                        // 合并空格和制表符
                        if (!prev_was_whitespace) {
                            buffer[j] = ' ';
                            j += 1;
                            prev_was_whitespace = true;
                        }
                    } else {
                        buffer[j] = c;
                        j += 1;
                        prev_was_whitespace = false;
                    }
                }
            },
        }

        return j;
    }

    /// 渲染justify对齐的文本（调整单词之间的间距，使文本两端对齐）
    /// 将文本分割成单词，然后调整单词之间的间距，使文本宽度等于容器宽度
    /// 注意：只调整单词之间的间距，不调整字符之间的间距
    fn renderTextJustified(self: *Renderer, text: []const u8, start_x: f32, start_y: f32, font: backend.Font, color: backend.Color, letter_spacing: ?f32, container_width: f32) !void {
        if (text.len == 0) {
            return;
        }

        // 将文本分割成单词（以空格分隔）
        var words = std.ArrayList([]const u8){};
        defer words.deinit(self.allocator);
        
        var word_start: usize = 0;
        var i: usize = 0;
        while (i < text.len) {
            const c = text[i];
            if (c == ' ' or c == '\t') {
                // 找到单词边界
                if (word_start < i) {
                    // 提取单词（不包括空格）
                    try words.append(self.allocator, text[word_start..i]);
                }
                // 跳过空格
                while (i < text.len and (text[i] == ' ' or text[i] == '\t')) {
                    i += 1;
                }
                word_start = i;
            } else {
                i += 1;
            }
        }
        
        // 处理最后一个单词（如果存在）
        if (word_start < text.len) {
            try words.append(self.allocator, text[word_start..]);
        }

        // 如果只有一个单词或没有单词，按普通方式渲染
        if (words.items.len <= 1) {
            self.render_backend.fillText(text, start_x, start_y, font, color, letter_spacing);
            return;
        }

        // 计算所有单词的总宽度（不包括单词之间的空格）
        // 注意：需要逐个单词计算，因为每个单词的宽度可能不同
        var total_words_width: f32 = 0;
        var temp_x: f32 = start_x;
        for (words.items) |word| {
            const word_end_x = try self.render_backend.calculateTextWidth(word, temp_x, font);
            const word_width = word_end_x - temp_x;
            total_words_width += word_width;
            // 更新temp_x用于下一个单词的计算（加上一个空格宽度作为估算）
            temp_x = word_end_x + font.size * 0.3; // 估算空格宽度约为字体大小的30%
        }

        // 计算需要增加的间距
        // 间距 = (容器宽度 - 单词总宽度) / (单词数量 - 1)
        const extra_spacing = (container_width - total_words_width) / @as(f32, @floatFromInt(words.items.len - 1));

        // 逐个单词渲染，在单词之间添加额外的间距
        var current_x = start_x;
        for (words.items, 0..) |word, word_idx| {
            // 渲染单词
            self.render_backend.fillText(word, current_x, start_y, font, color, letter_spacing);
            
            // 计算单词宽度
            const word_end_x = try self.render_backend.calculateTextWidth(word, current_x, font);
            const word_width = word_end_x - current_x;
            
            // 移动到下一个单词的位置（单词宽度 + 额外间距）
            // 注意：最后一个单词后不需要添加额外间距
            if (word_idx < words.items.len - 1) {
                current_x += word_width + extra_spacing;
            }
        }
    }

    /// 渲染文本（处理word-wrap和word-break）
    /// 根据word-wrap和word-break属性将文本分割成多行并分别渲染
    /// TODO: 完整实现需要：
    /// 1. 更准确的单词边界检测
    /// 2. 处理CJK字符的断行规则（keep-all）
    /// 3. 与布局阶段配合，正确处理行高和垂直对齐
    fn renderTextWithWordWrap(self: *Renderer, text: []const u8, start_x: f32, start_y: f32, font: backend.Font, color: backend.Color, letter_spacing: ?f32, max_width: f32, word_wrap: box.WordWrap, word_break: box.WordBreak, line_height: f32, needs_justify: bool) !void {
        if (text.len == 0) {
            return;
        }

        var current_y = start_y;
        var line_start: usize = 0;
        var i: usize = 0;

        while (i < text.len) {
            // 找到当前行的结束位置
            var line_end: usize = i;
            var last_break_pos: usize = line_start; // 最后一个可断行位置（空格或单词边界）

            // 逐字符检查，找到适合的断行位置
            while (line_end < text.len) {
                const char_width = try self.render_backend.calculateTextWidth(text[line_start..line_end + 1], start_x, font);
                const line_width = char_width - start_x;

                if (line_width > max_width and line_end > line_start) {
                    // 当前行超出宽度，需要断行
                    break;
                }

                // 记录可断行位置（空格或根据word-break规则）
                const c = text[line_end];
                if (c == ' ' or c == '\t') {
                    last_break_pos = line_end + 1; // 空格后可以断行
                } else if (word_break == .break_all) {
                    // break-all: 任意字符都可以断行
                    last_break_pos = line_end + 1;
                } else if (word_wrap == .break_word) {
                    // break-word: 允许在任意位置断行（长单词可以断行）
                    last_break_pos = line_end + 1;
                }

                line_end += 1;
            }

            // 确定断行位置
            var break_pos: usize = line_end;
            if (line_end < text.len) {
                // 需要断行
                if (last_break_pos > line_start) {
                    // 使用最后一个可断行位置
                    break_pos = last_break_pos;
                } else {
                    // 没有找到可断行位置，强制在当前字符处断行
                    break_pos = if (line_end > line_start) line_end else line_end + 1;
                }
            }

            // 渲染当前行
            const line_text = text[line_start..break_pos];
            if (line_text.len > 0) {
                // 去除行尾空格（除了最后一行）
                var trimmed_line = line_text;
                const is_last_line = break_pos >= text.len;
                if (!is_last_line) {
                    // 不是最后一行，去除尾随空格
                    while (trimmed_line.len > 0 and (trimmed_line[trimmed_line.len - 1] == ' ' or trimmed_line[trimmed_line.len - 1] == '\t')) {
                        trimmed_line = trimmed_line[0..trimmed_line.len - 1];
                    }
                }

                if (trimmed_line.len > 0) {
                    // 如果使用justify对齐，且不是最后一行，应用justify对齐
                    if (needs_justify and !is_last_line) {
                        try self.renderTextJustified(trimmed_line, start_x, current_y, font, color, letter_spacing, max_width);
                    } else {
                        // 普通渲染
                        self.render_backend.fillText(trimmed_line, start_x, current_y, font, color, letter_spacing);
                    }
                }
            }

            // 移动到下一行
            if (break_pos < text.len) {
                current_y += line_height;
                line_start = break_pos;
                // 跳过行首空格
                while (line_start < text.len and (text[line_start] == ' ' or text[line_start] == '\t')) {
                    line_start += 1;
                }
                i = line_start;
            } else {
                // 已处理完所有文本
                break;
            }
        }
    }

    /// 应用text-transform转换
    /// 将文本根据text-transform属性进行大小写转换
    fn applyTextTransform(self: *Renderer, text: []const u8, transform: box.TextTransform, buffer: []u8) usize {
        _ = self; // 未使用
        if (transform == .none) {
            // 不转换，直接复制
            const len = @min(text.len, buffer.len);
            @memcpy(buffer[0..len], text[0..len]);
            return len;
        }

        var i: usize = 0;
        var j: usize = 0;
        var capitalize_next = true; // 用于capitalize模式

        while (i < text.len and j < buffer.len) : (i += 1) {
            const c = text[i];
            var transformed: u8 = c;

            switch (transform) {
                .none => transformed = c,
                .uppercase => {
                    // 转换为大写
                    if (c >= 'a' and c <= 'z') {
                        transformed = c - ('a' - 'A');
                    }
                },
                .lowercase => {
                    // 转换为小写
                    if (c >= 'A' and c <= 'Z') {
                        transformed = c + ('a' - 'A');
                    }
                },
                .capitalize => {
                    // 首字母大写
                    if (capitalize_next and c >= 'a' and c <= 'z') {
                        transformed = c - ('a' - 'A');
                        capitalize_next = false;
                    } else if (c >= 'A' and c <= 'Z') {
                        // 如果当前字符是大写但不是首字母，转换为小写
                        if (!capitalize_next) {
                            transformed = c + ('a' - 'A');
                        } else {
                            capitalize_next = false;
                        }
                    } else if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                        // 遇到空白字符，下一个字符应该大写
                        capitalize_next = true;
                    } else {
                        capitalize_next = false;
                    }
                },
            }

            buffer[j] = transformed;
            j += 1;
        }

        return j;
    }
};
