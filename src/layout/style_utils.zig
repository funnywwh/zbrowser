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

/// 从字符串解析px单位的值
/// 支持格式："10px"、"0"（作为0px）
/// 返回解析的数值，如果解析失败返回null
fn parsePxValue(str: []const u8) ?f32 {
    const trimmed = std.mem.trim(u8, str, " \t\n\r");
    if (trimmed.len == 0) return null;

    // 解析px单位
    if (std.mem.endsWith(u8, trimmed, "px")) {
        const num_str = trimmed[0 .. trimmed.len - 2];
        if (std.fmt.parseFloat(f32, num_str)) |num| {
            return num;
        } else |_| {
            return null;
        }
    }

    // 支持 "0" 作为 0px
    if (std.mem.eql(u8, trimmed, "0")) {
        return 0;
    }

    return null;
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
        const result = switch (decl.value) {
            .keyword => |k| k,
            else => null,
        };
        std.log.warn("[StyleUtils] getPropertyKeyword - name='{s}', found={}, result={?s}", .{ name, true, result });
        return result;
    }
    std.log.warn("[StyleUtils] getPropertyKeyword - name='{s}', not found", .{name});
    return null;
}

/// 从ComputedStyle获取长度值
pub fn getPropertyLength(computed_style: *const cascade.ComputedStyle, name: []const u8, containing_size: f32) ?f32 {
    if (computed_style.getProperty(name)) |decl| {
        // 只返回长度值，如果是其他类型（如关键字），返回null
        return switch (decl.value) {
            .length => |l| {
                if (std.mem.eql(u8, l.unit, "px")) {
                    return @as(f32, @floatCast(l.value));
                }
                // TODO: 支持其他单位
                return null;
            },
            .percentage => |p| {
                return containing_size * @as(f32, @floatCast(p / 100.0));
            },
            else => null, // 关键字值或其他类型，返回null
        };
    }
    return null;
}

/// 从ComputedStyle获取颜色值
pub fn getPropertyColor(computed_style: *const cascade.ComputedStyle, name: []const u8) ?css_parser.Value.Color {
    if (computed_style.getProperty(name)) |decl| {
        return switch (decl.value) {
            .color => |c| c,
            else => null,
        };
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
        const node_type_str = switch (layout_box.node.node_type) {
            .element => if (layout_box.node.asElement()) |elem| elem.tag_name else "unknown",
            .text => "text",
            .comment => "comment",
            .document => "document",
            .doctype => "doctype",
        };
        const class_name = if (layout_box.node.node_type == .element)
            if (layout_box.node.asElement()) |elem| elem.attributes.get("class") else null
        else
            null;
        if (class_name) |class| {
            std.log.debug("[StyleUtils] applyStyleToLayoutBox: node='{s}.{s}', position={s} -> {}", .{ node_type_str, class, position_value, layout_box.position });
        } else {
            std.log.debug("[StyleUtils] applyStyleToLayoutBox: node='{s}', position={s} -> {}", .{ node_type_str, position_value, layout_box.position });
        }
    }

    // 解析float
    if (getPropertyKeyword(computed_style, "float")) |float_value| {
        layout_box.float = parseFloatType(float_value);
    }

    // 解析定位属性（top, right, bottom, left）
    if (getPropertyLength(computed_style, "top", containing_size.height)) |top| {
        layout_box.position_top = top;
        std.log.debug("[StyleUtils] applyStyleToLayoutBox: position_top={d:.1}", .{top});
    }
    if (getPropertyLength(computed_style, "right", containing_size.width)) |right| {
        layout_box.position_right = right;
    }
    if (getPropertyLength(computed_style, "bottom", containing_size.height)) |bottom| {
        layout_box.position_bottom = bottom;
    }
    if (getPropertyLength(computed_style, "left", containing_size.width)) |left| {
        layout_box.position_left = left;
        std.log.debug("[StyleUtils] applyStyleToLayoutBox: position_left={d:.1}", .{left});
    }

    // 解析margin
    parseMargin(layout_box, computed_style, containing_size);

    // 解析padding
    parsePadding(layout_box, computed_style, containing_size);

    // TODO: 解析border
    // TODO: 解析width、height
    // TODO: 解析box-sizing
}

