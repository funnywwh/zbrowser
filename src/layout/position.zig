const std = @import("std");
const box = @import("box");

/// 定位布局算法
/// 处理CSS定位属性（static、relative、absolute、fixed、sticky）
/// 执行定位布局
/// 根据LayoutBox的position类型，计算并设置其最终位置
///
/// 参数：
/// - layout_box: 要定位的布局框
/// - viewport: 视口尺寸（用于fixed定位）
///
/// TODO: 简化实现 - 当前实现了static和relative定位的基本逻辑
/// 完整实现需要：
/// 1. 完善absolute定位（需要找到定位祖先）
/// 2. 完善fixed定位（需要滚动位置信息）
/// 3. 完善sticky定位（需要滚动位置信息）
/// 参考：CSS 2.1规范 9.3节（Positioning schemes）
pub fn layoutPosition(layout_box: *box.LayoutBox, viewport: box.Size) void {
    switch (layout_box.position) {
        .static => {
            // static定位：正常文档流，不需要特殊处理
            // 位置已经在block/inline布局中计算好了
            // 这里不需要做任何操作
        },
        .relative => {
            // relative定位：相对于正常位置偏移
            // 参考：CSS 2.1规范 9.4.3节（Relative positioning）
            layoutRelative(layout_box);
        },
        .absolute => {
            // absolute定位：相对于最近的定位祖先
            // TODO: 简化实现 - 当前假设相对于父元素定位
            // 完整实现需要找到最近的定位祖先（position != static）
            // 参考：CSS 2.1规范 9.6.1节（Absolute positioning）
            layoutAbsolute(layout_box, viewport);
        },
        .fixed => {
            // fixed定位：相对于视口
            // 参考：CSS 2.1规范 9.6.1节（Fixed positioning）
            layoutFixed(layout_box, viewport);
        },
        .sticky => {
            // sticky定位：在滚动时会"粘"在指定位置
            // TODO: 简化实现 - 当前只处理初始位置
            // 完整实现需要跟踪滚动位置
            // 参考：CSS Positioned Layout Module Level 3
            layoutSticky(layout_box, viewport);
        },
    }
}

/// Relative定位：相对于正常位置偏移
/// 根据top、right、bottom、left值计算偏移量
/// top/left优先，如果未设置则使用bottom/right
fn layoutRelative(layout_box: *box.LayoutBox) void {
    // 计算水平偏移（left优先，如果未设置则使用right）
    if (layout_box.position_left) |left| {
        layout_box.box_model.content.x += left;
    } else if (layout_box.position_right) |right| {
        // right值需要相对于包含块的宽度计算
        // 简化实现：假设包含块宽度已知，这里暂时不处理right
        // TODO: 需要传入containing_block参数
        _ = right;
    }

    // 计算垂直偏移（top优先，如果未设置则使用bottom）
    if (layout_box.position_top) |top| {
        layout_box.box_model.content.y += top;
    } else if (layout_box.position_bottom) |bottom| {
        // bottom值需要相对于包含块的高度计算
        // 简化实现：假设包含块高度已知，这里暂时不处理bottom
        // TODO: 需要传入containing_block参数
        _ = bottom;
    }
}

