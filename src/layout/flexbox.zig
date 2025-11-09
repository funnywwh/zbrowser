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
    _ = style_utils.getFlexWrap(&computed_style); // TODO: 实现换行
    const justify_content = style_utils.getJustifyContent(&computed_style);
    const align_items = style_utils.getAlignItems(&computed_style);
    _ = style_utils.getAlignContent(&computed_style); // TODO: 实现多行对齐

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

    // 计算flex尺寸（考虑flex-grow）
    calculateFlexSizes(&flex_items, container_main_size, is_row);

    // 应用justify-content对齐（主轴对齐）
    const container_main_pos = if (is_row) layout_box.box_model.content.x else layout_box.box_model.content.y;
    applyJustifyContent(&flex_items, container_main_size, container_main_pos, justify_content, is_row, is_reverse);

    // 应用align-items对齐（交叉轴对齐，单行）
    const container_cross_pos = if (is_row) layout_box.box_model.content.y else layout_box.box_model.content.x;
    applyAlignItems(&flex_items, container_cross_size, container_cross_pos, align_items, is_row);

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

/// 计算flex items的最终尺寸（考虑flex-grow）
fn calculateFlexSizes(flex_items: *std.ArrayList(FlexItem), container_main_size: f32, is_row: bool) void {
    // 计算所有items的基础尺寸总和
    var total_base_size: f32 = 0;
    var total_grow: f32 = 0;
    
    for (flex_items.items) |*item| {
        total_base_size += item.base_main_size;
        total_grow += item.flex_props.grow;
    }

    // 计算剩余空间
    const free_space = container_main_size - total_base_size;

    // 如果有剩余空间且total_grow > 0，分配剩余空间
    if (free_space > 0 and total_grow > 0) {
        for (flex_items.items) |*item| {
            if (item.flex_props.grow > 0) {
                const grow_ratio = item.flex_props.grow / total_grow;
                const extra_size = free_space * grow_ratio;
                item.final_main_size = item.base_main_size + extra_size;
            } else {
                item.final_main_size = item.base_main_size;
            }
        }
    } else {
        // 没有剩余空间或没有grow，使用基础尺寸
        for (flex_items.items) |*item| {
            item.final_main_size = item.base_main_size;
        }
    }

    // 应用最终尺寸到layout_box
    for (flex_items.items) |*item| {
        if (is_row) {
            item.layout_box.box_model.content.width = item.final_main_size;
        } else {
            item.layout_box.box_model.content.height = item.final_main_size;
        }
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
