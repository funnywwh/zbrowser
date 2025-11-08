const std = @import("std");
const box = @import("box");

/// 计算块级元素宽度
/// 简化实现：如果已经设置了宽度，使用设置的宽度；否则使用containing_block的宽度
pub fn calculateBlockWidth(layout_box: *box.LayoutBox, containing_block: box.Size) f32 {
    // 如果已经设置了宽度，使用设置的宽度
    if (layout_box.box_model.content.width > 0) {
        return layout_box.box_model.content.width;
    }

    // 否则使用containing_block的宽度（auto宽度）
    return containing_block.width;
}

/// 块级布局算法
/// 根据CSS规范实现块级格式化上下文的布局
pub fn layoutBlock(layout_box: *box.LayoutBox, containing_block: box.Size) !void {
    // 1. 计算宽度
    const width = calculateBlockWidth(layout_box, containing_block);
    layout_box.box_model.content.width = width;

    // 2. 计算子元素布局
    var y: f32 = layout_box.box_model.padding.top;

    // 遍历所有子元素
    for (layout_box.children.items) |child| {
        // 处理浮动（暂时跳过，后续在float.zig中实现）
        if (child.float != .none) {
            // TODO: 实现浮动布局
            continue;
        }

        // 布局子元素（递归调用，暂时简化处理）
        // TODO: 根据子元素的display类型选择不同的布局算法
        // 先布局子元素，无论是否有子元素
        const child_containing_block = box.Size{
            .width = width - layout_box.box_model.padding.left - layout_box.box_model.padding.right,
            .height = containing_block.height,
        };
        try layoutBlock(child, child_containing_block);

        // 计算子元素位置（考虑margin）
        child.box_model.content.x = layout_box.box_model.content.x + layout_box.box_model.padding.left + child.box_model.margin.left;
        child.box_model.content.y = layout_box.box_model.content.y + y + child.box_model.margin.top;

        // 对于文本节点，需要设置最小高度
        if (child.node.node_type == .text) {
            // 文本节点的最小高度应该是字体大小
            // 简化：使用默认字体大小16px
            if (child.box_model.content.height == 0) {
                child.box_model.content.height = 16.0;
            }
        }

        // 更新y坐标（考虑子元素的高度和margin）
        const child_total_height = child.box_model.totalSize().height + child.box_model.margin.top + child.box_model.margin.bottom;
        y += child_total_height;
    }

    // 3. 计算高度
    // 如果高度未设置（为0），则根据子元素计算
    if (layout_box.box_model.content.height == 0) {
        layout_box.box_model.content.height = y + layout_box.box_model.padding.bottom;
    }
}
