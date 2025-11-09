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
    const align_items = style_utils.getAlignItems(&computed_style);
    const align_content = style_utils.getAlignContent(&computed_style);

    // 确定主轴方向
    const is_row = flex_direction == .row or flex_direction == .row_reverse;
    const is_reverse = flex_direction == .row_reverse or flex_direction == .column_reverse;

    // 标记容器为已布局
    layout_box.is_layouted = true;

    // 如果没有子元素，直接返回
    if (layout_box.children.items.len == 0) {
        return;
    }

    // 计算每个flex item的样式和属性
    var cascade_engine_items = cascade.Cascade.init(layout_box.allocator);

    // 收集所有flex items的属性和基础尺寸
    var flex_items = std.ArrayList(FlexItem){};
    defer flex_items.deinit(layout_box.allocator);
    
    const container_main_size = if (is_row) layout_box.box_model.content.width else layout_box.box_model.content.height;
    const container_cross_size = if (is_row) layout_box.box_model.content.height else layout_box.box_model.content.width;

    for (layout_box.children.items) |child| {
        // 计算子元素的样式
        var child_computed_style = cascade_engine_items.computeStyle(child.node, stylesheets) catch {
            // 如果计算失败，使用默认值
            flex_items.append(layout_box.allocator, FlexItem{
                .layout_box = child,
                .flex_props = .{ .grow = 0.0, .shrink = 1.0, .basis = null },
                .base_main_size = if (is_row) child.box_model.content.width else child.box_model.content.height,
                .base_cross_size = if (is_row) child.box_model.content.height else child.box_model.content.width,
            }) catch {
                // 如果append失败，跳过这个item
                continue;
            };
            continue;
        };
        defer child_computed_style.deinit();

        // 获取flex属性
        const flex_props = style_utils.getFlexProperties(&child_computed_style, container_main_size);
        
        // 计算基础尺寸（main size和cross size）
        const base_main_size = if (is_row) child.box_model.content.width else child.box_model.content.height;
        const base_cross_size = if (is_row) child.box_model.content.height else child.box_model.content.width;

        flex_items.append(layout_box.allocator, FlexItem{
            .layout_box = child,
            .flex_props = flex_props,
            .base_main_size = base_main_size,
            .base_cross_size = base_cross_size,
        }) catch {
            // 如果append失败，跳过这个item
            continue;
        };
    }

    // 根据flex-wrap决定是否换行
    if (flex_wrap == .nowrap) {
        // 不换行：所有items在一行
        layoutFlexboxSingleLine(&flex_items, container_main_size, container_cross_size, is_row, is_reverse, justify_content, align_items, layout_box);
    } else {
        // 换行：将items分成多行
        layoutFlexboxMultiLine(&flex_items, container_main_size, container_cross_size, is_row, is_reverse, flex_wrap, justify_content, align_items, align_content, layout_box);
    }

    // 标记所有子元素为已布局
    for (flex_items.items) |*item| {
        item.layout_box.is_layouted = true;
    }
}

/// Flex item数据结构
const FlexItem = struct {
    layout_box: *box.LayoutBox,
    flex_props: style_utils.FlexItemProperties,
    base_main_size: f32,
    base_cross_size: f32,
    final_main_size: f32 = 0,
    final_cross_size: f32 = 0,
};

/// Flex line数据结构（用于多行布局）
const FlexLine = struct {
    items: std.ArrayList(*FlexItem),
    main_size: f32 = 0, // 主轴尺寸
    cross_size: f32 = 0, // 交叉轴尺寸
    cross_start: f32 = 0, // 交叉轴起始位置
};

