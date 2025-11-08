const std = @import("std");
const box = @import("box");
const context = @import("context");

/// 清理IFC（接受已知的IFC类型）
/// 这是一个辅助函数，用于清理formatting_context中的IFC
/// 注意：这个函数接受已知的IFC类型，不进行类型转换
pub fn deinitIFC(ifc: *context.InlineFormattingContext, allocator: std.mem.Allocator) void {
    ifc.deinit();
    allocator.destroy(ifc);
}

/// 创建行框
fn createLineBox(ifc: *context.InlineFormattingContext, y: f32, allocator: std.mem.Allocator) !*context.LineBox {
    // 创建行框（作为值添加到line_boxes）
    const line_box = context.LineBox{
        .rect = box.Rect{
            .x = 0,
            .y = y,
            .width = 0,
            .height = 0,
        },
        .inline_boxes = std.ArrayList(*box.LayoutBox){},
        .baseline = 0,
        .line_height = 0,
    };
    try ifc.line_boxes.append(allocator, line_box);

    // 返回最后添加的行框的指针
    return &ifc.line_boxes.items[ifc.line_boxes.items.len - 1];
}

/// 行内布局算法
/// 根据CSS规范实现行内格式化上下文的布局
/// 返回创建的IFC指针，用于测试中清理
/// TODO: 简化实现 - 当前总是创建新的IFC，如果已存在formatting_context，会导致内存泄漏
pub fn layoutInline(layout_box: *box.LayoutBox, containing_block: box.Size) !*context.InlineFormattingContext {
    // 创建或获取IFC
    var ifc: ?*context.InlineFormattingContext = null;

    // 检查是否已有IFC
    // 注意：由于formatting_context是*anyopaque，类型转换比较复杂
    // 这里简化处理，总是创建新的IFC（如果已存在，会在deinit时清理）
    _ = layout_box.formatting_context;

    // 如果没有IFC，创建新的
    // 注意：如果已存在formatting_context，需要先清理
    // 简化处理：暂时总是创建新的（旧的需要在测试中手动清理）
    const new_ifc = try layout_box.allocator.create(context.InlineFormattingContext);
    new_ifc.* = context.InlineFormattingContext.init(layout_box, layout_box.allocator);
    layout_box.formatting_context = new_ifc;
    ifc = new_ifc;

    const ifc_ptr = ifc.?;

    // 创建第一个行框
    var current_y: f32 = layout_box.box_model.padding.top;
    var current_line = try createLineBox(ifc_ptr, current_y, layout_box.allocator);
    var line_width: f32 = 0;
    var line_height: f32 = 0;

    // 布局行内元素
    for (layout_box.children.items) |child| {
        // 递归布局子元素（如果子元素有子元素）
        if (child.children.items.len > 0) {
            // TODO: 根据子元素的display类型选择不同的布局算法
            // 暂时简化处理
        }

        const child_width = child.box_model.totalSize().width;
        const child_height = child.box_model.totalSize().height;

        // 检查是否需要换行
        const available_width = containing_block.width - layout_box.box_model.padding.left - layout_box.box_model.padding.right;
        if (line_width + child_width > available_width and line_width > 0) {
            // 完成当前行
            current_line.rect.width = line_width;
            current_line.rect.height = line_height;
            current_line.baseline = line_height * 0.8; // 简化：基线在行高的80%处
            current_line.line_height = line_height;

            // 创建新行
            current_y += line_height;
            current_line = try createLineBox(ifc_ptr, current_y, layout_box.allocator);
            line_width = 0;
            line_height = 0;
        }

        // 添加到当前行
        child.box_model.content.x = layout_box.box_model.content.x + layout_box.box_model.padding.left + line_width;
        child.box_model.content.y = layout_box.box_model.content.y + current_line.rect.y;
        try current_line.inline_boxes.append(layout_box.allocator, child);

        line_width += child_width;
        line_height = @max(line_height, child_height);
    }

    // 完成最后一行
    if (current_line.inline_boxes.items.len > 0) {
        current_line.rect.width = line_width;
        current_line.rect.height = line_height;
        current_line.baseline = line_height * 0.8; // 简化：基线在行高的80%处
        current_line.line_height = line_height;
    } else {
        // 如果没有元素，删除空行框
        _ = ifc_ptr.line_boxes.pop();
        // 注意：line_boxes存储的是值，不需要destroy
    }

    // 计算容器高度
    var total_height: f32 = layout_box.box_model.padding.top;
    for (ifc_ptr.line_boxes.items) |line| {
        total_height += line.rect.height;
    }
    total_height += layout_box.box_model.padding.bottom;
    layout_box.box_model.content.height = total_height;

    // 返回IFC指针，用于测试中清理
    return ifc_ptr;
}
