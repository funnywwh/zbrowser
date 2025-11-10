const std = @import("std");
const dom = @import("dom");

/// 矩形区域
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    /// 检查点是否在矩形内
    pub fn contains(self: Rect, point: Point) bool {
        return point.x >= self.x and point.x < self.x + self.width and
            point.y >= self.y and point.y < self.y + self.height;
    }

    /// 检查两个矩形是否相交
    pub fn intersects(self: Rect, other: Rect) bool {
        return !(self.x + self.width <= other.x or
            other.x + other.width <= self.x or
            self.y + self.height <= other.y or
            other.y + other.height <= self.y);
    }
};

/// 尺寸
pub const Size = struct {
    width: f32,
    height: f32,
};

/// 点坐标
pub const Point = struct {
    x: f32,
    y: f32,
};

/// 边距（上下左右）
pub const Edges = struct {
    top: f32,
    right: f32,
    bottom: f32,
    left: f32,

    /// 计算水平方向的总边距（left + right）
    pub fn horizontal(self: Edges) f32 {
        return self.left + self.right;
    }

    /// 计算垂直方向的总边距（top + bottom）
    pub fn vertical(self: Edges) f32 {
        return self.top + self.bottom;
    }
};

/// 盒模型类型
pub const BoxSizing = enum {
    content_box, // width/height 只包含内容
    border_box, // width/height 包含内容+padding+border
};

/// CSS盒模型
pub const BoxModel = struct {
    /// 内容区域（content box）
    content: Rect,

    /// 内边距（padding）
    padding: Edges,

    /// 边框（border）
    border: Edges,

    /// 外边距（margin）
    margin: Edges,

    /// 盒模型类型（content-box 或 border-box）
    box_sizing: BoxSizing,

    /// 边框圆角（border-radius属性）
    /// 如果为null，表示没有圆角（使用直角）
    border_radius: ?f32,

    /// 最小宽度（min-width属性）
    /// 如果为null，表示没有最小宽度限制
    min_width: ?f32,

    /// 最小高度（min-height属性）
    /// 如果为null，表示没有最小高度限制
    min_height: ?f32,

    /// 最大宽度（max-width属性）
    /// 如果为null，表示没有最大宽度限制
    max_width: ?f32,

    /// 最大高度（max-height属性）
    /// 如果为null，表示没有最大高度限制
    max_height: ?f32,

    /// 计算总尺寸（包含padding和border）
    pub fn totalSize(self: BoxModel) Size {
        const padding_horizontal = self.padding.horizontal();
        const padding_vertical = self.padding.vertical();
        const border_horizontal = self.border.horizontal();
        const border_vertical = self.border.vertical();

        return switch (self.box_sizing) {
            .content_box => .{
                .width = self.content.width + padding_horizontal + border_horizontal,
                .height = self.content.height + padding_vertical + border_vertical,
            },
            .border_box => .{
                .width = self.content.width,
                .height = self.content.height,
            },
        };
    }
};

/// 显示类型
pub const DisplayType = enum {
    none,
    block,
    inline_block,
    inline_element, // inline 是 Zig 关键字，使用 inline_element
    flex,
    inline_flex,
    grid,
    inline_grid,
    table,
    inline_table,
    table_row,
    table_cell,
};

/// 定位类型
pub const PositionType = enum {
    static,
    relative,
    absolute,
    fixed,
    sticky,
};

/// 浮动类型
pub const FloatType = enum {
    none,
    left,
    right,
};

/// 文本对齐类型
pub const TextAlign = enum {
    left,
    center,
    right,
    justify,
};

/// 文本装饰类型（text-decoration属性）
pub const TextDecoration = enum {
    none,
    underline,
    line_through,
    overline,
};

/// 垂直对齐方式（vertical-align属性）
pub const VerticalAlign = enum {
    baseline, // 基线对齐（默认）
    top, // 顶部对齐
    middle, // 中间对齐
    bottom, // 底部对齐
    sub, // 下标
    super, // 上标
    text_top, // 文本顶部
    text_bottom, // 文本底部
};

/// 空白字符处理方式（white-space属性）
pub const WhiteSpace = enum {
    normal, // 正常处理（合并空白字符，自动换行）
    nowrap, // 不换行（合并空白字符，但不换行）
    pre, // 保留空白字符（保留所有空白字符，不自动换行）
    pre_wrap, // 保留空白字符并换行（保留所有空白字符，自动换行）
    pre_line, // 保留换行符（合并空格，保留换行符，自动换行）
};

/// 单词换行方式（word-wrap/overflow-wrap属性）
pub const WordWrap = enum {
    normal, // 正常换行（只在正常单词边界换行）
    break_word, // 允许在任意位置换行（长单词可以断行）
};