/// 计算flex items的最终尺寸（考虑flex-grow, flex-shrink, flex-basis）
/// TODO: 简化实现 - 当前实现了基本的flex-grow和flex-shrink计算
/// 完整实现需要：
/// 1. 正确处理flex-basis（包括auto、0、百分比等）
/// 2. 处理min-width/min-height和max-width/max-height约束
/// 3. 处理负的剩余空间（flex-shrink）
fn calculateFlexSizes(flex_items: *std.ArrayList(FlexItem), container_main_size: f32, is_row: bool) void {
    // 第一步：计算每个item的假设主轴尺寸（hypothetical main size）
    // 如果flex-basis不为null，使用flex-basis；否则使用base_main_size
    for (flex_items.items) |*item| {
        if (item.flex_props.basis) |basis| {
            // 使用flex-basis作为假设主轴尺寸
            item.final_main_size = basis;
        } else {
            // flex-basis为auto，使用基础尺寸
            item.final_main_size = item.base_main_size;
        }
    }

    // 第二步：计算所有items的总尺寸
    var total_size: f32 = 0;
    for (flex_items.items) |*item| {
        total_size += item.final_main_size;
    }

    // 第三步：计算剩余空间
    const free_space = container_main_size - total_size;

    // 第四步：根据剩余空间的正负，应用flex-grow或flex-shrink
    if (free_space > 0) {
        // 有剩余空间，应用flex-grow
        var total_grow: f32 = 0;
        for (flex_items.items) |*item| {
            total_grow += item.flex_props.grow;
        }

        if (total_grow > 0) {
            // 按比例分配剩余空间
            for (flex_items.items) |*item| {
                if (item.flex_props.grow > 0) {
                    const grow_ratio = item.flex_props.grow / total_grow;
                    const extra_size = free_space * grow_ratio;
                    item.final_main_size += extra_size;
                }
            }
        }
    } else if (free_space < 0) {
        // 空间不足，应用flex-shrink
        // 计算总的shrink factor（每个item的shrink factor = shrink * 假设主轴尺寸）
        var total_shrink_factor: f32 = 0;
        for (flex_items.items) |*item| {
            if (item.flex_props.shrink > 0) {
                total_shrink_factor += item.flex_props.shrink * item.final_main_size;
            }
        }

        if (total_shrink_factor > 0) {
            // 按比例收缩
            const negative_space = -free_space; // 需要收缩的总量
            for (flex_items.items) |*item| {
                if (item.flex_props.shrink > 0) {
                    const shrink_factor = item.flex_props.shrink * item.final_main_size;
                    const shrink_ratio = shrink_factor / total_shrink_factor;
                    const shrink_amount = negative_space * shrink_ratio;
                    item.final_main_size -= shrink_amount;
                    // 确保尺寸不为负
                    if (item.final_main_size < 0) {
                        item.final_main_size = 0;
                    }
                }
            }
        }
    }
    // 如果free_space == 0，不需要调整

    // 第五步：应用最终尺寸到layout_box
    for (flex_items.items) |*item| {
        if (is_row) {
            item.layout_box.box_model.content.width = item.final_main_size;
        } else {
            item.layout_box.box_model.content.height = item.final_main_size;
        }
    }
}

/// 单行Flexbox布局（不换行）
fn layoutFlexboxSingleLine(
    flex_items: *std.ArrayList(FlexItem),
    container_main_size: f32,
    container_cross_size: f32,
    is_row: bool,
    is_reverse: bool,
    justify_content: style_utils.JustifyContent,
    align_items: style_utils.AlignItems,
    layout_box: *box.LayoutBox,
) void {
    // 计算flex尺寸
    calculateFlexSizes(flex_items, container_main_size, is_row);

    // 应用justify-content对齐（主轴对齐）
    const container_main_pos = if (is_row) layout_box.box_model.content.x else layout_box.box_model.content.y;
    applyJustifyContent(flex_items, container_main_size, container_main_pos, justify_content, is_row, is_reverse);

    // 应用align-items对齐（交叉轴对齐）
    const container_cross_pos = if (is_row) layout_box.box_model.content.y else layout_box.box_model.content.x;
    applyAlignItems(flex_items, container_cross_size, container_cross_pos, align_items, is_row);
}

