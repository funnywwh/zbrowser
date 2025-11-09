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
            },
            .display = .block,
            .position = .static,
            .position_top = null,
            .position_right = null,
            .position_bottom = null,
            .position_left = null,
            .float = .none,
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
