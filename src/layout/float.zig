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
/// 实现已改进：
/// 1. ✅ 碰撞检测已实现（考虑padding和border）
/// 2. ✅ 换行功能已实现（当一行放不下时自动换行）
/// TODO: 简化实现 - 完整实现还需要：
/// 1. 处理浮动元素与正常流的交互
/// 参考：CSS 2.1规范 9.5节（Floats）
pub fn layoutFloat(layout_box: *box.LayoutBox, containing_block: *box.LayoutBox, y: *f32) void {
    // 确定浮动方向
    const float_left = layout_box.float == .left;

    // 使用totalSize()获取包含padding和border的总宽度
    const layout_total_size = layout_box.box_model.totalSize();
    const layout_total_width = layout_total_size.width;
    const layout_total_height = layout_total_size.height;
    
    // 边界检查：确保尺寸有效
    if (layout_total_width <= 0 or layout_total_height <= 0) {
        layout_box.is_layouted = true;
        return;
    }

    // 计算浮动位置
    var x: f32 = if (float_left) 0 else containing_block.box_model.content.width - layout_total_width;

    // 关键修复：浮动元素应该从当前行的y坐标开始
    // 先检查是否有已布局的浮动元素，如果有，使用它们的最小y坐标（同一行）
    // 如果没有，使用y.*（第一个浮动元素）
    var current_y: f32 = undefined;
    var min_y_in_line: ?f32 = null;
    
    // 计算初始y坐标（从padding.top开始，不考虑已布局的浮动元素）
    // 这样可以找到同一行的浮动元素，即使y.*已经被更新
    const initial_y = containing_block.box_model.padding.top;
    
    // 查找所有已布局的浮动元素，找到最小y坐标（同一行的起始位置）
    // 策略：查找所有已布局的浮动元素，找到它们的最小y坐标
    // 只考虑与初始y坐标接近（同一行）的浮动元素
    for (containing_block.children.items) |child| {
        if (child.float == .none) continue;
        if (child == layout_box) continue;
        if (!child.is_layouted) continue;
        
        // 获取浮动元素的y坐标（相对于包含块）
        const child_y_abs = child.box_model.content.y;
        const containing_y_abs = containing_block.box_model.content.y;
        const child_margin_top = child.box_model.margin.top;
        
        // 计算浮动元素相对于包含块内容区域的y坐标（不包括padding和margin）
        // 浮动元素的最终y坐标 = containing_block.content.y + current_y + child.margin.top
        // 所以：current_y = child_y_abs - containing_y_abs - child_margin_top
        // 这个current_y就是浮动元素在布局时使用的y坐标
        const child_y_relative = child_y_abs - containing_y_abs - child_margin_top;
        
        // 只考虑与当前包含块相关的浮动元素（避免使用其他包含块的浮动元素坐标）
        // 如果child_y_relative是负数或非常大，说明这个浮动元素不属于当前包含块，应该跳过
        if (child_y_relative < -100.0 or child_y_relative > 10000.0) {
            continue;
        }
        
        // 只考虑与初始y坐标接近（同一行）的浮动元素
        // 如果child_y_relative与initial_y接近（在100像素内），认为是同一行
        if (@abs(child_y_relative - initial_y) < 100.0) {
            // 找到最小y坐标（同一行的起始位置）
            if (min_y_in_line == null or child_y_relative < min_y_in_line.?) {
                min_y_in_line = child_y_relative;
            }
        }
    }
    
    // 如果找到了已布局的浮动元素，检查最小y坐标
    // 策略：使用初始y坐标（padding.top）来判断是否在同一行
    // 如果min_y与initial_y接近（在100像素内），认为是同一行，使用min_y
    // 否则，使用y.*（新行）
    if (min_y_in_line) |min_y| {
        // 如果min_y与initial_y接近（在100像素内），认为是同一行，使用min_y
        if (@abs(min_y - initial_y) < 100.0) {
            // 在同一行，使用最小y坐标
            current_y = min_y;
        } else {
            // 不在同一行，使用y.*（新行）
            current_y = y.*;
        }
    } else {
        // 没有已布局的浮动元素，使用initial_y（padding.top）
        // 注意：y.*可能已经被前面的元素更新了，所以应该使用initial_y
        // 浮动元素应该相对于包含块的content区域，所以应该从padding.top开始
        current_y = initial_y;
    }

    // 查找合适的位置（考虑碰撞检测）
    x = findFloatPosition(layout_box, containing_block, x, current_y, float_left);

    // 检查是否需要换行（如果调整后的位置超出了包含块宽度）
    // 对于左浮动：如果x + layout_total_width > containing_block宽度，需要换行
    // 对于右浮动：如果x < 0，需要换行
    const needs_wrap = if (float_left)
        (x + layout_total_width > containing_block.box_model.content.width)
    else
        (x < 0);

    if (needs_wrap) {
        // 需要换行：找到下一行的y位置（所有浮动元素的最大底部位置）
        current_y = clearFloats(containing_block, current_y);
        // 重新计算x位置（换行后从新行开始）
        x = if (float_left) 0 else containing_block.box_model.content.width - layout_total_width;
        // 再次查找位置（在新行中）
        x = findFloatPosition(layout_box, containing_block, x, current_y, float_left);
    }

    // 设置位置（相对于包含块）
    // 注意：x和current_y都是相对于containing_block的内容区域的坐标
    // 浮动元素的位置 = containing_block.content位置 + containing_block.padding + current_y + margin
    // current_y是从padding.top开始的（相对于containing_block的content区域）
    // 所以需要加上containing_block的content坐标和margin
    // 但是，x是相对于containing_block内容区域的，所以需要加上padding.left
    layout_box.box_model.content.x = containing_block.box_model.content.x + containing_block.box_model.padding.left + x + layout_box.box_model.margin.left;
    layout_box.box_model.content.y = containing_block.box_model.content.y + current_y + layout_box.box_model.margin.top;
    
    // 标记为已布局
    layout_box.is_layouted = true;

    // 更新y坐标（取当前y和浮动元素底部位置的最大值）
    // 注意：这里更新y是为了后续的正常流元素知道浮动元素占用的空间
    const float_bottom = current_y + layout_total_height;
    if (float_bottom > y.*) {
        y.* = float_bottom;
    }
}