/// 解析margin属性
/// 支持格式：
/// - margin: 10px (所有边)
/// - margin: 10px 0 (上下 左右)
/// - margin: 10px 0 5px 0 (上 右 下 左)
/// - margin-top, margin-right, margin-bottom, margin-left (单独属性)
fn parseMargin(layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, containing_size: box.Size) void {
    // 先检查单独的margin属性
    if (getPropertyLength(computed_style, "margin-top", containing_size.height)) |top| {
        layout_box.box_model.margin.top = top;
    }
    if (getPropertyLength(computed_style, "margin-right", containing_size.width)) |right| {
        layout_box.box_model.margin.right = right;
    }
    if (getPropertyLength(computed_style, "margin-bottom", containing_size.height)) |bottom| {
        layout_box.box_model.margin.bottom = bottom;
    }
    if (getPropertyLength(computed_style, "margin-left", containing_size.width)) |left| {
        layout_box.box_model.margin.left = left;
    }

    // 检查margin简写属性（会覆盖单独属性）
    // 先尝试从length获取（如果margin是单个值，可能被解析为length）
    if (getPropertyLength(computed_style, "margin", containing_size.width)) |margin_length| {
        // 单个长度值，所有边都是这个值
        layout_box.box_model.margin.top = margin_length;
        layout_box.box_model.margin.right = margin_length;
        layout_box.box_model.margin.bottom = margin_length;
        layout_box.box_model.margin.left = margin_length;
        std.log.debug("[StyleUtils] parseMargin: found margin as length = {d:.1}px", .{margin_length});
    } else if (getPropertyKeyword(computed_style, "margin")) |margin_value| {
        std.log.debug("[StyleUtils] parseMargin: found margin shorthand = '{s}'", .{margin_value});
        parseMarginShorthand(layout_box, margin_value, containing_size);
        std.log.debug("[StyleUtils] parseMargin: applied margin = top={d:.1}, right={d:.1}, bottom={d:.1}, left={d:.1}", .{
            layout_box.box_model.margin.top,
            layout_box.box_model.margin.right,
            layout_box.box_model.margin.bottom,
            layout_box.box_model.margin.left,
        });
    }
}

/// 四边值结构
const FourSides = struct {
    top: f32,
    right: f32,
    bottom: f32,
    left: f32,
};

/// 解析四边简写属性值
/// 格式：<top> <right> <bottom> <left> 或 <vertical> <horizontal> 或 <all>
/// 返回解析的四边值，如果解析失败返回null
fn parseFourSidesShorthand(value_str: []const u8) ?FourSides {
    // 按空格分割值
    var parts = std.mem.splitSequence(u8, value_str, " ");
    var values: [4]?f32 = .{ null, null, null, null };
    var count: usize = 0;

    while (parts.next()) |part| {
        if (count >= 4) break; // 最多4个值

        if (parsePxValue(part)) |num| {
            values[count] = num;
            count += 1;
        }
    }

    // 根据值的数量应用
    if (count == 1) {
        // 单个值：所有边都是这个值
        const value = values[0] orelse return null;
        return FourSides{ .top = value, .right = value, .bottom = value, .left = value };
    } else if (count == 2) {
        // 两个值：上下 左右
        const vertical = values[0] orelse return null;
        const horizontal = values[1] orelse return null;
        return FourSides{ .top = vertical, .right = horizontal, .bottom = vertical, .left = horizontal };
    } else if (count == 3) {
        // 三个值：上 左右 下
        const top = values[0] orelse return null;
        const horizontal = values[1] orelse return null;
        const bottom = values[2] orelse return null;
        return FourSides{ .top = top, .right = horizontal, .bottom = bottom, .left = horizontal };
    } else if (count == 4) {
        // 四个值：上 右 下 左
        const top = values[0] orelse return null;
        const right = values[1] orelse return null;
        const bottom = values[2] orelse return null;
        const left = values[3] orelse return null;
        return FourSides{ .top = top, .right = right, .bottom = bottom, .left = left };
    }

    return null;
}

