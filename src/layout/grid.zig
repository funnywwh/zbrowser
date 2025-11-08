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

    // 计算列位置
    var x_offset: f32 = 0;
    column_positions.append(layout_box.allocator, 0) catch {
        layoutGridDefault(layout_box, containing_block);
        return;
    };
    if (grid_template_columns.items.len > 0) {
        for (grid_template_columns.items) |col_width| {
            x_offset += col_width;
            column_positions.append(layout_box.allocator, x_offset) catch {
                layoutGridDefault(layout_box, containing_block);
                return;
            };
        }
    } else {
        // 默认：平均分配
        const cell_width = layout_box.box_model.content.width / @as(f32, @floatFromInt(columns));
        var i: usize = 1;
        while (i <= columns) : (i += 1) {
            column_positions.append(layout_box.allocator, @as(f32, @floatFromInt(i)) * cell_width) catch {
                layoutGridDefault(layout_box, containing_block);
                return;
            };
        }
    }

    // 计算行位置
    var y_offset: f32 = 0;
    row_positions.append(layout_box.allocator, 0) catch {
        layoutGridDefault(layout_box, containing_block);
        return;
    };
    if (grid_template_rows.items.len > 0) {
        for (grid_template_rows.items) |row_height| {
            y_offset += row_height;
            row_positions.append(layout_box.allocator, y_offset) catch {
                layoutGridDefault(layout_box, containing_block);
                return;
            };
        }
    } else {
        // 默认：固定高度100px
        const cell_height: f32 = 100;
        var i: usize = 1;
        while (i <= rows) : (i += 1) {
            row_positions.append(layout_box.allocator, @as(f32, @floatFromInt(i)) * cell_height) catch {
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
        const width = if (col + 1 < column_positions.items.len)
            column_positions.items[col + 1] - column_positions.items[col]
        else
            layout_box.box_model.content.width - column_positions.items[col];
        const height = if (row + 1 < row_positions.items.len)
            row_positions.items[row + 1] - row_positions.items[row]
        else
            (if (row_positions.items.len > 0) row_positions.items[row_positions.items.len - 1] else 100);

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
