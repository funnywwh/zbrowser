const std = @import("std");
const box = @import("box");

/// 浮动布局算法
/// 处理CSS浮动属性（float: left, right）
/// 执行浮动布局
/// 将浮动元素放置在包含块中的合适位置
///
/// 参数：
/// - layout_box: 要浮动的布局框
/// - containing_block: 包含块布局框
/// - y: 当前y坐标（会被更新为浮动元素底部位置）
///
/// TODO: 简化实现 - 当前实现了基本的浮动布局逻辑
/// 完整实现需要：
/// 1. 处理浮动元素的碰撞检测（避免重叠）
/// 2. 处理浮动元素的换行（当一行放不下时）
/// 3. 处理浮动元素与正常流的交互
/// 参考：CSS 2.1规范 9.5节（Floats）
pub fn layoutFloat(layout_box: *box.LayoutBox, containing_block: *box.LayoutBox, y: *f32) void {
    // 确定浮动方向
    const float_left = layout_box.float == .left;

    // 计算浮动位置
    var x: f32 = if (float_left) 0 else containing_block.box_model.content.width - layout_box.box_model.content.width;

    // TODO: 检查与其他浮动元素的碰撞
    // 当前简化实现：假设没有碰撞
    x = findFloatPosition(layout_box, containing_block, x, y.*, float_left);

    // 设置位置（相对于包含块）
    layout_box.box_model.content.x = containing_block.box_model.content.x + x;
    layout_box.box_model.content.y = containing_block.box_model.content.y + y.*;

    // 标记为已布局
    layout_box.is_layouted = true;

    // 更新y坐标（取当前y和浮动元素底部位置的最大值）
    const float_bottom = y.* + layout_box.box_model.content.height;
    y.* = float_bottom;
}

/// 查找浮动位置
/// 检查与其他浮动元素的碰撞，找到合适的位置
///
/// TODO: 简化实现 - 当前实现了基本的碰撞检测
/// 完整实现需要：
/// 1. 更精确的碰撞检测（考虑padding、border等）
/// 2. 处理浮动元素的换行（当一行放不下时）
/// 3. 处理不同方向的浮动元素（left和right混合）
fn findFloatPosition(layout_box: *box.LayoutBox, containing_block: *box.LayoutBox, x: f32, y: f32, float_left: bool) f32 {
    // 获取包含块中的所有浮动元素
    var current_x = x;
    const layout_width = layout_box.box_model.content.width;
    const layout_height = layout_box.box_model.content.height;

    // 检查包含块的子元素中是否有浮动元素
    for (containing_block.children.items) |child| {
        // 只检查浮动元素
        if (child.float == .none) continue;
        if (child == layout_box) continue; // 跳过自己

        // 只检查已经布局好的浮动元素（位置已经设置）
        // 通过检查is_layouted标志来判断元素是否已经布局
        if (!child.is_layouted) continue;

        // 检查是否在同一行（y坐标重叠）
        // 注意：child的坐标是绝对坐标，y是相对坐标
        // 需要将child的坐标转换为相对坐标
        const child_x_abs = child.box_model.content.x;
        const child_y_abs = child.box_model.content.y;
        const containing_x_abs = containing_block.box_model.content.x;
        const containing_y_abs = containing_block.box_model.content.y;
        const child_y_relative = child_y_abs - containing_y_abs;
        const child_bottom = child_y_relative + child.box_model.content.height;
        if (y >= child_bottom or y + layout_height <= child_y_relative) {
            // 不在同一行，不碰撞
            continue;
        }

        // 检查水平方向是否碰撞
        // 注意：child的坐标是绝对坐标，x是相对坐标
        const child_x_relative = child_x_abs - containing_x_abs;
        const child_width = child.box_model.content.width;
        const child_right = child_x_relative + child_width;

        if (float_left) {
            // 左浮动：如果当前x位置与已有浮动元素重叠，调整到其右侧
            if (current_x < child_right and current_x + layout_width > child_x_relative) {
                current_x = child_right;
            }
        } else {
            // 右浮动：如果当前x位置与已有浮动元素重叠，调整到其左侧
            if (current_x + layout_width > child_x_relative and current_x < child_right) {
                current_x = child_x_relative - layout_width;
            }
        }
    }

    return current_x;
}

/// 清除浮动
/// 计算包含块中所有浮动元素的最大底部位置
///
/// 参数：
/// - containing_block: 包含块布局框
/// - y: 当前y坐标
///
/// 返回：所有浮动元素的最大底部位置
pub fn clearFloats(containing_block: *box.LayoutBox, y: f32) f32 {
    var max_y = y;

    // 获取包含块中的所有浮动元素
    for (containing_block.children.items) |child| {
        // 只检查浮动元素
        if (child.float == .none) continue;

        // 只检查已经布局好的浮动元素
        if (!child.is_layouted) continue;

        // 计算浮动元素的底部位置（相对于包含块）
        const child_y_abs = child.box_model.content.y;
        const containing_y_abs = containing_block.box_model.content.y;
        const child_y_relative = child_y_abs - containing_y_abs;
        const child_bottom = child_y_relative + child.box_model.content.height;

        // 更新最大y值
        if (child_bottom > max_y) {
            max_y = child_bottom;
        }
    }

    return max_y;
}