/// Absolute定位：相对于最近的定位祖先
/// TODO: 简化实现 - 当前假设相对于父元素定位
fn layoutAbsolute(layout_box: *box.LayoutBox, containing_block: box.Size) void {
    std.log.debug("[Position] layoutAbsolute: start, position_left={?}, position_top={?}, containing_block=({d:.1}x{d:.1})", 
        .{ layout_box.position_left, layout_box.position_top, containing_block.width, containing_block.height });
    
    // 找到定位祖先，获取其内容区域的位置
    // 如果找不到定位祖先，使用传入的containing_block（通常是视口或初始包含块）
    var containing_block_x: f32 = 0;
    var containing_block_y: f32 = 0;
    var positioned_ancestor: ?*box.LayoutBox = null;
    var ancestor = layout_box.parent;
    while (ancestor) |anc| {
        if (anc.position != .static) {
            // 找到定位祖先，使用其内容区域的位置
            // 注意：对于relative定位的元素，内容区域位置就是正常流位置（relative只是偏移，不影响包含块）
            containing_block_x = anc.box_model.content.x;
            containing_block_y = anc.box_model.content.y;
            positioned_ancestor = anc;
            const node_type_str = switch (anc.node.node_type) {
                .element => if (anc.node.asElement()) |elem| elem.tag_name else "unknown",
                .text => "text",
                .comment => "comment",
                .document => "document",
                .doctype => "doctype",
            };
            std.log.debug("[Position] layoutAbsolute: found positioned ancestor '{s}' (position={}) at ({d:.1}, {d:.1})", 
                .{ node_type_str, anc.position, containing_block_x, containing_block_y });
            break;
        }
        ancestor = anc.parent;
    }
    
    if (positioned_ancestor == null) {
        std.log.debug("[Position] layoutAbsolute: no positioned ancestor found, using viewport (0, 0)", .{});
    }
    
    // 如果找不到定位祖先，使用传入的containing_block（相对于视口或初始包含块）
    // 此时containing_block_x和containing_block_y已经是0，这是正确的

    // 计算水平位置（left优先，如果未设置则使用right）
    if (layout_box.position_left) |left| {
        layout_box.box_model.content.x = containing_block_x + left;
        std.log.debug("[Position] layoutAbsolute: set x = {d:.1} + {d:.1} = {d:.1}", .{ containing_block_x, left, layout_box.box_model.content.x });
    } else if (layout_box.position_right) |right| {
        // right值相对于包含块的右边缘
        const total_width = layout_box.box_model.content.width +
            layout_box.box_model.padding.horizontal() +
            layout_box.box_model.border.horizontal();
        const block_width = if (positioned_ancestor) |anc| 
            anc.box_model.content.width
        else 
            containing_block.width;
        layout_box.box_model.content.x = containing_block_x + block_width - total_width - right;
    } else {
        // 如果left和right都未设置，使用默认值0
        layout_box.box_model.content.x = containing_block_x;
        std.log.debug("[Position] layoutAbsolute: no left/right, set x = {d:.1}", .{containing_block_x});
    }

    // 计算垂直位置（top优先，如果未设置则使用bottom）
    if (layout_box.position_top) |top| {
        layout_box.box_model.content.y = containing_block_y + top;
        std.log.debug("[Position] layoutAbsolute: set y = {d:.1} + {d:.1} = {d:.1}", .{ containing_block_y, top, layout_box.box_model.content.y });
    } else if (layout_box.position_bottom) |bottom| {
        // bottom值相对于包含块的下边缘
        const total_height = layout_box.box_model.content.height +
            layout_box.box_model.padding.vertical() +
            layout_box.box_model.border.vertical();
        const block_height = if (positioned_ancestor) |anc| 
            anc.box_model.content.height
        else 
            containing_block.height;
        layout_box.box_model.content.y = containing_block_y + block_height - total_height - bottom;
    } else {
        // 如果top和bottom都未设置，使用默认值0
        layout_box.box_model.content.y = containing_block_y;
        std.log.debug("[Position] layoutAbsolute: no top/bottom, set y = {d:.1}", .{containing_block_y});
    }
    
    std.log.debug("[Position] layoutAbsolute: final position = ({d:.1}, {d:.1})", .{ layout_box.box_model.content.x, layout_box.box_model.content.y });
}

/// Fixed定位：相对于视口
fn layoutFixed(layout_box: *box.LayoutBox, viewport: box.Size) void {
    // fixed定位与absolute类似，但相对于视口而不是包含块
    layoutAbsolute(layout_box, viewport);
}

/// Sticky定位：在滚动时会"粘"在指定位置
/// TODO: 简化实现 - 当前只处理初始位置
fn layoutSticky(layout_box: *box.LayoutBox, containing_block: box.Size) void {
    // TODO: 完整实现需要跟踪滚动位置
    // 当前简化实现：使用与relative类似的逻辑
    _ = containing_block;

    // 初始位置使用relative定位逻辑
    layoutRelative(layout_box);

    // TODO: 当滚动时，如果元素到达指定位置，将其"粘"在那里
    // 这需要：
    // 1. 跟踪滚动位置
    // 2. 计算元素是否应该"粘"住
    // 3. 如果应该"粘"住，使用fixed定位逻辑
}