/// 多行Flexbox布局（换行）
/// TODO: 简化实现 - 当前实现了基本的换行功能
/// 完整实现需要：
/// 1. 正确处理wrap-reverse
/// 2. 实现align-content多行对齐
/// 3. 处理每行的交叉轴尺寸计算
fn layoutFlexboxMultiLine(
    flex_items: *std.ArrayList(FlexItem),
    container_main_size: f32,
    container_cross_size: f32,
    is_row: bool,
    is_reverse: bool,
    flex_wrap: style_utils.FlexWrap,
    justify_content: style_utils.JustifyContent,
    align_items: style_utils.AlignItems,
    align_content: style_utils.AlignContent,
    layout_box: *box.LayoutBox,
) void {
    // 第一步：将items分成多个flex lines
    var flex_lines = std.ArrayList(FlexLine){};
    defer {
        for (flex_lines.items) |*line| {
            line.items.deinit(layout_box.allocator);
        }
        flex_lines.deinit(layout_box.allocator);
    }
    
    createFlexLines(&flex_lines, flex_items, container_main_size, is_row, layout_box.allocator);

    // 第二步：对每个flex line计算尺寸和对齐
    for (flex_lines.items) |*line| {
        // 创建一个临时的FlexItem数组用于计算（因为calculateFlexSizes需要*std.ArrayList(FlexItem)）
        var line_items = std.ArrayList(FlexItem){};
        defer line_items.deinit(layout_box.allocator);
        
        // 将line.items中的指针解引用并复制到line_items
        for (line.items.items) |item_ptr| {
            line_items.append(layout_box.allocator, item_ptr.*) catch continue;
        }
        
        // 计算这一行的flex尺寸
        calculateFlexSizes(&line_items, container_main_size, is_row);
        
        // 将计算结果同步回line.items（通过layout_box更新）
        // 注意：calculateFlexSizes已经直接更新了layout_box的尺寸，所以不需要同步
        // 只需要更新FlexItem结构中的final_main_size等字段
        for (line.items.items, line_items.items) |item_ptr, updated_item| {
            // item_ptr是*FlexItem，需要解引用才能访问字段
            item_ptr.flex_props = updated_item.flex_props;
            item_ptr.base_main_size = updated_item.base_main_size;
            item_ptr.base_cross_size = updated_item.base_cross_size;
            item_ptr.final_main_size = updated_item.final_main_size;
            item_ptr.final_cross_size = updated_item.final_cross_size;
            // layout_box已经在calculateFlexSizes中更新了，不需要再次更新
        }

        // 应用justify-content对齐（主轴对齐）
        const container_main_pos = if (is_row) layout_box.box_model.content.x else layout_box.box_model.content.y;
        // 创建一个临时的FlexItem数组用于对齐计算
        var line_items_for_justify = std.ArrayList(FlexItem){};
        defer line_items_for_justify.deinit(layout_box.allocator);
        for (line.items.items) |item_ptr| {
            line_items_for_justify.append(layout_box.allocator, item_ptr.*) catch continue;
        }
        applyJustifyContent(&line_items_for_justify, container_main_size, container_main_pos, justify_content, is_row, is_reverse);
        // justify-content已经直接更新了layout_box的位置，不需要同步

        // 计算这一行的交叉轴尺寸（取最大item的交叉轴尺寸）
        var max_cross_size: f32 = 0;
        for (line.items.items) |item| {
            const item_cross_size = if (is_row) item.layout_box.box_model.content.height else item.layout_box.box_model.content.width;
            max_cross_size = @max(max_cross_size, item_cross_size);
        }
        line.cross_size = max_cross_size;

        // 应用align-items对齐（交叉轴对齐）
        const container_cross_pos = if (is_row) layout_box.box_model.content.y else layout_box.box_model.content.x;
        // 创建一个临时的FlexItem数组用于对齐计算
        var line_items_for_align = std.ArrayList(FlexItem){};
        defer line_items_for_align.deinit(layout_box.allocator);
        for (line.items.items) |item_ptr| {
            line_items_for_align.append(layout_box.allocator, item_ptr.*) catch continue;
        }
        applyAlignItems(&line_items_for_align, line.cross_size, container_cross_pos, align_items, is_row);
        // align-items已经直接更新了layout_box的位置和尺寸，不需要同步
    }

    // 第三步：计算每行的交叉轴位置（应用align-content）
    applyAlignContent(&flex_lines, container_cross_size, is_row, align_content, flex_wrap, layout_box);
}