/// 解析margin简写属性
/// 格式：margin: <top> <right> <bottom> <left>
/// 或：margin: <vertical> <horizontal>
/// 或：margin: <all>
fn parseMarginShorthand(layout_box: *box.LayoutBox, margin_value: []const u8, _: box.Size) void {
    if (parseFourSidesShorthand(margin_value)) |sides| {
        layout_box.box_model.margin.top = sides.top;
        layout_box.box_model.margin.right = sides.right;
        layout_box.box_model.margin.bottom = sides.bottom;
        layout_box.box_model.margin.left = sides.left;
    }
}

/// 解析padding属性
/// 支持格式：
/// - padding: 10px (所有边)
/// - padding: 10px 0 (上下 左右)
/// - padding: 10px 0 5px 0 (上 右 下 左)
/// - padding-top, padding-right, padding-bottom, padding-left (单独属性)
fn parsePadding(layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, containing_size: box.Size) void {
    // 先检查单独的padding属性
    if (getPropertyLength(computed_style, "padding-top", containing_size.height)) |top| {
        layout_box.box_model.padding.top = top;
    }
    if (getPropertyLength(computed_style, "padding-right", containing_size.width)) |right| {
        layout_box.box_model.padding.right = right;
    }
    if (getPropertyLength(computed_style, "padding-bottom", containing_size.height)) |bottom| {
        layout_box.box_model.padding.bottom = bottom;
    }
    if (getPropertyLength(computed_style, "padding-left", containing_size.width)) |left| {
        layout_box.box_model.padding.left = left;
    }

    // 检查padding简写属性（会覆盖单独属性）
    // 先尝试从length获取（如果padding是单个值，可能被解析为length）
    if (getPropertyLength(computed_style, "padding", containing_size.width)) |padding_length| {
        // 单个长度值，所有边都是这个值
        layout_box.box_model.padding.top = padding_length;
        layout_box.box_model.padding.right = padding_length;
        layout_box.box_model.padding.bottom = padding_length;
        layout_box.box_model.padding.left = padding_length;
        std.log.debug("[StyleUtils] parsePadding: found padding as length = {d:.1}px", .{padding_length});
    } else if (getPropertyKeyword(computed_style, "padding")) |padding_value| {
        std.log.debug("[StyleUtils] parsePadding: found padding shorthand = '{s}'", .{padding_value});
        parsePaddingShorthand(layout_box, padding_value, containing_size);
        std.log.debug("[StyleUtils] parsePadding: applied padding = top={d:.1}, right={d:.1}, bottom={d:.1}, left={d:.1}", .{
            layout_box.box_model.padding.top,
            layout_box.box_model.padding.right,
            layout_box.box_model.padding.bottom,
            layout_box.box_model.padding.left,
        });
    }
}

/// 解析padding简写属性
/// 格式：padding: <top> <right> <bottom> <left>
/// 或：padding: <vertical> <horizontal>
/// 或：padding: <all>
fn parsePaddingShorthand(layout_box: *box.LayoutBox, padding_value: []const u8, _: box.Size) void {
    if (parseFourSidesShorthand(padding_value)) |sides| {
        layout_box.box_model.padding.top = sides.top;
        layout_box.box_model.padding.right = sides.right;
        layout_box.box_model.padding.bottom = sides.bottom;
        layout_box.box_model.padding.left = sides.left;
    }
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

/// 解析align-items属性值
pub const AlignItems = enum {
    flex_start,
    flex_end,
    center,
    baseline,
    stretch,
};

pub fn parseAlignItems(value: []const u8) AlignItems {
    if (std.mem.eql(u8, value, "flex-start")) return .flex_start;
    if (std.mem.eql(u8, value, "flex-end")) return .flex_end;
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "baseline")) return .baseline;
    if (std.mem.eql(u8, value, "stretch")) return .stretch;
    // 默认返回stretch
    return .stretch;
}

