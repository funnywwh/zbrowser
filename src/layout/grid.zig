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

    // 获取对齐属性
    const justify_items = style_utils.getGridJustifyItems(&computed_style);
    const align_items = style_utils.getGridAlignItems(&computed_style);
    const justify_content = style_utils.getGridJustifyContent(&computed_style);
    const align_content = style_utils.getGridAlignContent(&computed_style);
    std.log.warn("[Grid] layoutGrid - align_content={}", .{align_content});

    // 标记容器为已布局
    layout_box.is_layouted = true;

    const items_count = layout_box.children.items.len;
    if (items_count == 0) {
        return;
    }

    const container_x = layout_box.box_model.content.x;
    const container_y = layout_box.box_model.content.y;

    // 计算列数和行数
    std.log.warn("[Grid] layoutGrid - grid_template_columns.items.len={d}", .{grid_template_columns.items.len});
    const columns = if (grid_template_columns.items.len > 0) grid_template_columns.items.len else 2;
    std.log.warn("[Grid] layoutGrid - columns={d}", .{columns});
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
    // column_positions存储每列的起始位置（包括gap的累积位置）
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
    // row_positions存储每行的起始位置（包括gap的累积位置）
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

    // 应用justify-content和align-content（调整整个grid的位置）
    const grid_offset = applyGridContentAlignment(
        &column_positions,
        &row_positions,
        layout_box.box_model.content.width,
        layout_box.box_model.content.height,
        justify_content,
        align_content,
        column_gap,
        row_gap,
        layout_box.allocator,
    ) catch {
        layoutGridDefault(layout_box, containing_block);
        return;
    };

    // 放置items
    var row: usize = 0;
    var col: usize = 0;

    for (layout_box.children.items) |child| {
        // 检查是否有显式指定的grid-row和grid-column
        var use_explicit_position = false;
        var item_row: usize = 0;
        var item_col: usize = 0;
        var item_row_span: usize = 1;
        var item_col_span: usize = 1;

        // 检查grid-row
        if (child.grid_row_start) |row_start| {
            // Grid行号从1开始，转换为数组索引（从0开始）
            if (row_start > 0 and row_start <= row_positions.items.len) {
                item_row = row_start - 1;
                use_explicit_position = true;
                // 检查是否有结束位置
                if (child.grid_row_end) |row_end| {
                    if (row_end > row_start and row_end <= row_positions.items.len + 1) {
                        item_row_span = row_end - row_start;
                    }
                }
            } else {
                std.log.warn("[Grid] layoutGrid - grid-row-start={d}超出范围! row_positions.len={d}, 使用自动放置", .{ row_start, row_positions.items.len });
            }
        }

        // 检查grid-column
        if (child.grid_column_start) |col_start| {
            // Grid列号从1开始，转换为数组索引（从0开始）
            if (col_start > 0 and col_start <= column_positions.items.len) {
                item_col = col_start - 1;
                use_explicit_position = true;
                // 检查是否有结束位置
                if (child.grid_column_end) |col_end| {
                    if (col_end > col_start and col_end <= column_positions.items.len + 1) {
                        item_col_span = col_end - col_start;
                    }
                }
            } else {
                std.log.warn("[Grid] layoutGrid - grid-column-start={d}超出范围! column_positions.len={d}, 使用自动放置", .{ col_start, column_positions.items.len });
            }
        }

        // 如果没有显式指定位置，使用自动放置
        if (!use_explicit_position) {
            // 边界检查：确保row和col在有效范围内
            if (row >= row_positions.items.len) {
                std.log.warn("[Grid] layoutGrid - row={d}超出范围! row_positions.len={d}, 跳过item", .{ row, row_positions.items.len });
                child.is_layouted = true;
                continue;
            }
            if (col >= column_positions.items.len) {
                std.log.warn("[Grid] layoutGrid - col={d}超出范围! column_positions.len={d}, 重置col=0, row+1", .{ col, column_positions.items.len });
                col = 0;
                row += 1;
                if (row >= row_positions.items.len) {
                    std.log.warn("[Grid] layoutGrid - row={d}超出范围! row_positions.len={d}, 跳过item", .{ row, row_positions.items.len });
                    child.is_layouted = true;
                    continue;
                }
            }
            item_row = row;
            item_col = col;
        }

        // 边界检查：确保item_row和item_col在有效范围内
        if (item_row >= row_positions.items.len) {
            std.log.warn("[Grid] layoutGrid - item_row={d}超出范围! row_positions.len={d}, 跳过item", .{ item_row, row_positions.items.len });
            child.is_layouted = true;
            continue;
        }
        if (item_col >= column_positions.items.len) {
            std.log.warn("[Grid] layoutGrid - item_col={d}超出范围! column_positions.len={d}, 跳过item", .{ item_col, column_positions.items.len });
            child.is_layouted = true;
            continue;
        }

        // 计算网格cell的位置和尺寸
        const cell_x = container_x + column_positions.items[item_col] + grid_offset.x;
        const cell_y = container_y + row_positions.items[item_row] + grid_offset.y;
        std.log.warn("[Grid] layoutGrid - placing item: row={d}, col={d}, row_span={d}, col_span={d}, row_positions[{d}]={d}, cell_y={d}, container_y={d}, grid_offset.y={d}", .{ item_row, item_col, item_row_span, item_col_span, item_row, row_positions.items[item_row], cell_y, container_y, grid_offset.y });

        // 计算cell尺寸（考虑跨越的行/列）
        // column_positions存储每列的起始位置（包括gap的累积位置）
        // 宽度 = 结束列的起始位置 - 起始列的起始位置 - gap（如果有结束列）
        const end_col = @min(item_col + item_col_span, column_positions.items.len);
        const cell_width = if (end_col < column_positions.items.len)
            column_positions.items[end_col] - column_positions.items[item_col] - column_gap
        else if (column_positions.items.len > 0)
            layout_box.box_model.content.width - column_positions.items[item_col] - grid_offset.x
        else
            100.0; // 默认值
        // row_positions存储每行的起始位置（包括gap的累积位置）
        // 高度 = 结束行的起始位置 - 起始行的起始位置 - gap（如果有结束行）
        const end_row = @min(item_row + item_row_span, row_positions.items.len);
        const cell_height = if (end_row < row_positions.items.len)
            row_positions.items[end_row] - row_positions.items[item_row] - row_gap
        else if (row_positions.items.len > 0)
            layout_box.box_model.content.height - row_positions.items[item_row] - grid_offset.y
        else
            100.0; // 默认值

        // 保存item的原始尺寸（用于对齐计算）
        const original_width = child.box_model.content.width;
        const original_height = child.box_model.content.height;

        // 应用justify-items和align-items（调整item在cell内的位置）
        const item_pos = applyGridItemAlignment(
            original_width,
            original_height,
            cell_width,
            cell_height,
            justify_items,
            align_items,
        );

        // 设置子元素位置和尺寸
        child.box_model.content.x = cell_x + item_pos.x;
        child.box_model.content.y = cell_y + item_pos.y;
        std.log.warn("[Grid] layoutGrid - item placed: child.box_model.content.y={d} (cell_y={d} + item_pos.y={d})", .{ child.box_model.content.y, cell_y, item_pos.y });
        // 如果stretch，使用cell尺寸；否则使用item的原始尺寸
        if (justify_items == .stretch) {
            child.box_model.content.width = cell_width;
        } else {
            child.box_model.content.width = original_width;
        }
        if (align_items == .stretch) {
            child.box_model.content.height = cell_height;
        } else {
            child.box_model.content.height = original_height;
        }

        // 更新网格位置（仅用于自动放置）
        if (!use_explicit_position) {
            col += 1;
            if (col >= columns) {
                col = 0;
                row += 1;
            }
        }
        std.log.warn("[Grid] layoutGrid - after update: row={d}, col={d}, columns={d}", .{ row, col, columns });

        // 标记子元素为已布局
        child.is_layouted = true;
    }
}