/// 创建flex lines（将items分成多行）
fn createFlexLines(
    flex_lines: *std.ArrayList(FlexLine),
    flex_items: *std.ArrayList(FlexItem),
    container_main_size: f32,
    _: bool, // is_row 暂时未使用
    allocator: std.mem.Allocator,
) void {
    var current_line = FlexLine{
        .items = std.ArrayList(*FlexItem){},
        .main_size = 0,
        .cross_size = 0,
        .cross_start = 0,
    };

    for (flex_items.items) |*item| {
        // 计算item的假设主轴尺寸（用于判断是否需要换行）
        const item_main_size = if (item.flex_props.basis) |basis| basis else item.base_main_size;

        // 检查是否需要换行
        if (current_line.items.items.len > 0 and current_line.main_size + item_main_size > container_main_size) {
            // 完成当前行
            flex_lines.append(allocator, current_line) catch {
                current_line.items.deinit(allocator);
                return;
            };

            // 创建新行
            current_line.items.deinit(allocator);
            current_line = FlexLine{
                .items = std.ArrayList(*FlexItem){},
                .main_size = 0,
                .cross_size = 0,
                .cross_start = 0,
            };
        }

        // 添加到当前行
        current_line.items.append(allocator, item) catch {
            current_line.items.deinit(allocator);
            return;
        };
        current_line.main_size += item_main_size;
    }

    // 添加最后一行
    if (current_line.items.items.len > 0) {
        flex_lines.append(allocator, current_line) catch {
            current_line.items.deinit(allocator);
        };
    }
}

/// 应用align-content对齐（多行对齐）
fn applyAlignContent(
    flex_lines: *std.ArrayList(FlexLine),
    container_cross_size: f32,
    is_row: bool,
    align_content: style_utils.AlignContent,
    _: style_utils.FlexWrap, // flex_wrap 暂时未使用（wrap-reverse待实现）
    layout_box: *box.LayoutBox,
) void {
    if (flex_lines.items.len == 0) {
        return;
    }

    // 计算所有行的总交叉轴尺寸
    var total_cross_size: f32 = 0;
    for (flex_lines.items) |*line| {
        total_cross_size += line.cross_size;
    }

    // 计算剩余空间
    const free_space = container_cross_size - total_cross_size;

    // 计算每行的交叉轴起始位置
    var cross_offset: f32 = 0;
    const container_cross_pos = if (is_row) layout_box.box_model.content.y else layout_box.box_model.content.x;

    switch (align_content) {
        .flex_start => {
            cross_offset = 0;
        },
        .flex_end => {
            cross_offset = free_space;
        },
        .center => {
            cross_offset = free_space / 2.0;
        },
        .space_between => {
            if (flex_lines.items.len > 1) {
                const gap = free_space / @as(f32, @floatFromInt(flex_lines.items.len - 1));
                for (flex_lines.items, 0..) |*line, i| {
                    line.cross_start = container_cross_pos + cross_offset;
                    if (i < flex_lines.items.len - 1) {
                        cross_offset += line.cross_size + gap;
                    }
                }
                return;
            } else {
                cross_offset = 0;
            }
        },
        .space_around => {
            if (flex_lines.items.len > 0) {
                const gap = free_space / @as(f32, @floatFromInt(flex_lines.items.len));
                cross_offset = gap / 2.0;
                for (flex_lines.items) |*line| {
                    line.cross_start = container_cross_pos + cross_offset;
                    cross_offset += line.cross_size + gap;
                }
                return;
            }
        },
        .space_evenly => {
            if (flex_lines.items.len > 0) {
                const gap = free_space / @as(f32, @floatFromInt(flex_lines.items.len + 1));
                cross_offset = gap;
                for (flex_lines.items) |*line| {
                    line.cross_start = container_cross_pos + cross_offset;
                    cross_offset += line.cross_size + gap;
                }
                return;
            }
        },
        .stretch => {
            // stretch: 每行拉伸到填满容器
            if (flex_lines.items.len > 0) {
                const stretched_size = container_cross_size / @as(f32, @floatFromInt(flex_lines.items.len));
                for (flex_lines.items) |*line| {
                    line.cross_size = stretched_size;
                    line.cross_start = container_cross_pos + cross_offset;
                    cross_offset += stretched_size;
                }
                return;
            }
        },
    }

    // 应用交叉轴位置到每行的items
    for (flex_lines.items) |*line| {
        line.cross_start = container_cross_pos + cross_offset;
        for (line.items.items) |item| {
            if (is_row) {
                item.layout_box.box_model.content.y = line.cross_start;
            } else {
                item.layout_box.box_model.content.x = line.cross_start;
            }
        }
        cross_offset += line.cross_size;
    }
}

