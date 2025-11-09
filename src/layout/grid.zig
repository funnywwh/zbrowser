const std = @import("std");
const box = @import("box");
const cascade = @import("cascade");
const css_parser = @import("parser");
const style_utils = @import("style_utils");

/// Grid布局算法
/// 处理CSS Grid布局（display: grid, inline-grid）
/// 执行Grid布局
/// 根据Grid规范计算grid容器和grid items的位置和尺寸
///
/// 参数：
/// - layout_box: Grid容器布局框
/// - containing_block: 包含块尺寸
/// - stylesheets: CSS样式表（用于获取Grid属性）
///
/// TODO: 简化实现 - 当前实现了基本的Grid布局，支持grid-template-rows/columns
/// 完整实现需要：
/// 1. 解析grid模板（repeat(), minmax(), fr单位等）
/// 2. 处理grid items的放置（grid-row, grid-column, grid-area）
/// 3. 处理自动放置算法（auto-placement）
/// 4. 处理gap（row-gap, column-gap）
/// 5. 处理对齐（justify-items, align-items, justify-content, align-content）
/// 参考：CSS Grid Layout Module Level 1
pub fn layoutGrid(layout_box: *box.LayoutBox, containing_block: box.Size, stylesheets: []const css_parser.Stylesheet) void {
    // 计算样式以获取Grid属性
    var cascade_engine = cascade.Cascade.init(layout_box.allocator);
    var computed_style = cascade_engine.computeStyle(layout_box.node, stylesheets) catch {
        // 如果计算样式失败，使用默认值
        layoutGridDefault(layout_box, containing_block);
        return;
    };
    defer computed_style.deinit();

    // 获取Grid属性
    var grid_template_rows = style_utils.getGridTemplateRows(&computed_style, layout_box.allocator) catch {
        layoutGridDefault(layout_box, containing_block);
        return;
    };
    defer grid_template_rows.deinit(layout_box.allocator);

    var grid_template_columns = style_utils.getGridTemplateColumns(&computed_style, layout_box.allocator) catch {
        layoutGridDefault(layout_box, containing_block);
        return;
    };
    defer grid_template_columns.deinit(layout_box.allocator);
    
    // 获取gap属性
    const row_gap = style_utils.getRowGap(&computed_style, containing_block.height);
    const column_gap = style_utils.getColumnGap(&computed_style, containing_block.width);

    // 标记容器为已布局
    layout_box.is_layouted = true;

    const items_count = layout_box.children.items.len;
    if (items_count == 0) {
        return;
    }

    const container_x = layout_box.box_model.content.x;
    const container_y = layout_box.box_model.content.y;

    // 计算列数和行数
    const columns = if (grid_template_columns.items.len > 0) grid_template_columns.items.len else 2;
    const calculated_rows = if (items_count == 0) 0 else (items_count + columns - 1) / columns;
    const rows = if (grid_template_rows.items.len > 0) grid_template_rows.items.len else @max(@as(usize, 1), calculated_rows);

    // 计算网格线位置
    var column_positions = std.ArrayList(f32){
        .items = &[_]f32{},
        .capacity = 0,
    };
    defer column_positions.deinit(layout_box.allocator);
    var row_positions = std.ArrayList(f32){
        .items = &[_]f32{},
        .capacity = 0,
    };
    defer row_positions.deinit(layout_box.allocator);

    // 计算列位置（考虑gap）
    // column_positions存储每列的起始位置（不包括gap）
    var x_offset: f32 = 0;
    column_positions.append(layout_box.allocator, 0) catch {
        layoutGridDefault(layout_box, containing_block);
        return;
    };
    if (grid_template_columns.items.len > 0) {
        for (grid_template_columns.items, 0..) |col_width, i| {
            // 下一列的起始位置 = 当前列的起始位置 + 当前列宽 + gap
            if (i < grid_template_columns.items.len - 1) {
                x_offset += col_width + column_gap;
            } else {
                // 最后一列后不加gap
                x_offset += col_width;
            }
            column_positions.append(layout_box.allocator, x_offset) catch {
                layoutGridDefault(layout_box, containing_block);
                return;
            };
        }
    } else {
        // 默认：平均分配（考虑gap）
        const total_gap = column_gap * @as(f32, @floatFromInt(columns - 1));
        const available_width = layout_box.box_model.content.width - total_gap;
        const cell_width = available_width / @as(f32, @floatFromInt(columns));
        var i: usize = 1;
        while (i <= columns) : (i += 1) {
            x_offset = @as(f32, @floatFromInt(i - 1)) * (cell_width + column_gap) + cell_width;
            column_positions.append(layout_box.allocator, x_offset) catch {
                layoutGridDefault(layout_box, containing_block);
                return;
            };
        }
    }

    // 计算行位置（考虑gap）
    // row_positions存储每行的起始位置（不包括gap）
    var y_offset: f32 = 0;
    row_positions.append(layout_box.allocator, 0) catch {
        layoutGridDefault(layout_box, containing_block);
        return;
    };
    if (grid_template_rows.items.len > 0) {
        for (grid_template_rows.items, 0..) |row_height, i| {
            // 下一行的起始位置 = 当前行的起始位置 + 当前行高 + gap
            if (i < grid_template_rows.items.len - 1) {
                y_offset += row_height + row_gap;
            } else {
                // 最后一行后不加gap
                y_offset += row_height;
            }
            row_positions.append(layout_box.allocator, y_offset) catch {
                layoutGridDefault(layout_box, containing_block);
                return;
            };
        }
    } else {
        // 默认：固定高度100px（考虑gap）
        const cell_height: f32 = 100;
        var i: usize = 1;
        while (i <= rows) : (i += 1) {
            y_offset = @as(f32, @floatFromInt(i - 1)) * (cell_height + row_gap) + cell_height;
            row_positions.append(layout_box.allocator, y_offset) catch {
                layoutGridDefault(layout_box, containing_block);
                return;
            };
        }
    }

    // 放置items
    var row: usize = 0;
    var col: usize = 0;

    for (layout_box.children.items) |child| {
        // 计算网格位置
        const x = container_x + column_positions.items[col];
        const y = container_y + row_positions.items[row];

        // 计算尺寸
        // column_positions存储每列的起始位置（不包括gap）
        // 宽度 = 下一列的起始位置 - 当前列的起始位置 - gap（如果有下一列）
        const width = if (col + 1 < column_positions.items.len)
            column_positions.items[col + 1] - column_positions.items[col] - column_gap
        else
            layout_box.box_model.content.width - column_positions.items[col];
        // row_positions存储每行的起始位置（不包括gap）
        // 高度 = 下一行的起始位置 - 当前行的起始位置 - gap（如果有下一行）
        const height = if (row + 1 < row_positions.items.len)
            row_positions.items[row + 1] - row_positions.items[row] - row_gap
        else
            (if (row_positions.items.len > 0) layout_box.box_model.content.height - row_positions.items[row] else 100);

        // 设置子元素位置和尺寸
        child.box_model.content.x = x;
        child.box_model.content.y = y;
        child.box_model.content.width = width;
        child.box_model.content.height = height;

        // 更新网格位置
        col += 1;
        if (col >= columns) {
            col = 0;
            row += 1;
        }

        // 标记子元素为已布局
        child.is_layouted = true;
    }
}

/// 使用默认值的Grid布局（当样式计算失败时）
fn layoutGridDefault(layout_box: *box.LayoutBox, containing_block: box.Size) void {
    _ = containing_block;
    layout_box.is_layouted = true;

    const items_count = layout_box.children.items.len;
    if (items_count == 0) {
        return;
    }

    const columns = 2;
    const container_x = layout_box.box_model.content.x;
    const container_y = layout_box.box_model.content.y;
    const cell_width = layout_box.box_model.content.width / @as(f32, @floatFromInt(columns));
    const cell_height: f32 = 100;

    var row: usize = 0;
    var col: usize = 0;

    for (layout_box.children.items) |child| {
        const x = container_x + @as(f32, @floatFromInt(col)) * cell_width;
        const y = container_y + @as(f32, @floatFromInt(row)) * cell_height;
        child.box_model.content.x = x;
        child.box_model.content.y = y;
        col += 1;
        if (col >= columns) {
            col = 0;
            row += 1;
        }
        child.is_layouted = true;
    }
}