/// 解析align-content属性值
pub const AlignContent = enum {
    flex_start,
    flex_end,
    center,
    space_between,
    space_around,
    space_evenly,
    stretch,
};

pub fn parseAlignContent(value: []const u8) AlignContent {
    if (std.mem.eql(u8, value, "flex-start")) return .flex_start;
    if (std.mem.eql(u8, value, "flex-end")) return .flex_end;
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "space-between")) return .space_between;
    if (std.mem.eql(u8, value, "space-around")) return .space_around;
    if (std.mem.eql(u8, value, "space-evenly")) return .space_evenly;
    if (std.mem.eql(u8, value, "stretch")) return .stretch;
    // 默认返回stretch
    return .stretch;
}

/// Flex item属性结构
pub const FlexItemProperties = struct {
    grow: f32 = 0.0,
    shrink: f32 = 1.0,
    basis: ?f32 = null, // null表示auto
};

/// 从ComputedStyle获取flex-grow值
pub fn getFlexGrow(computed_style: *const cascade.ComputedStyle) f32 {
    if (getPropertyKeyword(computed_style, "flex-grow")) |value| {
        if (std.fmt.parseFloat(f32, value)) |num| {
            return num;
        } else |_| {}
    }
    return 0.0; // 默认值
}

/// 从ComputedStyle获取flex-shrink值
pub fn getFlexShrink(computed_style: *const cascade.ComputedStyle) f32 {
    if (getPropertyKeyword(computed_style, "flex-shrink")) |value| {
        if (std.fmt.parseFloat(f32, value)) |num| {
            return num;
        } else |_| {}
    }
    return 1.0; // 默认值
}

/// 从ComputedStyle获取flex-basis值
/// 返回null表示auto
pub fn getFlexBasis(computed_style: *const cascade.ComputedStyle, containing_size: f32) ?f32 {
    // 先检查flex-basis属性
    if (getPropertyLength(computed_style, "flex-basis", containing_size)) |basis| {
        return basis;
    }
    // 检查flex简写属性（简化实现：只支持单个值，如"1"表示flex-grow=1）
    // TODO: 完整实现需要解析flex简写（flex-grow flex-shrink flex-basis）
    return null; // auto
}

/// 从ComputedStyle获取完整的flex属性
pub fn getFlexProperties(computed_style: *const cascade.ComputedStyle, containing_size: f32) FlexItemProperties {
    return .{
        .grow = getFlexGrow(computed_style),
        .shrink = getFlexShrink(computed_style),
        .basis = getFlexBasis(computed_style, containing_size),
    };
}

/// 从ComputedStyle获取align-items属性
pub fn getAlignItems(computed_style: *const cascade.ComputedStyle) AlignItems {
    if (getPropertyKeyword(computed_style, "align-items")) |value| {
        return parseAlignItems(value);
    }
    return .stretch; // 默认值
}

/// 从ComputedStyle获取align-content属性
pub fn getAlignContent(computed_style: *const cascade.ComputedStyle) AlignContent {
    if (getPropertyKeyword(computed_style, "align-content")) |value| {
        return parseAlignContent(value);
    }
    return .stretch; // 默认值
}