/// Grid偏移量结构
const GridOffset = struct {
    x: f32,
    y: f32,
};

/// 应用space-between对齐（通用函数，用于justify-content和align-content）
/// 参数：
/// - positions: 要调整的位置数组（column_positions或row_positions）
/// - grid_size: grid的总尺寸（grid_width或grid_height）
/// - container_size: 容器的尺寸（container_width或container_height）
/// - gap: gap值（column_gap或row_gap）
fn applySpaceBetween(
    positions: *std.ArrayList(f32),
    grid_size: f32,
    container_size: f32,
    gap: f32,
) void {
    std.log.warn("[Grid] applySpaceBetween - positions.len={d}, grid_size={d}, container_size={d}, gap={d}", .{ positions.items.len, grid_size, container_size, gap });
    if (positions.items.len > 1) {
        // positions包含结束位置，所以tracks_count = len - 1
        const tracks_count = positions.items.len - 1;
        std.log.warn("[Grid] applySpaceBetween - tracks_count={d}", .{tracks_count});
        // 保存原始positions（在修改之前）
        var orig_positions = [_]f32{0} ** 10;
        if (tracks_count <= orig_positions.len) {
            for (0..tracks_count) |i| {
                orig_positions[i] = positions.items[i];
                std.log.warn("[Grid] applySpaceBetween - orig_positions[{d}]={d}", .{ i, orig_positions[i] });
            }
        }

        // 计算每个track的尺寸（使用原始positions）
        var track_sizes = [_]f32{0} ** 10; // 假设最多10个tracks
        if (tracks_count <= track_sizes.len) {
            for (0..tracks_count) |i| {
                if (i < tracks_count - 1) {
                    // 有下一个track：尺寸 = 下一个track起始位置 - 当前track起始位置 - gap
                    track_sizes[i] = orig_positions[i + 1] - orig_positions[i] - gap;
                } else {
                    // 最后一个track：需要从原始grid_size计算
                    track_sizes[i] = grid_size - orig_positions[i];
                }
                std.log.warn("[Grid] applySpaceBetween - track_sizes[{d}]={d}", .{ i, track_sizes[i] });
            }

            // 计算总尺寸（包括gap）
            var total_tracks_size: f32 = 0;
            for (0..tracks_count) |i| {
                total_tracks_size += track_sizes[i];
            }
            const total_gaps_size = gap * @as(f32, @floatFromInt(tracks_count - 1));
            const total_grid_size = total_tracks_size + total_gaps_size;
            std.log.warn("[Grid] applySpaceBetween - total_tracks_size={d}, total_gaps_size={d}, total_grid_size={d}", .{ total_tracks_size, total_gaps_size, total_grid_size });

            // 计算剩余空间和gap间距
            const remaining_space = container_size - total_grid_size;
            const gaps_count = tracks_count - 1;
            const gap_size = if (gaps_count > 0) remaining_space / @as(f32, @floatFromInt(gaps_count)) else 0;
            std.log.warn("[Grid] applySpaceBetween - remaining_space={d}, gaps_count={d}, gap_size={d}", .{ remaining_space, gaps_count, gap_size });

            // 重新计算positions（positions存储起始位置，最后一个值是结束位置）
            // space-between: 第一个track在0，最后一个track在container_size - last_track_size
            std.log.warn("[Grid] applySpaceBetween - before update: positions[0]={d}, positions[{d}]={d}", .{ positions.items[0], tracks_count - 1, positions.items[tracks_count - 1] });
            positions.items[0] = 0;
            if (tracks_count > 1) {
                // 最后一个track的起始位置 = container_size - 最后一个track的尺寸
                const last_pos = container_size - track_sizes[tracks_count - 1];
                positions.items[tracks_count - 1] = last_pos;
                std.log.warn("[Grid] applySpaceBetween - updating positions[{d}]={d} (container_size={d} - track_sizes[{d}]={d})", .{ tracks_count - 1, last_pos, container_size, tracks_count - 1, track_sizes[tracks_count - 1] });

                // 中间的tracks均匀分布
                if (tracks_count > 2) {
                    var current_pos: f32 = track_sizes[0] + gap_size;
                    for (1..tracks_count - 1) |i| {
                        positions.items[i] = current_pos;
                        std.log.warn("[Grid] applySpaceBetween - updating positions[{d}]={d}", .{ i, current_pos });
                        current_pos += track_sizes[i] + gap_size;
                    }
                }
                // tracks_count == 2时，已经在上面正确设置了两个位置
            }
            // 更新结束位置
            if (positions.items.len > tracks_count) {
                positions.items[tracks_count] = container_size;
            }
            std.log.warn("[Grid] applySpaceBetween - after update: positions[0]={d}, positions[{d}]={d}", .{ positions.items[0], tracks_count - 1, positions.items[tracks_count - 1] });
        } else {
            std.log.warn("[Grid] applySpaceBetween - tracks_count ({d}) > track_sizes.len ({d}), skipping", .{ tracks_count, track_sizes.len });
        }
    } else {
        std.log.warn("[Grid] applySpaceBetween - positions.items.len ({d}) <= 1, skipping", .{positions.items.len});
    }
}

