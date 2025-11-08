const std = @import("std");
const dom = @import("dom");
const box = @import("box");
const block = @import("block");
const inline_layout = @import("inline");
const flexbox = @import("flexbox");
const grid = @import("grid");
const cascade = @import("cascade");
const css_parser = @import("parser");

/// 布局引擎
/// 负责从DOM树构建布局树，并执行布局计算
pub const LayoutEngine = struct {
    allocator: std.mem.Allocator,

    /// 初始化布局引擎
    pub fn init(allocator: std.mem.Allocator) LayoutEngine {
        return .{ .allocator = allocator };
    }

    /// 构建布局树（从DOM树构建）
    /// TODO: 简化实现 - 当前不处理样式表，只构建基本的布局树结构
    /// 完整实现需要：
    /// 1. 处理样式表，计算每个元素的display、position、float等属性
    /// 2. 根据display类型设置LayoutBox的display属性
    /// 3. 计算盒模型（padding、border、margin）
    pub fn buildLayoutTree(self: *LayoutEngine, node: *dom.Node, stylesheets: []const css_parser.Stylesheet) !*box.LayoutBox {
        // TODO: 暂时不使用样式表的内容，后续实现样式计算
        // 但stylesheets参数需要在递归调用中传递

        // 创建布局框
        const layout_box = try self.allocator.create(box.LayoutBox);
        errdefer self.allocator.destroy(layout_box);

        // 直接初始化字段，而不是使用结构体赋值
        // 这样可以确保ArrayList字段被正确初始化
        layout_box.node = node;
        layout_box.box_model = box.BoxModel{
            .content = box.Rect{ .x = 0, .y = 0, .width = 0, .height = 0 },
            .padding = box.Edges{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
            .border = box.Edges{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
            .margin = box.Edges{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
            .box_sizing = .content_box,
        };
        layout_box.display = .block;
        layout_box.position = .static;
        layout_box.float = .none;
        layout_box.children = std.ArrayList(*box.LayoutBox){
            .items = &[_]*box.LayoutBox{},
            .capacity = 0,
        };
        layout_box.parent = null;
        layout_box.formatting_context = null;
        layout_box.is_layouted = false;
        layout_box.allocator = self.allocator;

        // TODO: 从样式表获取display、position、float等属性
        // 暂时使用默认值（block、static、none）

        // 递归构建子节点
        var child = node.first_child;
        while (child) |c| {
            const child_layout_box = try self.buildLayoutTree(c, stylesheets);
            child_layout_box.parent = layout_box;
            try layout_box.children.append(layout_box.allocator, child_layout_box);
            child = c.next_sibling;
        }

        return layout_box;
    }

    /// 执行布局计算
    /// 根据布局树的display类型，选择合适的布局算法
    pub fn layout(self: *LayoutEngine, layout_tree: *box.LayoutBox, viewport: box.Size) !void {
        // 根据display类型选择布局算法
        switch (layout_tree.display) {
            .block => {
                try block.layoutBlock(layout_tree, viewport);
            },
            .inline_element => {
                _ = try inline_layout.layoutInline(layout_tree, viewport);
                // 注意：layoutInline返回IFC指针，但这里暂时不处理
            },
            .flex, .inline_flex => {
                // Flexbox布局
                flexbox.layoutFlexbox(layout_tree, viewport);
            },
            .grid, .inline_grid => {
                // Grid布局
                grid.layoutGrid(layout_tree, viewport);
            },
            else => {
                // 默认使用block布局
                try block.layoutBlock(layout_tree, viewport);
            },
        }

        // 标记为已布局
        layout_tree.is_layouted = true;

        // 递归布局子节点
        // 注意：对于flex和grid布局，子节点的布局已经在各自的布局函数中处理
        // 这里只对block和inline布局进行递归
        if (layout_tree.display == .block or layout_tree.display == .inline_element) {
            for (layout_tree.children.items) |child| {
                // 子节点的containing_block是父节点的内容区域
                const containing_block = box.Size{
                    .width = layout_tree.box_model.content.width,
                    .height = layout_tree.box_model.content.height,
                };
                try self.layout(child, containing_block);
            }
        }
    }
};
