const std = @import("std");
const box = @import("box");
const cascade = @import("cascade");
const css_parser = @import("parser");

/// 样式工具函数
/// 用于从ComputedStyle中解析CSS属性值并应用到LayoutBox
/// 解析display属性值
pub fn parseDisplayType(value: []const u8) box.DisplayType {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "block")) return .block;
    if (std.mem.eql(u8, value, "inline-block")) return .inline_block;
    if (std.mem.eql(u8, value, "inline")) return .inline_element;
    if (std.mem.eql(u8, value, "flex")) return .flex;
    if (std.mem.eql(u8, value, "inline-flex")) return .inline_flex;
    if (std.mem.eql(u8, value, "grid")) return .grid;
    if (std.mem.eql(u8, value, "inline-grid")) return .inline_grid;
    if (std.mem.eql(u8, value, "table")) return .table;
    if (std.mem.eql(u8, value, "inline-table")) return .inline_table;
    if (std.mem.eql(u8, value, "table-row")) return .table_row;
    if (std.mem.eql(u8, value, "table-cell")) return .table_cell;
    // 默认返回block
    return .block;
}

/// 解析position属性值
pub fn parsePositionType(value: []const u8) box.PositionType {
    if (std.mem.eql(u8, value, "static")) return .static;
    if (std.mem.eql(u8, value, "relative")) return .relative;
    if (std.mem.eql(u8, value, "absolute")) return .absolute;
    if (std.mem.eql(u8, value, "fixed")) return .fixed;
    if (std.mem.eql(u8, value, "sticky")) return .sticky;
    // 默认返回static
    return .static;
}

/// 解析float属性值
pub fn parseFloatType(value: []const u8) box.FloatType {
    if (std.mem.eql(u8, value, "left")) return .left;
    if (std.mem.eql(u8, value, "right")) return .right;
    // 默认返回none
    return .none;
}

/// 解析长度值（px单位）为f32
/// TODO: 支持更多单位（em, rem, %, vw, vh等）
pub fn parseLength(value: css_parser.Value, containing_size: f32) f32 {
    return switch (value) {
        .length => |l| {
            if (std.mem.eql(u8, l.unit, "px")) {
                return @as(f32, @floatCast(l.value));
            }
            // TODO: 支持其他单位
            return 0;
        },
        .percentage => |p| {
            return containing_size * @as(f32, @floatCast(p / 100.0));
        },
        else => 0,
    };
}

/// 从ComputedStyle获取属性值（字符串）
pub fn getPropertyKeyword(computed_style: *const cascade.ComputedStyle, name: []const u8) ?[]const u8 {
    if (computed_style.getProperty(name)) |decl| {
        return switch (decl.value) {
            .keyword => |k| k,
            else => null,
        };
    }
    return null;
}

/// 从ComputedStyle获取长度值
pub fn getPropertyLength(computed_style: *const cascade.ComputedStyle, name: []const u8, containing_size: f32) ?f32 {
    if (computed_style.getProperty(name)) |decl| {
        return parseLength(decl.value, containing_size);
    }
    return null;
}

/// 应用样式到LayoutBox
pub fn applyStyleToLayoutBox(layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, containing_size: box.Size) void {
    // 解析display
    if (getPropertyKeyword(computed_style, "display")) |display_value| {
        layout_box.display = parseDisplayType(display_value);
    }

    // 解析position
    if (getPropertyKeyword(computed_style, "position")) |position_value| {
        layout_box.position = parsePositionType(position_value);
    }

    // 解析float
    if (getPropertyKeyword(computed_style, "float")) |float_value| {
        layout_box.float = parseFloatType(float_value);
    }

    // 解析定位属性（top, right, bottom, left）
    if (getPropertyLength(computed_style, "top", containing_size.height)) |top| {
        layout_box.position_top = top;
    }
    if (getPropertyLength(computed_style, "right", containing_size.width)) |right| {
        layout_box.position_right = right;
    }
    if (getPropertyLength(computed_style, "bottom", containing_size.height)) |bottom| {
        layout_box.position_bottom = bottom;
    }
    if (getPropertyLength(computed_style, "left", containing_size.width)) |left| {
        layout_box.position_left = left;
    }

    // TODO: 解析padding、border、margin
    // TODO: 解析width、height
    // TODO: 解析box-sizing
}

/// Flexbox属性解析
/// 解析flex-direction属性值
pub const FlexDirection = enum {
    row,
    row_reverse,
    column,
    column_reverse,
};

