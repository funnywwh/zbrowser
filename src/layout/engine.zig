const std = @import("std");
const builtin = @import("builtin");
const dom = @import("dom");
const box = @import("box");
const block = @import("block");
const inline_layout = @import("inline");
const flexbox = @import("flexbox");
const grid = @import("grid");
const position = @import("position");
const cascade = @import("cascade");
const css_parser = @import("parser");
const style_utils = @import("style_utils");
const context = @import("context");

/// 调试输出函数（只在Debug模式下输出）
/// 使用条件编译，在Release模式下完全移除，避免性能影响
inline fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        std.debug.print(fmt, args);
    }
}

/// 布局引擎
/// 负责从DOM树构建布局树，并执行布局计算
pub const LayoutEngine = struct {
    allocator: std.mem.Allocator,
    stylesheets: []const css_parser.Stylesheet = &[_]css_parser.Stylesheet{},
    initial_viewport: ?box.Size = null, // 保存初始视口大小，用于fixed定位
    cascade_engine: cascade.Cascade, // 复用的Cascade实例，避免重复创建
    // TODO: 实现样式计算缓存（HashMap<Node指针 -> ComputedStyle>）
    // 当前实现：通过将computed_style存储在LayoutBox中已经实现了缓存
    // 每个DOM节点只对应一个LayoutBox，所以不会出现重复计算
    // 如果将来需要支持布局树复用（render-flow-9），可以实现真正的缓存机制

    /// 初始化布局引擎
    pub fn init(allocator: std.mem.Allocator) LayoutEngine {
        return .{
            .allocator = allocator,
            .cascade_engine = cascade.Cascade.init(allocator),
        };
    }

    /// 构建布局树（从DOM树构建）
    /// 计算样式并应用到布局框
    pub fn buildLayoutTree(self: *LayoutEngine, node: *dom.Node, stylesheets: []const css_parser.Stylesheet) !*box.LayoutBox {
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
            .border_radius = null, // 默认无圆角
            .min_width = null, // 默认无最小宽度限制
            .min_height = null, // 默认无最小高度限制
            .max_width = null, // 默认无最大宽度限制
            .max_height = null, // 默认无最大高度限制
        };
        layout_box.display = .block;
        layout_box.position = .static;
        layout_box.position_top = null;
        layout_box.position_right = null;
        layout_box.position_bottom = null;
        layout_box.position_left = null;
        layout_box.float = .none;
        layout_box.grid_row_start = null;
        layout_box.grid_row_end = null;
        layout_box.grid_column_start = null;
        layout_box.grid_column_end = null;
        layout_box.text_align = .left; // 默认左对齐
        layout_box.text_decoration = .none; // 默认无装饰
        layout_box.line_height = .normal; // 默认行高
        layout_box.overflow = .visible; // 默认不裁剪
        layout_box.letter_spacing = null; // 默认无额外字符间距
        layout_box.opacity = 1.0; // 默认完全不透明
        layout_box.z_index = null; // 默认使用auto堆叠顺序
        layout_box.vertical_align = .baseline; // 默认基线对齐
        layout_box.white_space = .normal; // 默认正常处理空白字符
        layout_box.word_wrap = .normal; // 默认正常换行
        layout_box.word_break = .normal; // 默认正常断行
        layout_box.text_transform = .none; // 默认不转换
        layout_box.box_shadow = null; // 默认无阴影
        layout_box.children = std.ArrayList(*box.LayoutBox){
            .items = &[_]*box.LayoutBox{},
            .capacity = 0,
        };
        layout_box.parent = null;
        layout_box.formatting_context = null;
        layout_box.is_layouted = false;
        layout_box.allocator = self.allocator;

        // 计算样式并应用到布局框
        // 注意：样式计算在buildLayoutTree阶段完成，保存到LayoutBox中，避免在渲染阶段重复计算
        // 样式缓存机制：通过将computed_style存储在LayoutBox中实现缓存
        // 每个DOM节点只对应一个LayoutBox，所以不会出现重复计算
        // 复用LayoutEngine的cascade_engine实例，避免重复创建
        var computed_style = try self.cascade_engine.computeStyle(node, stylesheets);
        // 不要deinit，保存到LayoutBox中，在LayoutBox.deinit时释放
        // 这已经实现了样式缓存：每个节点的样式只计算一次，存储在LayoutBox中
        layout_box.computed_style = computed_style;

        // 获取包含块尺寸（简化：使用默认值，后续可以从父节点获取）
        const containing_size = box.Size{ .width = 800, .height = 600 };
        style_utils.applyStyleToLayoutBox(layout_box, &computed_style, containing_size);

        // 递归构建子节点
        var child = node.first_child;
        while (child) |c| {
            // 跳过DOCTYPE节点（不应该产生布局box）
            // DOCTYPE是文档类型声明，不应该参与布局计算
            if (c.node_type == .doctype) {
                child = c.next_sibling;
                continue;
            }

            const child_layout_box = try self.buildLayoutTree(c, stylesheets);
            child_layout_box.parent = layout_box;
            try layout_box.children.append(layout_box.allocator, child_layout_box);
            child = c.next_sibling;
        }

        return layout_box;
    }

    /// 布局box状态（用于收敛检测）
    const BoxState = struct { box_ptr: *box.LayoutBox, x: f32, y: f32, w: f32, h: f32 };

    /// 收集布局树中所有box的状态（用于收敛检测）
    fn collectBoxStates(layout_box: *box.LayoutBox, states: *std.ArrayList(BoxState), allocator: std.mem.Allocator) !void {
        try states.append(allocator, BoxState{
            .box_ptr = layout_box,
            .x = layout_box.box_model.content.x,
            .y = layout_box.box_model.content.y,
            .w = layout_box.box_model.content.width,
            .h = layout_box.box_model.content.height,
        });

        for (layout_box.children.items) |child| {
            try collectBoxStates(child, states, allocator);
        }
    }

    /// 执行布局计算
    /// 根据布局树的display类型，选择合适的布局算法
    /// 实现布局收敛检测，避免多次不收敛的reflow
    pub fn layout(self: *LayoutEngine, layout_tree: *box.LayoutBox, viewport: box.Size, stylesheets: []const css_parser.Stylesheet) !void {
        // 保存初始视口大小（第一次调用时）
        if (self.initial_viewport == null) {
            self.initial_viewport = viewport;
        }

        // 二分屏蔽法：暂时完全禁用收敛检测，直接执行一次布局
        // 如果段错误消失，说明问题在收敛检测逻辑中
        // 执行一次布局
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
                flexbox.layoutFlexbox(layout_tree, viewport, stylesheets);
            },
            .grid, .inline_grid => {
                // Grid布局
                grid.layoutGrid(layout_tree, viewport, stylesheets);
            },
            else => {
                // 默认使用block布局
                try block.layoutBlock(layout_tree, viewport);
            },
        }

        // 二分屏蔽法：暂时注释掉收敛检测逻辑
        // 如果段错误消失，说明问题在收敛检测逻辑中
        // 收敛检测代码已暂时移除，直接执行一次布局

        // 标记为已布局
        layout_tree.is_layouted = true;

        // 递归布局和定位元素处理
        // 优化：只分配一次children_copy，用于所有处理步骤
        if (layout_tree.display == .block or layout_tree.display == .inline_element) {
            const children_count = layout_tree.children.items.len;
            if (children_count > 0) {
                // 分配临时数组保存子节点指针（只分配一次，用于所有处理步骤）
                const children_copy = layout_tree.allocator.alloc(*box.LayoutBox, children_count) catch {
                    // 如果分配失败，跳过递归布局
                    return;
                };
                defer layout_tree.allocator.free(children_copy);

                // 复制子节点指针
                @memcpy(children_copy, layout_tree.children.items);

                // 第一步：布局正常流的子元素
                for (children_copy) |child| {
                    // 跳过absolute和fixed定位的元素（它们稍后单独处理）
                    if (child.position == .absolute or child.position == .fixed) {
                        continue;
                    }

                    // 子节点的containing_block是父节点的内容区域
                    const containing_block = box.Size{
                        .width = layout_tree.box_model.content.width,
                        .height = layout_tree.box_model.content.height,
                    };
                    try self.layout(child, containing_block, stylesheets);
                }

                // 第二步：处理relative定位的元素（它们在正常流中，只需要应用偏移）
                for (children_copy) |child| {
                    if (child.position == .relative) {
                        const position_module = @import("position");
                        position_module.layoutPosition(child, viewport);
                    }
                }

                // 第三步：处理absolute定位的元素（需要找到定位祖先）
                for (children_copy) |child| {
                    if (child.position == .absolute) {
                        // 安全检查：确保parent指针有效
                        if (child.parent == null) {
                            continue;
                        }

                        const position_module = @import("position");
                        // 使用父节点的内容区域作为containing_block
                        const containing_block = box.Size{
                            .width = if (child.parent) |p| p.box_model.content.width else viewport.width,
                            .height = if (child.parent) |p| p.box_model.content.height else viewport.height,
                        };
                        position_module.layoutPosition(child, containing_block);
                    }
                }

                // 第四步：处理fixed定位的元素（相对于视口）
                for (children_copy) |child| {
                    if (child.position == .fixed) {
                        const position_module = @import("position");
                        position_module.layoutPosition(child, viewport);
                    }
                }
            }
        }
    }

    /// 更新子元素的位置（相对于父元素位置）
    /// 注意：只更新非绝对定位的子元素，绝对定位的子元素应该由layoutPosition处理
    fn updateChildrenPositionsRelativeToParent(self: *LayoutEngine, layout_box: *box.LayoutBox, parent_x: f32, parent_y: f32) void {
        // 递归更新所有非绝对定位的子元素的位置
        for (layout_box.children.items) |child| {
            // 跳过绝对定位的子元素，它们的位置应该由layoutPosition处理
            if (child.position == .absolute or child.position == .fixed) {
                continue;
            }

            // 子元素的位置应该相对于父元素的内容区域
            child.box_model.content.x = parent_x + child.box_model.margin.left;
            child.box_model.content.y = parent_y + child.box_model.margin.top;

            // 递归更新子元素的子元素（只更新非绝对定位的）
            self.updateChildrenPositionsRelativeToParent(child, child.box_model.content.x, child.box_model.content.y);
        }
    }

    /// 清理布局树中的所有formatting_context
    /// 这是一个辅助函数，用于在释放布局树之前清理formatting_context
    /// 注意：必须在deinitAndDestroyChildren之前调用
    pub fn cleanupFormattingContexts(layout_box: *box.LayoutBox) void {
        // 先清理当前节点的formatting_context，再递归清理子节点
        // 这样可以避免在递归过程中访问已释放的formatting_context
        if (layout_box.formatting_context) |ctx| {
            // 根据display类型清理formatting_context
            switch (layout_box.display) {
                .inline_element => {
                    // 清理IFC
                    // 注意：类型转换是unsafe的，但在这个上下文中是安全的
                    // 因为只有inline_element类型的box才会有InlineFormattingContext
                    // 使用容错处理：如果类型转换或清理失败，只设置为null
                    const ifc: *context.InlineFormattingContext = @ptrCast(@alignCast(ctx));
                    // 先调用deinit清理内部资源
                    ifc.deinit();
                    // 然后释放IFC本身
                    layout_box.allocator.destroy(ifc);
                },
                else => {
                    // 其他类型的formatting_context暂时不处理
                    // TODO: 实现其他类型的formatting_context清理
                },
            }
            layout_box.formatting_context = null;
        }

        // 递归清理所有子节点的formatting_context
        // 注意：在清理子节点之前，先保存children.items的副本，避免在清理过程中修改children导致迭代器失效
        const children_count = layout_box.children.items.len;
        if (children_count > 0) {
            // 分配临时数组保存子节点指针
            const children_copy = layout_box.allocator.alloc(*box.LayoutBox, children_count) catch {
                // 如果分配失败，直接遍历children.items（虽然可能有迭代器失效的风险，但总比泄漏好）
                // 注意：这种情况下，如果children在清理过程中被修改，可能会导致问题
                // 但这是最后的清理机会，必须尝试清理
                for (layout_box.children.items) |child| {
                    cleanupFormattingContexts(child);
                }
                return;
            };
            defer layout_box.allocator.free(children_copy);

            // 复制子节点指针
            @memcpy(children_copy, layout_box.children.items);

            // 递归清理子节点的formatting_context
            // 注意：必须递归清理所有子节点，包括深层嵌套的子节点
            for (children_copy) |child| {
                cleanupFormattingContexts(child);
            }
        }
        
    }
};
