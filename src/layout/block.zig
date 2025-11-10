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
    // 1. 计算宽度（考虑margin）
    // 如果当前元素有margin，可用宽度应该减去margin
    const available_width = containing_block.width - layout_box.box_model.margin.left - layout_box.box_model.margin.right;
    const width = calculateBlockWidth(layout_box, box.Size{ .width = available_width, .height = containing_block.height });
    layout_box.box_model.content.width = width;

    // 2. 应用margin到位置（如果父元素存在）
    // 在块级布局中，元素的margin应该影响元素相对于父元素的位置
    // 如果父元素存在，当前元素的位置 = 父元素内容区域位置 + 父元素padding + 当前元素margin
    // 但是，由于布局是递归的，当前元素的位置应该在父元素的block.zig中计算
    // 这里只处理根元素的位置（根元素的位置不需要margin）
    if (layout_box.parent == null) {
        // 根元素的位置是(0, 0)，不需要处理margin
        layout_box.box_model.content.x = 0;
        layout_box.box_model.content.y = 0;
    }

    // 3. 计算子元素布局
    // 注意：这里y从padding.top开始，因为子元素的位置是相对于父元素的内容区域的
    var y: f32 = layout_box.box_model.padding.top;

    // 遍历所有子元素
    for (layout_box.children.items) |child| {
        // 处理浮动元素
        if (child.float != .none) {
            // 关键修复：浮动元素需要先计算自己的宽度和高度
            // 1. 先计算浮动元素的宽度（使用containing_block的宽度作为参考）
            const child_containing_block = box.Size{
                .width = width - layout_box.box_model.padding.left - layout_box.box_model.padding.right,
                .height = containing_block.height,
            };
            
            // 2. 计算浮动元素的宽度（如果CSS中设置了width，会在这里设置）
            const child_width = calculateBlockWidth(child, child_containing_block);
            child.box_model.content.width = child_width;
            
            // 3. 布局浮动元素的子元素（递归调用）
            try layoutBlock(child, child_containing_block);
            
            // 4. 调用浮动布局函数
            // 注意：浮动元素应该相对于包含块的content区域
            // layout_box（containing_block）的content.y应该已经在父元素的layoutBlock中设置
            // 如果还没有设置，说明layout_box是根元素，content.y应该是0
            // 但是，如果layout_box是body的子元素，它的content.y应该在body布局时设置
            // 由于浮动元素在layout_box的layoutBlock中被处理，此时layout_box的content.y可能还没有被设置
            // 所以，我们需要使用layout_box的当前content.y（如果还没有设置，应该是0或之前的值）
            const float_module = @import("float");
            float_module.layoutFloat(child, layout_box, &y);
            continue;
        }

        // 跳过absolute和fixed定位的元素（它们不参与正常流布局）
        if (child.position == .absolute or child.position == .fixed) {
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

        // 计算子元素位置（考虑margin和padding）
        // 子元素的位置 = 父元素内容区域位置 + 父元素padding + 子元素margin
        // 注意：父元素的margin应该影响父元素的位置，而不是子元素的位置
        // 所以，子元素的位置是相对于父元素的内容区域的，不需要考虑父元素的margin
        child.box_model.content.x = layout_box.box_model.content.x + layout_box.box_model.padding.left + child.box_model.margin.left;
        child.box_model.content.y = layout_box.box_model.content.y + y + child.box_model.margin.top;

        // 对于文本节点，需要设置最小高度
        if (child.node.node_type == .text) {
            // 文本节点的最小高度应该足够容纳 ascent + descent
            // 简化：使用字体大小的1.5倍（典型值：ascent约75%，descent约25%）
            // 如果高度未设置，使用默认字体大小16px的1.5倍
            // 增加高度以确保descender（如'p'的尾巴）有足够空间显示
            // 注意：对于绝对定位的文本节点，高度计算应该在position.zig中处理
            if (child.position == .static and child.box_model.content.height == 0) {
                child.box_model.content.height = 16.0 * 1.5;
            }
        }

        // 更新y坐标（考虑子元素的高度和margin）
        // y坐标 = 父元素padding-top + 所有前面子元素的高度和margin
        const child_total_height = child.box_model.totalSize().height + child.box_model.margin.top + child.box_model.margin.bottom;
        y += child_total_height;
    }

    // 3. 计算高度
    // 如果高度未设置（为0），则根据子元素计算
    if (layout_box.box_model.content.height == 0) {
        layout_box.box_model.content.height = y + layout_box.box_model.padding.bottom;
    }
}