/// Grid属性解析
/// 解析grid-template-rows/columns（简化：只支持固定值，如"100px 200px"）
/// TODO: 完整实现需要支持repeat(), minmax(), fr单位等
pub fn parseGridTemplate(value: []const u8, allocator: std.mem.Allocator) !std.ArrayList(f32) {
    std.log.warn("[StyleUtils] parseGridTemplate - value='{s}'", .{value});
    var tracks = std.ArrayList(f32){
        .items = &[_]f32{},
        .capacity = 0,
    };
    errdefer tracks.deinit(allocator);

    // 简化实现：按空格分割，解析每个值
    var iter = std.mem.splitSequence(u8, value, " ");
    while (iter.next()) |track_str| {
        if (parsePxValue(track_str)) |num| {
            std.log.warn("[StyleUtils] parseGridTemplate - parsed track: {d}", .{num});
            try tracks.append(allocator, num);
        } else {
            std.log.warn("[StyleUtils] parseGridTemplate - failed to parse track: '{s}'", .{track_str});
        }
    }
    std.log.warn("[StyleUtils] parseGridTemplate - tracks.len={d}", .{tracks.items.len});

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
    if (computed_style.getProperty("grid-template-columns")) |decl| {
        std.log.warn("[StyleUtils] getGridTemplateColumns - found property, value type: {}", .{decl.value});
        const value_str = switch (decl.value) {
            .keyword => |k| k,
            .length => |l| blk: {
                // 将长度值转换为字符串（简化：只支持px）
                var buf: [32]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}px", .{l.value}) catch "0px";
                break :blk str;
            },
            else => {
                std.log.warn("[StyleUtils] getGridTemplateColumns - unsupported value type", .{});
                return std.ArrayList(f32){
                    .items = &[_]f32{},
                    .capacity = 0,
                };
            },
        };
        std.log.warn("[StyleUtils] getGridTemplateColumns - value_str='{s}'", .{value_str});
        return parseGridTemplate(value_str, allocator);
    }
    std.log.warn("[StyleUtils] getGridTemplateColumns - property not found", .{});
    // 默认返回空列表
    return std.ArrayList(f32){
        .items = &[_]f32{},
        .capacity = 0,
    };
}

/// 解析gap简写属性值
/// 格式：<row-gap> <column-gap> 或 <all>
/// 返回解析的gap值数组，如果解析失败返回null
fn parseGapShorthand(gap_value: []const u8) ?[2]f32 {
    var values: [2]f32 = undefined;
    var count: usize = 0;

    var iter = std.mem.splitSequence(u8, gap_value, " ");
    while (iter.next()) |value_str| {
        if (count >= 2) break; // 最多解析2个值

        if (parsePxValue(value_str)) |num| {
            values[count] = num;
            count += 1;
        }
    }

    if (count == 0) return null;

    // 如果只有一个值，同时用于row-gap和column-gap
    if (count == 1) {
        return [2]f32{ values[0], values[0] };
    }

    // 两个值：第一个是row-gap，第二个是column-gap
    return values;
}

/// 从ComputedStyle获取row-gap值
pub fn getRowGap(computed_style: *const cascade.ComputedStyle, containing_size: f32) f32 {
    // 先查找 row-gap
    if (getPropertyLength(computed_style, "row-gap", containing_size)) |gap| {
        return gap;
    }
    // 检查gap简写属性
    // gap可能是长度值（单个值）或关键字值（多值属性，如 "10px 20px"）
    if (getPropertyLength(computed_style, "gap", containing_size)) |gap| {
        // 单个长度值，同时用于row-gap和column-gap
        return gap;
    }
    if (getPropertyKeyword(computed_style, "gap")) |gap_value| {
        // 解析gap简写属性：可能是单个值或两个值（row-gap column-gap）
        if (parseGapShorthand(gap_value)) |gaps| {
            return gaps[0]; // 第一个值是row-gap
        }
    }
    return 0.0; // 默认值
}

/// 从ComputedStyle获取column-gap值
pub fn getColumnGap(computed_style: *const cascade.ComputedStyle, containing_size: f32) f32 {
    // 先查找 column-gap
    if (getPropertyLength(computed_style, "column-gap", containing_size)) |gap| {
        return gap;
    }
    // 检查gap简写属性
    // gap可能是长度值（单个值）或关键字值（多值属性，如 "10px 20px"）
    if (getPropertyLength(computed_style, "gap", containing_size)) |gap| {
        // 单个长度值，同时用于row-gap和column-gap
        return gap;
    }
    if (getPropertyKeyword(computed_style, "gap")) |gap_value| {
        // 解析gap简写属性：可能是单个值或两个值（row-gap column-gap）
        if (parseGapShorthand(gap_value)) |gaps| {
            return gaps[1]; // 第二个值是column-gap（如果只有一个值，gaps[1]也是该值）
        }
    }
    return 0.0; // 默认值
}