/// 查找浮动位置
/// 检查与其他浮动元素的碰撞，找到合适的位置
///
/// 实现已改进：
/// 1. ✅ 碰撞检测现在考虑padding和border（使用totalSize()）
/// 2. ✅ 换行功能已实现（在layoutFloat中检查并处理换行）
/// TODO: 简化实现 - 完整实现还需要：
/// 1. 处理不同方向的浮动元素（left和right混合）
fn findFloatPosition(layout_box: *box.LayoutBox, containing_block: *box.LayoutBox, x: f32, y: f32, float_left: bool) f32 {
    // 获取包含块中的所有浮动元素
    var current_x = x;
    // 使用totalSize()获取包含padding和border的总尺寸
    const layout_total_size = layout_box.box_model.totalSize();
    const layout_width = layout_total_size.width;
    const layout_height = layout_total_size.height;

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
        // 使用totalSize()获取包含padding和border的总高度
        const child_x_abs = child.box_model.content.x;
        const child_y_abs = child.box_model.content.y;
        const containing_x_abs = containing_block.box_model.content.x;
        const containing_y_abs = containing_block.box_model.content.y;
        const child_y_relative = child_y_abs - containing_y_abs;
        const child_total_size = child.box_model.totalSize();
        const child_bottom = child_y_relative + child_total_size.height;
        if (y >= child_bottom or y + layout_height <= child_y_relative) {
            // 不在同一行，不碰撞
            continue;
        }

        // 检查水平方向是否碰撞
        // 注意：child的坐标是绝对坐标，x是相对坐标
        // 使用totalSize()获取包含padding和border的总宽度
        const child_x_relative = child_x_abs - containing_x_abs;
        const child_total_width = child_total_size.width;
        const child_right = child_x_relative + child_total_width;

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
        // 使用totalSize()获取包含padding和border的总高度
        const child_y_abs = child.box_model.content.y;
        const containing_y_abs = containing_block.box_model.content.y;
        const child_y_relative = child_y_abs - containing_y_abs;
        const child_total_size = child.box_model.totalSize();
        const child_bottom = child_y_relative + child_total_size.height;

        // 更新最大y值
        if (child_bottom > max_y) {
            max_y = child_bottom;
        }
    }

    return max_y;
}