pub fn parseFlexDirection(value: []const u8) FlexDirection {
    if (std.mem.eql(u8, value, "row")) return .row;
    if (std.mem.eql(u8, value, "row-reverse")) return .row_reverse;
    if (std.mem.eql(u8, value, "column")) return .column;
    if (std.mem.eql(u8, value, "column-reverse")) return .column_reverse;
    // 默认返回row
    return .row;
}

/// 解析flex-wrap属性值
pub const FlexWrap = enum {
    nowrap,
    wrap,
    wrap_reverse,
};

pub fn parseFlexWrap(value: []const u8) FlexWrap {
    if (std.mem.eql(u8, value, "nowrap")) return .nowrap;
    if (std.mem.eql(u8, value, "wrap")) return .wrap;
    if (std.mem.eql(u8, value, "wrap-reverse")) return .wrap_reverse;
    // 默认返回nowrap
    return .nowrap;
}

/// 解析justify-content属性值
pub const JustifyContent = enum {
    flex_start,
    flex_end,
    center,
    space_between,
    space_around,
    space_evenly,
};

pub fn parseJustifyContent(value: []const u8) JustifyContent {
    if (std.mem.eql(u8, value, "flex-start")) return .flex_start;
    if (std.mem.eql(u8, value, "flex-end")) return .flex_end;
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "space-between")) return .space_between;
    if (std.mem.eql(u8, value, "space-around")) return .space_around;
    if (std.mem.eql(u8, value, "space-evenly")) return .space_evenly;
    // 默认返回flex-start
    return .flex_start;
}

/// 从ComputedStyle获取Flexbox属性
pub fn getFlexDirection(computed_style: *const cascade.ComputedStyle) FlexDirection {
    if (getPropertyKeyword(computed_style, "flex-direction")) |value| {
        return parseFlexDirection(value);
    }
    return .row; // 默认值
}

pub fn getFlexWrap(computed_style: *const cascade.ComputedStyle) FlexWrap {
    if (getPropertyKeyword(computed_style, "flex-wrap")) |value| {
        return parseFlexWrap(value);
    }
    return .nowrap; // 默认值
}

pub fn getJustifyContent(computed_style: *const cascade.ComputedStyle) JustifyContent {
    if (getPropertyKeyword(computed_style, "justify-content")) |value| {
        return parseJustifyContent(value);
    }
    return .flex_start; // 默认值
}

/// Grid属性解析
/// 解析grid-template-rows/columns（简化：只支持固定值，如"100px 200px"）
/// TODO: 完整实现需要支持repeat(), minmax(), fr单位等
pub fn parseGridTemplate(value: []const u8, allocator: std.mem.Allocator) !std.ArrayList(f32) {
    var tracks = std.ArrayList(f32){
        .items = &[_]f32{},
        .capacity = 0,
    };
    errdefer tracks.deinit(allocator);

    // 简化实现：按空格分割，解析每个值
    var iter = std.mem.splitSequence(u8, value, " ");
    while (iter.next()) |track_str| {
        const trimmed = std.mem.trim(u8, track_str, " \t\n\r");
        if (trimmed.len == 0) continue;

        // 解析长度值（简化：只支持px）
        if (std.mem.endsWith(u8, trimmed, "px")) {
            const num_str = trimmed[0 .. trimmed.len - 2];
            const num = std.fmt.parseFloat(f32, num_str) catch continue;
            try tracks.append(allocator, num);
        }
    }

    return tracks;
}

/// 从ComputedStyle获取Grid属性
pub fn getGridTemplateRows(computed_style: *const cascade.ComputedStyle, allocator: std.mem.Allocator) !std.ArrayList(f32) {
    if (getPropertyKeyword(computed_style, "grid-template-rows")) |value| {
        return parseGridTemplate(value, allocator);
    }
    // 默认返回空列表
    return std.ArrayList(f32){
        .items = &[_]f32{},
        .capacity = 0,
    };
}

pub fn getGridTemplateColumns(computed_style: *const cascade.ComputedStyle, allocator: std.mem.Allocator) !std.ArrayList(f32) {
    if (getPropertyKeyword(computed_style, "grid-template-columns")) |value| {
        return parseGridTemplate(value, allocator);
    }
    // 默认返回空列表
    return std.ArrayList(f32){
        .items = &[_]f32{},
        .capacity = 0,
    };
}