/// Grid对齐类型
pub const GridJustifyItems = enum {
    start,
    end,
    center,
    stretch,
};

pub const GridAlignItems = enum {
    start,
    end,
    center,
    stretch,
};

pub const GridJustifyContent = enum {
    start,
    end,
    center,
    stretch,
    space_around,
    space_between,
    space_evenly,
};

pub const GridAlignContent = enum {
    start,
    end,
    center,
    stretch,
    space_around,
    space_between,
    space_evenly,
};

/// 解析justify-items属性
pub fn parseGridJustifyItems(value: []const u8) GridJustifyItems {
    if (std.mem.eql(u8, value, "start")) return .start;
    if (std.mem.eql(u8, value, "end")) return .end;
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "stretch")) return .stretch;
    // 默认值
    return .stretch;
}

/// 解析align-items属性
pub fn parseGridAlignItems(value: []const u8) GridAlignItems {
    if (std.mem.eql(u8, value, "start")) return .start;
    if (std.mem.eql(u8, value, "end")) return .end;
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "stretch")) return .stretch;
    // 默认值
    return .stretch;
}

/// 解析justify-content属性
pub fn parseGridJustifyContent(value: []const u8) GridJustifyContent {
    if (std.mem.eql(u8, value, "start")) return .start;
    if (std.mem.eql(u8, value, "end")) return .end;
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "stretch")) return .stretch;
    if (std.mem.eql(u8, value, "space-around")) return .space_around;
    if (std.mem.eql(u8, value, "space-between")) return .space_between;
    if (std.mem.eql(u8, value, "space-evenly")) return .space_evenly;
    // 默认值
    return .start;
}

/// 解析align-content属性
pub fn parseGridAlignContent(value: []const u8) GridAlignContent {
    if (std.mem.eql(u8, value, "start")) return .start;
    if (std.mem.eql(u8, value, "end")) return .end;
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "stretch")) return .stretch;
    if (std.mem.eql(u8, value, "space-around")) return .space_around;
    if (std.mem.eql(u8, value, "space-between")) return .space_between;
    if (std.mem.eql(u8, value, "space-evenly")) return .space_evenly;
    // 默认值
    return .start;
}

/// 从ComputedStyle获取justify-items属性
pub fn getGridJustifyItems(computed_style: *const cascade.ComputedStyle) GridJustifyItems {
    if (getPropertyKeyword(computed_style, "justify-items")) |value| {
        return parseGridJustifyItems(value);
    }
    return .stretch; // 默认值
}

/// 从ComputedStyle获取align-items属性
pub fn getGridAlignItems(computed_style: *const cascade.ComputedStyle) GridAlignItems {
    if (getPropertyKeyword(computed_style, "align-items")) |value| {
        return parseGridAlignItems(value);
    }
    return .stretch; // 默认值
}

/// 从ComputedStyle获取justify-content属性
pub fn getGridJustifyContent(computed_style: *const cascade.ComputedStyle) GridJustifyContent {
    if (getPropertyKeyword(computed_style, "justify-content")) |value| {
        return parseGridJustifyContent(value);
    }
    return .start; // 默认值
}

/// 从ComputedStyle获取align-content属性
pub fn getGridAlignContent(computed_style: *const cascade.ComputedStyle) GridAlignContent {
    if (getPropertyKeyword(computed_style, "align-content")) |value| {
        const result = parseGridAlignContent(value);
        std.log.warn("[StyleUtils] getGridAlignContent - value='{s}', result={}", .{ value, result });
        return result;
    }
    std.log.warn("[StyleUtils] getGridAlignContent - no align-content property, returning .start", .{});
    return .start; // 默认值
}