/// 应用grid content对齐（justify-content, align-content）
/// 返回grid的偏移量
fn applyGridContentAlignment(
    column_positions: *std.ArrayList(f32),
    row_positions: *std.ArrayList(f32),
    container_width: f32,
    container_height: f32,
    justify_content: style_utils.GridJustifyContent,
    align_content: style_utils.GridAlignContent,
    column_gap: f32,
    row_gap: f32,
    _: std.mem.Allocator, // allocator暂时未使用（space-between使用固定大小数组）
) std.mem.Allocator.Error!GridOffset {
    var offset = GridOffset{ .x = 0, .y = 0 };

    // 计算grid的总宽度和总高度（在调整之前，使用原始值）
    // grid_width = 最后一列的起始位置 + 最后一列的宽度
    // 注意：column_positions存储的是起始位置，所以最后一列的结束位置需要计算
    const grid_width = if (column_positions.items.len > 0) blk: {
        if (column_positions.items.len == 1) {
            // 只有一列：需要从grid_template_columns获取宽度（这里简化处理，使用container_width）
            break :blk column_positions.items[0];
        } else {
            // 多列：column_positions的最后一个值就是grid的结束位置（最后一列的结束位置）
            // 因为column_positions存储的是每列的起始位置，最后一个值就是最后一列结束的位置
            break :blk column_positions.items[column_positions.items.len - 1];
        }
    } else 0;

    // grid_height = 最后一行的起始位置 + 最后一行的宽度
    // 注意：row_positions存储的是起始位置，所以最后一行的结束位置需要计算
    const grid_height = if (row_positions.items.len > 0) blk: {
        if (row_positions.items.len == 1) {
            // 只有一行：需要从grid_template_rows获取高度（这里简化处理，使用container_height）
            break :blk row_positions.items[0];
        } else {
            // 多行：row_positions的最后一个值就是grid的结束位置（最后一行的结束位置）
            // 因为row_positions存储的是每行的起始位置，最后一个值就是最后一行结束的位置
            break :blk row_positions.items[row_positions.items.len - 1];
        }
    } else 0;

    // 计算剩余空间
    const free_width = container_width - grid_width;
    const free_height = container_height - grid_height;

    // 应用justify-content
    switch (justify_content) {
        .start => offset.x = 0,
        .end => offset.x = free_width,
        .center => offset.x = free_width / 2.0,
        .stretch => {
            // stretch: 拉伸grid填满容器（调整列宽）
            if (column_positions.items.len > 1 and free_width > 0) {
                const scale = container_width / grid_width;
                for (column_positions.items[1..]) |*pos| {
                    pos.* = pos.* * scale;
                }
            }
        },
        .space_between => {
            // space-between: 第一个track在开始位置，最后一个track在结束位置，中间的tracks之间均匀分布
            applySpaceBetween(column_positions, grid_width, container_width, column_gap);
            offset.x = 0;
        },
        .space_around => {
            // space-around: 每个track两侧都有相等的空间
            if (column_positions.items.len > 0) {
                // column_positions包含结束位置，所以tracks_count = len - 1
                const tracks_count = column_positions.items.len - 1;
                // 保存原始positions（在修改之前）
                var orig_positions = [_]f32{0} ** 10;
                if (tracks_count <= orig_positions.len) {
                    for (0..tracks_count) |i| {
                        orig_positions[i] = column_positions.items[i];
                    }
                }

                // 计算每个track的宽度（使用原始positions）
                var track_widths = [_]f32{0} ** 10; // 假设最多10个tracks
                if (tracks_count <= track_widths.len) {
                    for (0..tracks_count) |i| {
                        if (i < tracks_count - 1) {
                            // 有下一列：宽度 = 下一列起始位置 - 当前列起始位置 - gap
                            track_widths[i] = orig_positions[i + 1] - orig_positions[i] - column_gap;
                        } else {
                            // 最后一列：需要从原始grid_width计算
                            track_widths[i] = grid_width - orig_positions[i];
                        }
                    }

                    // 计算总宽度（包括gap）
                    var total_tracks_width: f32 = 0;
                    for (0..tracks_count) |i| {
                        total_tracks_width += track_widths[i];
                    }
                    const total_gaps_width = column_gap * @as(f32, @floatFromInt(tracks_count - 1));
                    const total_grid_width = total_tracks_width + total_gaps_width;

                    // 计算剩余空间和每侧空间
                    const remaining_space = container_width - total_grid_width;
                    const space_per_side = remaining_space / @as(f32, @floatFromInt(tracks_count * 2));

                    // 重新计算positions（column_positions存储起始位置，最后一个值是结束位置）
                    // space-around: 每个track两侧都有相等的空间
                    // 对于2个tracks：track1左侧=space_per_side，track1和track2之间=space_per_side，track2右侧=space_per_side
                    // 所以track2位置 = space_per_side + track_widths[0] + space_per_side
                    var current_pos = space_per_side;
                    for (0..tracks_count) |i| {
                        column_positions.items[i] = current_pos;
                        if (i < tracks_count - 1) {
                            // 下一个track的位置 = 当前track位置 + 当前track宽度 + gap + space_per_side（track之间的间距）
                            current_pos += track_widths[i] + column_gap + space_per_side;
                        }
                    }
                    // 更新结束位置
                    if (column_positions.items.len > tracks_count) {
                        column_positions.items[tracks_count] = container_width;
                    }
                }
            }
            offset.x = 0;
        },
        .space_evenly => {
            // space-evenly: 所有空间（包括两端）均匀分布
            if (column_positions.items.len > 0) {
                // column_positions包含结束位置，所以tracks_count = len - 1
                const tracks_count = column_positions.items.len - 1;
                // 保存原始positions（在修改之前）
                var orig_positions = [_]f32{0} ** 10;
                if (tracks_count <= orig_positions.len) {
                    for (0..tracks_count) |i| {
                        orig_positions[i] = column_positions.items[i];
                    }
                }

                // 计算每个track的宽度（使用原始positions）
                var track_widths = [_]f32{0} ** 10; // 假设最多10个tracks
                if (tracks_count <= track_widths.len) {
                    for (0..tracks_count) |i| {
                        if (i < tracks_count - 1) {
                            // 有下一列：宽度 = 下一列起始位置 - 当前列起始位置 - gap
                            track_widths[i] = orig_positions[i + 1] - orig_positions[i] - column_gap;
                        } else {
                            // 最后一列：需要从原始grid_width计算
                            track_widths[i] = grid_width - orig_positions[i];
                        }
                    }

                    // 计算总宽度（包括gap）
                    var total_tracks_width: f32 = 0;
                    for (0..tracks_count) |i| {
                        total_tracks_width += track_widths[i];
                    }
                    const total_gaps_width = column_gap * @as(f32, @floatFromInt(tracks_count - 1));
                    const total_grid_width = total_tracks_width + total_gaps_width;

                    // 计算剩余空间和每个gap的间距
                    const remaining_space = container_width - total_grid_width;
                    const gaps_count = tracks_count + 1; // 包括两端（开始-track1, track1-track2, ..., trackN-结束）
                    const space_per_gap = remaining_space / @as(f32, @floatFromInt(gaps_count));

                    // 重新计算positions（column_positions存储起始位置，最后一个值是结束位置）
                    // space-evenly: 所有空间（包括两端）均匀分布
                    var current_pos = space_per_gap;
                    for (0..tracks_count) |i| {
                        column_positions.items[i] = current_pos;
                        if (i < tracks_count - 1) {
                            // 下一个track的位置 = 当前track位置 + 当前track宽度 + gap + 下一个gap的间距
                            current_pos += track_widths[i] + column_gap + space_per_gap;
                        }
                    }
                    // 更新结束位置
                    if (column_positions.items.len > tracks_count) {
                        column_positions.items[tracks_count] = container_width;
                    }
                }
            }
            offset.x = 0;
        },
    }

    // 应用align-content
    std.log.warn("[Grid] applyGridContentAlignment - align_content={}, free_height={d}, container_height={d}", .{ align_content, free_height, container_height });
    switch (align_content) {
        .start => {
            std.log.debug("[Grid] applyGridContentAlignment - align-content: start", .{});
            offset.y = 0;
        },
        .end => {
            std.log.debug("[Grid] applyGridContentAlignment - align-content: end", .{});
            offset.y = free_height;
        },
        .center => {
            std.log.debug("[Grid] applyGridContentAlignment - align-content: center", .{});
            offset.y = free_height / 2.0;
        },
        .stretch => {
            std.log.debug("[Grid] applyGridContentAlignment - align-content: stretch", .{});
            // stretch: 拉伸grid填满容器（调整行高）
            if (row_positions.items.len > 1 and free_height > 0) {
                const scale = container_height / grid_height;
                for (row_positions.items[1..]) |*pos| {
                    pos.* = pos.* * scale;
                }
            }
        },
        .space_between => {
            // space-between: 第一个track在开始位置，最后一个track在结束位置，中间的tracks之间均匀分布
            std.log.warn("[Grid] align-content: space-between - row_positions.len={d}, container_height={d}, grid_height={d}", .{ row_positions.items.len, container_height, grid_height });
            applySpaceBetween(row_positions, grid_height, container_height, row_gap);
            std.log.warn("[Grid] align-content: space-between - after update: row_positions[0]={d}, row_positions[1]={d}", .{ row_positions.items[0], if (row_positions.items.len > 1) row_positions.items[1] else 0 });
            offset.y = 0;
        },
        .space_around => {
            // space-around: 每个track两侧都有相等的空间
            if (row_positions.items.len > 0) {
                // row_positions包含结束位置，所以tracks_count = len - 1
                const tracks_count = row_positions.items.len - 1;
                // 保存原始positions（在修改之前）
                var orig_positions = [_]f32{0} ** 10;
                if (tracks_count <= orig_positions.len) {
                    for (0..tracks_count) |i| {
                        orig_positions[i] = row_positions.items[i];
                    }
                }

                // 计算每个track的高度（使用原始positions）
                var track_heights = [_]f32{0} ** 10; // 假设最多10个tracks
                if (tracks_count <= track_heights.len) {
                    for (0..tracks_count) |i| {
                        if (i < tracks_count - 1) {
                            // 有下一行：高度 = 下一行起始位置 - 当前行起始位置 - gap
                            track_heights[i] = orig_positions[i + 1] - orig_positions[i] - row_gap;
                        } else {
                            // 最后一行：需要从原始grid_height计算
                            track_heights[i] = grid_height - orig_positions[i];
                        }
                    }

                    // 计算总高度（包括gap）
                    var total_tracks_height: f32 = 0;
                    for (0..tracks_count) |i| {
                        total_tracks_height += track_heights[i];
                    }
                    const total_gaps_height = row_gap * @as(f32, @floatFromInt(tracks_count - 1));
                    const total_grid_height = total_tracks_height + total_gaps_height;

                    // 计算剩余空间和每侧空间
                    const remaining_space = container_height - total_grid_height;
                    const space_per_side = remaining_space / @as(f32, @floatFromInt(tracks_count * 2));

                    // 重新计算positions（row_positions存储起始位置，最后一个值是结束位置）
                    var current_pos = space_per_side;
                    for (0..tracks_count) |i| {
                        row_positions.items[i] = current_pos;
                        if (i < tracks_count - 1) {
                            current_pos += track_heights[i] + row_gap + space_per_side * 2;
                        }
                    }
                    // 更新结束位置
                    if (row_positions.items.len > tracks_count) {
                        row_positions.items[tracks_count] = container_height;
                    }
                }
            }
            offset.y = 0;
        },
        .space_evenly => {
            // space-evenly: 所有空间（包括两端）均匀分布
            if (row_positions.items.len > 0) {
                // row_positions包含结束位置，所以tracks_count = len - 1
                const tracks_count = row_positions.items.len - 1;
                // 保存原始positions（在修改之前）
                var orig_positions = [_]f32{0} ** 10;
                if (tracks_count <= orig_positions.len) {
                    for (0..tracks_count) |i| {
                        orig_positions[i] = row_positions.items[i];
                    }
                }

                // 计算每个track的高度（使用原始positions）
                var track_heights = [_]f32{0} ** 10; // 假设最多10个tracks
                if (tracks_count <= track_heights.len) {
                    for (0..tracks_count) |i| {
                        if (i < tracks_count - 1) {
                            // 有下一行：高度 = 下一行起始位置 - 当前行起始位置 - gap
                            track_heights[i] = orig_positions[i + 1] - orig_positions[i] - row_gap;
                        } else {
                            // 最后一行：需要从原始grid_height计算
                            track_heights[i] = grid_height - orig_positions[i];
                        }
                    }

                    // 计算总高度（包括gap）
                    var total_tracks_height: f32 = 0;
                    for (0..tracks_count) |i| {
                        total_tracks_height += track_heights[i];
                    }
                    const total_gaps_height = row_gap * @as(f32, @floatFromInt(tracks_count - 1));
                    const total_grid_height = total_tracks_height + total_gaps_height;

                    // 计算剩余空间和每个gap的间距
                    const remaining_space = container_height - total_grid_height;
                    const gaps_count = tracks_count + 1; // 包括两端
                    const space_per_gap = remaining_space / @as(f32, @floatFromInt(gaps_count));

                    // 重新计算positions（row_positions存储起始位置，最后一个值是结束位置）
                    // space-evenly: 所有空间（包括两端）均匀分布
                    var current_pos = space_per_gap;
                    for (0..tracks_count) |i| {
                        row_positions.items[i] = current_pos;
                        if (i < tracks_count - 1) {
                            current_pos += track_heights[i] + row_gap + space_per_gap;
                        }
                    }
                    // 更新结束位置
                    if (row_positions.items.len > tracks_count) {
                        row_positions.items[tracks_count] = container_height;
                    }
                }
            }
            offset.y = 0;
        },
    }

    return offset;
}

/// 应用grid item对齐（justify-items, align-items）
/// 返回item在cell内的偏移量
fn applyGridItemAlignment(
    item_width: f32,
    item_height: f32,
    cell_width: f32,
    cell_height: f32,
    justify_items: style_utils.GridJustifyItems,
    align_items: style_utils.GridAlignItems,
) GridOffset {
    var offset = GridOffset{ .x = 0, .y = 0 };

    // 应用justify-items
    switch (justify_items) {
        .start => offset.x = 0,
        .end => offset.x = cell_width - item_width,
        .center => offset.x = (cell_width - item_width) / 2.0,
        .stretch => {
            // stretch: item宽度会被设置为cell_width（在调用处处理）
            offset.x = 0;
        },
    }

    // 应用align-items
    switch (align_items) {
        .start => offset.y = 0,
        .end => offset.y = cell_height - item_height,
        .center => offset.y = (cell_height - item_height) / 2.0,
        .stretch => {
            // stretch: item高度会被设置为cell_height（在调用处处理）
            offset.y = 0;
        },
    }

    return offset;
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
