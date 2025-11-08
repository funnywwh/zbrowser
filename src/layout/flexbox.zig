const std = @import("std");
const box = @import("box");
const cascade = @import("cascade");
const css_parser = @import("parser");
const style_utils = @import("style_utils");

/// Flexbox布局算法
/// 处理CSS Flexbox布局（display: flex, inline-flex）
/// 执行Flexbox布局
/// 根据Flexbox规范计算flex容器和flex items的位置和尺寸
///
/// 参数：
/// - layout_box: Flex容器布局框
/// - containing_block: 包含块尺寸
/// - stylesheets: CSS样式表（用于获取Flexbox属性）
///
/// TODO: 简化实现 - 当前实现了基本的row和column方向布局，不换行
/// 完整实现需要：
/// 1. 实现flex items的基础尺寸计算
/// 2. 实现flex items的flex尺寸计算（考虑flex-grow, flex-shrink, flex-basis）
/// 3. 实现flex lines的计算（处理换行）
/// 4. 实现交叉轴尺寸计算
/// 5. 实现对齐算法（justify-content, align-items, align-content）
/// 6. 处理flex-direction的反向（row-reverse, column-reverse）
/// 参考：CSS Flexible Box Layout Module Level 1
pub fn layoutFlexbox(layout_box: *box.LayoutBox, containing_block: box.Size, stylesheets: []const css_parser.Stylesheet) void {
    // 计算样式以获取Flexbox属性
    var cascade_engine = cascade.Cascade.init(layout_box.allocator);
    var computed_style = cascade_engine.computeStyle(layout_box.node, stylesheets) catch {
        // 如果计算样式失败，使用默认值
        layoutFlexboxDefault(layout_box, containing_block);
        return;
    };
    defer computed_style.deinit();

    // 获取Flexbox属性
    const flex_direction = style_utils.getFlexDirection(&computed_style);
    const flex_wrap = style_utils.getFlexWrap(&computed_style);
    const justify_content = style_utils.getJustifyContent(&computed_style);
    _ = flex_wrap; // TODO: 实现换行
    _ = justify_content; // TODO: 实现对齐

    // 确定主轴方向
    const is_row = flex_direction == .row or flex_direction == .row_reverse;

    // 标记容器为已布局
    layout_box.is_layouted = true;

    // 简化实现：row方向，水平排列items
    if (is_row) {
        var x_offset: f32 = 0;
        const container_x = layout_box.box_model.content.x;
        const container_y = layout_box.box_model.content.y;

        for (layout_box.children.items) |child| {
            // 设置子元素位置（相对于容器）
            child.box_model.content.x = container_x + x_offset;
            child.box_model.content.y = container_y;

            // 更新x偏移量（累加子元素宽度）
            x_offset += child.box_model.content.width;

            // 标记子元素为已布局
            child.is_layouted = true;
        }
    } else {
        // column方向，垂直排列items
        var y_offset: f32 = 0;
        const container_x = layout_box.box_model.content.x;
        const container_y = layout_box.box_model.content.y;

        for (layout_box.children.items) |child| {
            // 设置子元素位置（相对于容器）
            child.box_model.content.x = container_x;
            child.box_model.content.y = container_y + y_offset;

            // 更新y偏移量（累加子元素高度）
            y_offset += child.box_model.content.height;

            // 标记子元素为已布局
            child.is_layouted = true;
        }
    }
}

/// 使用默认值的Flexbox布局（当样式计算失败时）
fn layoutFlexboxDefault(layout_box: *box.LayoutBox, containing_block: box.Size) void {
    _ = containing_block;
    layout_box.is_layouted = true;

    // 默认row方向
    var x_offset: f32 = 0;
    const container_x = layout_box.box_model.content.x;
    const container_y = layout_box.box_model.content.y;

    for (layout_box.children.items) |child| {
        child.box_model.content.x = container_x + x_offset;
        child.box_model.content.y = container_y;
        x_offset += child.box_model.content.width;
        child.is_layouted = true;
    }
}