/// 单词断行方式（word-break属性）
pub const WordBreak = enum {
    normal, // 正常断行（使用默认断行规则）
    break_all, // 允许在任意字符间断行
    keep_all, // 保持所有（CJK文本不断行，非CJK文本正常断行）
};

/// 文本大小写转换（text-transform属性）
pub const TextTransform = enum {
    none, // 不转换（默认）
    uppercase, // 转换为大写
    lowercase, // 转换为小写
    capitalize, // 首字母大写
};

/// 行高类型（line-height属性）
pub const LineHeight = union(enum) {
    /// 数字值（如1.5，表示字体大小的倍数）
    number: f32,
    /// 长度值（如20px）
    length: f32,
    /// 百分比值（如150%，表示字体大小的百分比）
    percent: f32,
    /// 默认值（normal，通常约为1.2）
    normal,
};

/// 溢出处理类型（overflow属性）
pub const Overflow = enum {
    visible, // 默认值，不裁剪溢出内容
    hidden,  // 隐藏溢出内容
    scroll,  // 显示滚动条（简化实现：等同于hidden）
    auto,    // 自动（简化实现：等同于hidden）
};

/// 布局框（每个DOM元素对应一个布局框）
pub const LayoutBox = struct {
    /// 对应的DOM节点
    node: *dom.Node,

    /// 盒模型
    box_model: BoxModel,

    /// 显示类型（block, inline, flex, grid等）
    display: DisplayType,

    /// 定位类型（static, relative, absolute, fixed, sticky）
    position: PositionType,

    /// 定位属性（top、right、bottom、left）
    /// 这些值从样式表中获取，用于relative、absolute、fixed、sticky定位
    /// 如果值为null，表示该属性未设置（使用auto）
    position_top: ?f32,
    position_right: ?f32,
    position_bottom: ?f32,
    position_left: ?f32,

    /// 浮动类型（none, left, right）
    float: FloatType,

    /// Grid行位置（grid-row属性）
    /// 如果值为null，表示使用自动放置
    grid_row_start: ?usize,
    grid_row_end: ?usize,

    /// Grid列位置（grid-column属性）
    /// 如果值为null，表示使用自动放置
    grid_column_start: ?usize,
    grid_column_end: ?usize,

    /// 文本对齐方式（text-align属性）
    text_align: TextAlign,

    /// 文本装饰方式（text-decoration属性）
    text_decoration: TextDecoration,

    /// 行高（line-height属性）
    line_height: LineHeight,

    /// 溢出处理（overflow属性）
    overflow: Overflow,

    /// 字符间距（letter-spacing属性）
    /// 如果为null，表示使用默认字符间距（0）
    letter_spacing: ?f32,

    /// 透明度（opacity属性）
    /// 范围：0.0（完全透明）到1.0（完全不透明）
    /// 默认值：1.0（完全不透明）
    opacity: f32,

    /// 堆叠顺序（z-index属性）
    /// 如果为null，表示使用默认堆叠顺序（auto）
    /// 只对positioned元素（relative、absolute、fixed、sticky）有效
    z_index: ?i32,

    /// 垂直对齐方式（vertical-align属性）
    /// 用于inline元素和table-cell元素的垂直对齐
    vertical_align: VerticalAlign,

    /// 空白字符处理方式（white-space属性）
    /// 控制空白字符（空格、换行符、制表符）的处理方式
    white_space: WhiteSpace,

    /// 单词换行方式（word-wrap/overflow-wrap属性）
    /// 控制长单词是否可以在任意位置换行
    word_wrap: WordWrap,

    /// 单词断行方式（word-break属性）
    /// 控制单词内部的断行规则
    word_break: WordBreak,

    /// 文本大小写转换（text-transform属性）
    /// 控制文本的大小写转换方式
    text_transform: TextTransform,

    /// 子布局框列表
    children: std.ArrayList(*LayoutBox),

    /// 父布局框
    parent: ?*LayoutBox,

    /// 布局上下文（BFC、IFC、FFC、GFC）- 暂时留空，后续实现
    formatting_context: ?*anyopaque,

    /// 是否已布局
    is_layouted: bool,

    allocator: std.mem.Allocator,

    /// 初始化布局框
    pub fn init(node: *dom.Node, allocator: std.mem.Allocator) LayoutBox {
        return .{
            .node = node,
            .box_model = BoxModel{
                .content = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 },
                .padding = Edges{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
                .border = Edges{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
                .margin = Edges{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
                .box_sizing = .content_box,
                .border_radius = null, // 默认无圆角
                .min_width = null, // 默认无最小宽度限制
                .min_height = null, // 默认无最小高度限制
                .max_width = null, // 默认无最大宽度限制
                .max_height = null, // 默认无最大高度限制
            },
            .display = .block,
            .position = .static,
            .position_top = null,
            .position_right = null,
            .position_bottom = null,
            .position_left = null,
            .float = .none,
            .grid_row_start = null,
            .grid_row_end = null,
            .grid_column_start = null,
            .grid_column_end = null,
            .text_align = .left, // 默认左对齐
            .text_decoration = .none, // 默认无装饰
            .line_height = .normal, // 默认行高
            .overflow = .visible, // 默认不裁剪
            .letter_spacing = null, // 默认无额外字符间距
            .opacity = 1.0, // 默认完全不透明
            .z_index = null, // 默认使用auto堆叠顺序
            .vertical_align = .baseline, // 默认基线对齐
            .white_space = .normal, // 默认正常处理空白字符
            .word_wrap = .normal, // 默认正常换行
            .word_break = .normal, // 默认正常断行
            .text_transform = .none, // 默认不转换
            .children = std.ArrayList(*LayoutBox){
                .items = &[_]*LayoutBox{},
                .capacity = 0,
            },
            .parent = null,
            .formatting_context = null,
            .is_layouted = false,
            .allocator = allocator,
        };
    }

    /// 清理布局框及其子节点
    /// 注意：此方法只清理ArrayList和递归清理子节点，不释放LayoutBox本身
    /// 如果LayoutBox是用allocator.create创建的，需要先调用deinit()，再调用allocator.destroy()
    ///
    /// 注意：此方法不会释放子节点的内存，只清理子节点的内容
    /// 如果子节点是用allocator.create创建的，需要在调用deinit()后手动调用allocator.destroy()
    pub fn deinit(self: *LayoutBox) void {
        // 注意：formatting_context的清理由创建它的布局函数负责（如layoutInline）
        // 这是因为formatting_context的类型是*anyopaque，需要根据display类型判断具体类型
        // 而box模块不能导入context模块（会造成循环依赖）
        // 如果需要在deinit中清理formatting_context，需要在调用deinit之前手动清理
        // 或者使用deinitAndDestroyChildren，它会递归清理所有子节点（包括formatting_context）
        // TODO: 实现formatting_context的自动清理机制（可能需要使用函数指针或vtable）

        // 清理所有子节点
        // 注意：只清理子节点的内容，不释放子节点的内存
        // 子节点的内存需要在调用deinit()后手动释放（如果子节点是用allocator.create创建的）
        const items_len = self.children.items.len;
        if (items_len > 0) {
            const children_slice = self.children.items;
            for (children_slice) |child| {
                child.deinit();
            }
        }

        // 最后清理ArrayList本身（只有在capacity > 0时才需要）
        const capacity = self.children.capacity;
        if (capacity > 0) {
            self.children.deinit(self.allocator);
        }
    }

    /// 清理布局框及其子节点，并释放所有子节点的内存
    /// 注意：此方法假设所有子节点都是用allocator.create创建的
    /// 如果LayoutBox是用allocator.create创建的，需要先调用deinitAndDestroyChildren()，再调用allocator.destroy()
    pub fn deinitAndDestroyChildren(self: *LayoutBox) void {
        // 先保存所有子节点的指针到独立数组，避免在清理过程中修改children导致迭代器失效
        // 注意：必须在children.deinit之前保存，因为deinit会释放items的内存
        const children_count = self.children.items.len;
        const allocator = self.allocator; // 保存allocator引用，避免在清理过程中失效
        const capacity = self.children.capacity;

        if (children_count > 0) {
            // 分配临时数组来保存子节点指针
            const children_to_destroy = allocator.alloc(*LayoutBox, children_count) catch {
                // 如果分配失败，直接清理children（不释放子节点）
                if (capacity > 0) {
                    self.children.deinit(allocator);
                }
                return;
            };

            // 复制子节点指针
            @memcpy(children_to_destroy, self.children.items);

            // 先清理ArrayList本身（释放items的内存）
            if (capacity > 0) {
                self.children.deinit(allocator);
            }

            // 然后递归清理并释放所有子节点
            for (children_to_destroy) |child| {
                child.deinitAndDestroyChildren();
                // 子节点是用allocator.create创建的，需要释放内存
                allocator.destroy(child);
            }

            // 释放临时数组
            allocator.free(children_to_destroy);
        } else {
            // 没有子节点，直接清理ArrayList
            if (capacity > 0) {
                self.children.deinit(allocator);
            }
        }
    }
};
