const std = @import("std");
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

/// 布局引擎
/// 负责从DOM树构建布局树，并执行布局计算
pub const LayoutEngine = struct {
    allocator: std.mem.Allocator,
    stylesheets: []const css_parser.Stylesheet = &[_]css_parser.Stylesheet{},

    /// 初始化布局引擎
    pub fn init(allocator: std.mem.Allocator) LayoutEngine {
        return .{ .allocator = allocator };
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

        // 计算样式并应用到布局框
        var cascade_engine = cascade.Cascade.init(self.allocator);
        var computed_style = try cascade_engine.computeStyle(node, stylesheets);
        defer computed_style.deinit();

        // 获取包含块尺寸（简化：使用默认值，后续可以从父节点获取）
        const containing_size = box.Size{ .width = 800, .height = 600 };
        style_utils.applyStyleToLayoutBox(layout_box, &computed_style, containing_size);

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
    pub fn layout(self: *LayoutEngine, layout_tree: *box.LayoutBox, viewport: box.Size, stylesheets: []const css_parser.Stylesheet) !void {
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

        // 标记为已布局
        layout_tree.is_layouted = true;

        // 处理定位元素（relative、absolute、fixed等）
        // 注意：relative定位需要在正常流布局之后处理
        if (layout_tree.position == .relative) {
            position.layoutPosition(layout_tree, viewport);
        } else if (layout_tree.position != .static) {
            // absolute和fixed定位：找到定位祖先
            var containing_block = viewport;
            var ancestor = layout_tree.parent;
            while (ancestor) |anc| {
                if (anc.position != .static) {
                    containing_block = box.Size{
                        .width = anc.box_model.content.width,
                        .height = anc.box_model.content.height,
                    };
                    break;
                }
                ancestor = anc.parent;
            }
            position.layoutPosition(layout_tree, containing_block);
        }

        // 递归布局子节点
        // 注意：对于flex和grid布局，子节点的布局已经在各自的布局函数中处理
        // 这里只对block和inline布局进行递归
        if (layout_tree.display == .block or layout_tree.display == .inline_element) {
            // 先布局正常流的子元素
            for (layout_tree.children.items) |child| {
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
                
                // 在块级布局中，父元素的margin应该影响父元素的位置
                // 关键问题：父元素（layout_tree）的位置需要包含margin
                // 但是，由于布局是递归的，父元素的位置应该在父元素的父元素的block.zig中计算
                // 这里不需要处理，因为child的位置已经在block.zig中计算了
                // 但是，我们需要确保父元素的位置包含了父元素的margin
                // 这应该在父元素的父元素的block.zig中处理
            }
            
            // 然后处理absolute和fixed定位的子元素
            for (layout_tree.children.items) |child| {
                if (child.position == .absolute or child.position == .fixed) {
                    const child_node_type_str = switch (child.node.node_type) {
                        .element => if (child.node.asElement()) |elem| elem.tag_name else "unknown",
                        .text => "text",
                        .comment => "comment",
                        .document => "document",
                        .doctype => "doctype",
                    };
                    std.log.debug("[LayoutEngine] Processing absolute/fixed child: '{s}', position={}, position_left={?}, position_top={?}", 
                        .{ child_node_type_str, child.position, child.position_left, child.position_top });
                    
                    // 先定位父元素（如果父元素也是绝对定位的），确保子元素能找到正确的定位祖先
                    // 找到定位祖先（position != static）
                    // 如果找不到定位祖先，使用视口作为包含块
                    var ancestor_containing_block = viewport;
                    var ancestor: ?*box.LayoutBox = layout_tree;
                    while (ancestor) |anc| {
                        if (anc.position != .static) {
                            ancestor_containing_block = box.Size{
                                .width = anc.box_model.content.width,
                                .height = anc.box_model.content.height,
                            };
                            const ancestor_node_type_str = switch (anc.node.node_type) {
                                .element => if (anc.node.asElement()) |elem| elem.tag_name else "unknown",
                                .text => "text",
                                .comment => "comment",
                                .document => "document",
                                .doctype => "doctype",
                            };
                            std.log.debug("[LayoutEngine] Found positioned ancestor for '{s}': '{s}' (position={}) at ({d:.1}, {d:.1})", 
                                .{ child_node_type_str, ancestor_node_type_str, anc.position, anc.box_model.content.x, anc.box_model.content.y });
                            break;
                        }
                        ancestor = anc.parent;
                    }
                    
                    if (ancestor == null) {
                        std.log.debug("[LayoutEngine] No positioned ancestor found for '{s}', using viewport", .{child_node_type_str});
                    }
                    
                    // 先应用绝对定位（在递归布局子元素之前）
                    // 这样，当子元素查找定位祖先时，父元素的位置已经是正确的
                    position.layoutPosition(child, ancestor_containing_block);
                    
                    // 然后递归布局子元素（包括其子元素）
                    const containing_block = box.Size{
                        .width = layout_tree.box_model.content.width,
                        .height = layout_tree.box_model.content.height,
                    };
                    try self.layout(child, containing_block, stylesheets);
                    
                    // 绝对定位后，对于非绝对定位的子元素，需要更新它们的位置（相对于新的父元素位置）
                    // 注意：绝对定位的子元素不应该被更新，因为它们的位置应该由layoutPosition处理
                    const parent_x = child.box_model.content.x;
                    const parent_y = child.box_model.content.y;
                    
                    // 更新所有非绝对定位的子元素的位置（相对于新的父元素位置）
                    for (child.children.items) |grandchild| {
                        // 跳过绝对定位的子元素，它们的位置应该由layoutPosition处理
                        if (grandchild.position == .absolute or grandchild.position == .fixed) {
                            continue;
                        }
                        
                        // 子元素的位置应该相对于父元素的内容区域
                        grandchild.box_model.content.x = parent_x + grandchild.box_model.margin.left;
                        grandchild.box_model.content.y = parent_y + grandchild.box_model.margin.top;
                        
                        // 递归更新子元素的子元素（只更新非绝对定位的）
                        self.updateChildrenPositionsRelativeToParent(grandchild, parent_x, parent_y);
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
};