/// 应用justify-content对齐（主轴对齐）
fn applyJustifyContent(
    flex_items: *std.ArrayList(FlexItem),
    container_main_size: f32,
    container_main_pos: f32,
    justify_content: style_utils.JustifyContent,
    is_row: bool,
    is_reverse: bool,
) void {
    // 计算所有items的总尺寸
    var total_items_size: f32 = 0;
    for (flex_items.items) |*item| {
        total_items_size += item.final_main_size;
    }

    // 计算剩余空间
    const free_space = container_main_size - total_items_size;

    // 计算起始位置
    var main_offset: f32 = 0;
    switch (justify_content) {
        .flex_start => {
            main_offset = 0;
        },
        .flex_end => {
            main_offset = free_space;
        },
        .center => {
            main_offset = free_space / 2.0;
        },
        .space_between => {
            if (flex_items.items.len > 1) {
                const gap = free_space / @as(f32, @floatFromInt(flex_items.items.len - 1));
                // 第一个item从0开始，后续item之间有gap
                var current_offset: f32 = 0;
                for (flex_items.items, 0..) |*item, i| {
                    if (i > 0) {
                        current_offset += flex_items.items[i - 1].final_main_size + gap;
                    }
                    if (is_row) {
                        item.layout_box.box_model.content.x = container_main_pos + current_offset;
                    } else {
                        item.layout_box.box_model.content.y = container_main_pos + current_offset;
                    }
                }
                return;
            } else {
                main_offset = 0;
            }
        },
        .space_around => {
            if (flex_items.items.len > 0) {
                const gap = free_space / @as(f32, @floatFromInt(flex_items.items.len));
                var current_offset: f32 = gap / 2.0;
                for (flex_items.items) |*item| {
                    if (is_row) {
                        item.layout_box.box_model.content.x = container_main_pos + current_offset;
                    } else {
                        item.layout_box.box_model.content.y = container_main_pos + current_offset;
                    }
                    current_offset += item.final_main_size + gap;
                }
                return;
            }
        },
        .space_evenly => {
            if (flex_items.items.len > 0) {
                const gap = free_space / @as(f32, @floatFromInt(flex_items.items.len + 1));
                var current_offset: f32 = gap;
                for (flex_items.items) |*item| {
                    if (is_row) {
                        item.layout_box.box_model.content.x = container_main_pos + current_offset;
                    } else {
                        item.layout_box.box_model.content.y = container_main_pos + current_offset;
                    }
                    current_offset += item.final_main_size + gap;
                }
                return;
            }
        },
    }

    // 应用位置（flex-start, flex-end, center）
    var current_offset = main_offset;
    if (is_reverse) {
        // 反向：从右到左（或从下到上）
        current_offset = container_main_size - main_offset;
        for (flex_items.items) |*item| {
            current_offset -= item.final_main_size;
            if (is_row) {
                item.layout_box.box_model.content.x = container_main_pos + current_offset;
            } else {
                item.layout_box.box_model.content.y = container_main_pos + current_offset;
            }
        }
    } else {
        // 正向：从左到右（或从上到下）
        for (flex_items.items) |*item| {
            if (is_row) {
                item.layout_box.box_model.content.x = container_main_pos + current_offset;
            } else {
                item.layout_box.box_model.content.y = container_main_pos + current_offset;
            }
            current_offset += item.final_main_size;
        }
    }
}

/// 应用align-items对齐（交叉轴对齐，单行）
fn applyAlignItems(
    flex_items: *std.ArrayList(FlexItem),
    container_cross_size: f32,
    container_cross_pos: f32,
    align_items: style_utils.AlignItems,
    is_row: bool,
) void {
    for (flex_items.items) |*item| {
        var cross_offset: f32 = 0;
        
        switch (align_items) {
            .flex_start => {
                cross_offset = 0;
            },
            .flex_end => {
                cross_offset = container_cross_size - item.final_cross_size;
            },
            .center => {
                cross_offset = (container_cross_size - item.final_cross_size) / 2.0;
            },
            .baseline => {
                // TODO: 实现baseline对齐
                cross_offset = 0;
            },
            .stretch => {
                // stretch：拉伸到容器高度
                item.final_cross_size = container_cross_size;
                if (is_row) {
                    item.layout_box.box_model.content.height = item.final_cross_size;
                } else {
                    item.layout_box.box_model.content.width = item.final_cross_size;
                }
                cross_offset = 0;
            },
        }

        // 应用交叉轴位置
        if (is_row) {
            item.layout_box.box_model.content.y = container_cross_pos + cross_offset;
        } else {
            item.layout_box.box_model.content.x = container_cross_pos + cross_offset;
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
