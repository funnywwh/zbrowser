const std = @import("std");
const builtin = @import("builtin");

/// 调试输出函数（只在Debug模式下输出）
/// 使用条件编译，在Release模式下完全移除，避免性能影响
inline fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        std.debug.print(fmt, args);
    }
}
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

/// 解析text-align属性值
pub fn parseTextAlign(value: []const u8) box.TextAlign {
    if (std.mem.eql(u8, value, "left")) return .left;
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "right")) return .right;
    if (std.mem.eql(u8, value, "justify")) return .justify;
    // 默认返回left
    return .left;
}

/// 解析vertical-align属性值
pub fn parseVerticalAlign(value: []const u8) box.VerticalAlign {
    if (std.mem.eql(u8, value, "baseline")) return .baseline;
    if (std.mem.eql(u8, value, "top")) return .top;
    if (std.mem.eql(u8, value, "middle")) return .middle;
    if (std.mem.eql(u8, value, "bottom")) return .bottom;
    if (std.mem.eql(u8, value, "sub")) return .sub;
    if (std.mem.eql(u8, value, "super")) return .super;
    if (std.mem.eql(u8, value, "text-top")) return .text_top;
    if (std.mem.eql(u8, value, "text-bottom")) return .text_bottom;
    // 默认返回baseline
    return .baseline;
}

/// 解析white-space属性值
pub fn parseWhiteSpace(value: []const u8) box.WhiteSpace {
    if (std.mem.eql(u8, value, "normal")) return .normal;
    if (std.mem.eql(u8, value, "nowrap")) return .nowrap;
    if (std.mem.eql(u8, value, "pre")) return .pre;
    if (std.mem.eql(u8, value, "pre-wrap")) return .pre_wrap;
    if (std.mem.eql(u8, value, "pre-line")) return .pre_line;
    // 默认返回normal
    return .normal;
}

/// 解析word-wrap/overflow-wrap属性值
pub fn parseWordWrap(value: []const u8) box.WordWrap {
    if (std.mem.eql(u8, value, "normal")) return .normal;
    if (std.mem.eql(u8, value, "break-word")) return .break_word;
    // 默认返回normal
    return .normal;
}

/// 解析word-break属性值
pub fn parseWordBreak(value: []const u8) box.WordBreak {
    if (std.mem.eql(u8, value, "normal")) return .normal;
    if (std.mem.eql(u8, value, "break-all")) return .break_all;
    if (std.mem.eql(u8, value, "keep-all")) return .keep_all;
    // 默认返回normal
    return .normal;
}

/// 解析text-transform属性值
pub fn parseTextTransform(value: []const u8) box.TextTransform {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "uppercase")) return .uppercase;
    if (std.mem.eql(u8, value, "lowercase")) return .lowercase;
    if (std.mem.eql(u8, value, "capitalize")) return .capitalize;
    // 默认返回none
    return .none;
}

/// 解析box-shadow属性值
/// 格式：offset-x offset-y blur-radius spread-radius color inset?
/// 例如："2px 2px 4px 0px rgba(0,0,0,0.2)" 或 "2px 2px 4px 0px #000 inset"
/// TODO: 完整实现需要支持多个阴影（用逗号分隔）
pub fn parseBoxShadow(value: []const u8) ?box.BoxShadow {
    const trimmed = std.mem.trim(u8, value, " \t\n\r");
    if (trimmed.len == 0) return null;
    
    // 检查是否是"none"
    if (std.mem.eql(u8, trimmed, "none")) return null;
    
    // 简化实现：只支持基本格式
    // 格式：offset-x offset-y blur-radius spread-radius color [inset]
    var parts = std.mem.splitSequence(u8, trimmed, " ");
    var parts_list = std.ArrayList([]const u8){
        .items = &[_][]const u8{},
        .capacity = 0,
    };
    defer parts_list.deinit(std.heap.page_allocator);
    
    while (parts.next()) |part| {
        const trimmed_part = std.mem.trim(u8, part, " \t\n\r");
        if (trimmed_part.len > 0) {
            parts_list.append(std.heap.page_allocator, trimmed_part) catch return null;
        }
    }
    
    if (parts_list.items.len < 5) {
        // 至少需要5个部分（offset-x, offset-y, blur-radius, spread-radius, color）
        return null;
    }
    
    // 检查最后一个部分是否是"inset"
    var has_inset = false;
    var color_index = parts_list.items.len - 1;
    if (std.mem.eql(u8, parts_list.items[parts_list.items.len - 1], "inset")) {
        has_inset = true;
        color_index = parts_list.items.len - 2;
    }
    
    if (color_index < 4) {
        return null; // 没有足够的参数
    }
    
    // 解析offset-x
    const offset_x = parsePxValue(parts_list.items[0]) orelse return null;
    
    // 解析offset-y
    const offset_y = parsePxValue(parts_list.items[1]) orelse return null;
    
    // 解析blur-radius
    const blur_radius = parsePxValue(parts_list.items[2]) orelse return null;
    
    // 解析spread-radius
    const spread_radius = parsePxValue(parts_list.items[3]) orelse return null;
    
    // 解析颜色
    const color_str = parts_list.items[color_index];
    const color = parseColor(color_str) orelse return null;
    
    return box.BoxShadow{
        .offset_x = offset_x,
        .offset_y = offset_y,
        .blur_radius = blur_radius,
        .spread_radius = spread_radius,
        .color_r = color.r,
        .color_g = color.g,
        .color_b = color.b,
        .color_a = color.a,
        .inset = has_inset,
    };
}

/// 解析颜色值
/// 支持格式：#rgb, #rrggbb, rgb(r,g,b), rgba(r,g,b,a)
/// TODO: 完整实现需要支持更多颜色格式
fn parseColor(value: []const u8) ?struct { r: u8, g: u8, b: u8, a: u8 } {
    const trimmed = std.mem.trim(u8, value, " \t\n\r");
    if (trimmed.len == 0) return null;
    
    // 解析十六进制颜色 #rgb 或 #rrggbb
    if (trimmed[0] == '#') {
        const hex_str = trimmed[1..];
        if (hex_str.len == 3) {
            // #rgb格式
            const r_hex = hex_str[0..1];
            const g_hex = hex_str[1..2];
            const b_hex = hex_str[2..3];
            const r = std.fmt.parseInt(u8, r_hex, 16) catch return null;
            const g = std.fmt.parseInt(u8, g_hex, 16) catch return null;
            const b = std.fmt.parseInt(u8, b_hex, 16) catch return null;
            return .{
                .r = r * 17, // 扩展3位到8位
                .g = g * 17,
                .b = b * 17,
                .a = 255,
            };
        } else if (hex_str.len == 6) {
            // #rrggbb格式
            const r_hex = hex_str[0..2];
            const g_hex = hex_str[2..4];
            const b_hex = hex_str[4..6];
            const r = std.fmt.parseInt(u8, r_hex, 16) catch return null;
            const g = std.fmt.parseInt(u8, g_hex, 16) catch return null;
            const b = std.fmt.parseInt(u8, b_hex, 16) catch return null;
            return .{ .r = r, .g = g, .b = b, .a = 255 };
        }
    }
    
    // 解析rgba格式 rgba(r,g,b,a)
    if (std.mem.startsWith(u8, trimmed, "rgba(") and std.mem.endsWith(u8, trimmed, ")")) {
        const inner = trimmed[5..trimmed.len - 1];
        var parts = std.mem.splitSequence(u8, inner, ",");
        var values: [4]f32 = undefined;
        var i: usize = 0;
        while (parts.next()) |part| : (i += 1) {
            if (i >= 4) return null;
            const trimmed_part = std.mem.trim(u8, part, " \t\n\r");
            values[i] = std.fmt.parseFloat(f32, trimmed_part) catch return null;
        }
        if (i != 4) return null;
        
        // rgba值范围：r,g,b在0-255，a在0-1
        return .{
            .r = @as(u8, @intFromFloat(@min(255, @max(0, values[0])))),
            .g = @as(u8, @intFromFloat(@min(255, @max(0, values[1])))),
            .b = @as(u8, @intFromFloat(@min(255, @max(0, values[2])))),
            .a = @as(u8, @intFromFloat(@min(255, @max(0, values[3] * 255)))),
        };
    }
    
    // 解析rgb格式 rgb(r,g,b)
    if (std.mem.startsWith(u8, trimmed, "rgb(") and std.mem.endsWith(u8, trimmed, ")")) {
        const inner = trimmed[4..trimmed.len - 1];
        var parts = std.mem.splitSequence(u8, inner, ",");
        var values: [3]f32 = undefined;
        var i: usize = 0;
        while (parts.next()) |part| : (i += 1) {
            if (i >= 3) return null;
            const trimmed_part = std.mem.trim(u8, part, " \t\n\r");
            values[i] = std.fmt.parseFloat(f32, trimmed_part) catch return null;
        }
        if (i != 3) return null;
        
        return .{
            .r = @as(u8, @intFromFloat(@min(255, @max(0, values[0])))),
            .g = @as(u8, @intFromFloat(@min(255, @max(0, values[1])))),
            .b = @as(u8, @intFromFloat(@min(255, @max(0, values[2])))),
            .a = 255,
        };
    }
    
    return null;
}

/// 解析text-decoration属性值
pub fn parseTextDecoration(value: []const u8) box.TextDecoration {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "underline")) return .underline;
    if (std.mem.eql(u8, value, "line-through")) return .line_through;
    if (std.mem.eql(u8, value, "overline")) return .overline;
    // 默认返回none
    return .none;
}

/// 解析overflow属性值
pub fn parseOverflow(value: []const u8) box.Overflow {
    if (std.mem.eql(u8, value, "visible")) return .visible;
    if (std.mem.eql(u8, value, "hidden")) return .hidden;
    if (std.mem.eql(u8, value, "scroll")) return .scroll;
    if (std.mem.eql(u8, value, "auto")) return .auto;
    // 默认返回visible
    return .visible;
}

/// 解析line-height属性值
/// 支持格式：
/// - 数字值（如"1.5"，表示字体大小的倍数）
/// - 长度值（如"20px"）
/// - 百分比值（如"150%"）
/// - "normal"（默认值）
pub fn parseLineHeight(value: []const u8, _: f32) box.LineHeight {
    const trimmed = std.mem.trim(u8, value, " \t\n\r");
    if (trimmed.len == 0) {
        return .normal;
    }

    // 检查是否是"normal"
    if (std.mem.eql(u8, trimmed, "normal")) {
        return .normal;
    }

    // 尝试解析为数字值（无单位，表示字体大小的倍数）
    if (std.fmt.parseFloat(f32, trimmed)) |number| {
        return .{ .number = number };
    } else |_| {
        // 解析失败，继续尝试其他格式
    }

    // 尝试解析为长度值（px单位）
    if (parsePxValue(trimmed)) |length| {
        return .{ .length = length };
    }

    // 尝试解析为百分比值
    if (trimmed.len > 1 and trimmed[trimmed.len - 1] == '%') {
        if (std.fmt.parseFloat(f32, trimmed[0..trimmed.len - 1])) |percent| {
            return .{ .percent = percent };
        } else |_| {
            // 解析失败
        }
    }

    // 如果都解析失败，返回normal
    return .normal;
}

/// 计算实际行高值（像素）
/// 根据line-height类型和字体大小计算实际的行高
/// 注意：对于h1等标题元素，Chrome使用的默认line-height可能更大（约1.4375）
pub fn computeLineHeight(line_height: box.LineHeight, font_size: f32) f32 {
    return switch (line_height) {
        .normal => {
            // 对于大字体（如h1的32px），Chrome使用的默认line-height约为1.4375
            // 对于小字体（如16px），默认line-height约为1.2
            // 简化实现：根据字体大小调整line-height
            if (font_size >= 32.0) {
                // h1等大标题：使用1.4375（匹配Chrome）
                return font_size * 1.4375;
            } else if (font_size >= 24.0) {
                // h2等中等标题：使用1.35
                return font_size * 1.35;
            } else {
                // 普通文本：使用1.2
                return font_size * 1.2;
            }
        },
        .number => |n| font_size * n,
        .length => |l| l,
        .percent => |p| font_size * p / 100.0,
    };
}

/// 解析border-radius属性值
/// 支持格式："10px"、"0"（作为0px）
/// 返回解析的数值，如果解析失败返回null
pub fn parseBorderRadius(value: []const u8, containing_size: box.Size) ?f32 {
    const trimmed = std.mem.trim(u8, value, " \t\n\r");
    if (trimmed.len == 0) {
        return null;
    }

    // 检查是否是"0"（表示0px）
    if (std.mem.eql(u8, trimmed, "0")) {
        return 0.0;
    }

    // 尝试解析px单位
    if (parsePxValue(trimmed)) |px_value| {
        return px_value;
    }

    // 尝试解析百分比
    if (trimmed.len > 1 and trimmed[trimmed.len - 1] == '%') {
        if (std.fmt.parseFloat(f32, trimmed[0..trimmed.len - 1])) |percent| {
            // 使用宽度和高度中的较小值作为参考（CSS规范）
            const reference = @min(containing_size.width, containing_size.height);
            return reference * percent / 100.0;
        } else |_| {
            return null;
        }
    }

    return null;
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

/// CSS单位计算上下文
/// 包含计算相对单位所需的所有信息
pub const UnitContext = struct {
    /// 包含块尺寸（用于百分比计算）
    containing_size: f32,
    /// 父元素字体大小（用于em单位，默认16px）
    parent_font_size: f32 = 16.0,
    /// 根元素字体大小（用于rem单位，默认16px）
    root_font_size: f32 = 16.0,
    /// 视口宽度（用于vw单位）
    viewport_width: f32 = 800.0,
    /// 视口高度（用于vh单位）
    viewport_height: f32 = 600.0,
};

/// 解析长度值为f32
/// 支持单位：px, em, rem, %, vw, vh, vmin, vmax
pub fn parseLength(value: css_parser.Value, context: UnitContext) f32 {
    return switch (value) {
        .length => |l| {
            const num_value = @as(f32, @floatCast(l.value));

            // 根据单位类型计算
            if (std.mem.eql(u8, l.unit, "px")) {
                return num_value;
            } else if (std.mem.eql(u8, l.unit, "em")) {
                // em: 相对于父元素字体大小
                return num_value * context.parent_font_size;
            } else if (std.mem.eql(u8, l.unit, "rem")) {
                // rem: 相对于根元素字体大小
                return num_value * context.root_font_size;
            } else if (std.mem.eql(u8, l.unit, "vw")) {
                // vw: 视口宽度的1%
                return num_value * context.viewport_width / 100.0;
            } else if (std.mem.eql(u8, l.unit, "vh")) {
                // vh: 视口高度的1%
                return num_value * context.viewport_height / 100.0;
            } else if (std.mem.eql(u8, l.unit, "vmin")) {
                // vmin: 视口宽度和高度中较小值的1%
                const min_viewport = @min(context.viewport_width, context.viewport_height);
                return num_value * min_viewport / 100.0;
            } else if (std.mem.eql(u8, l.unit, "vmax")) {
                // vmax: 视口宽度和高度中较大值的1%
                const max_viewport = @max(context.viewport_width, context.viewport_height);
                return num_value * max_viewport / 100.0;
            }
            // 未知单位，返回0
            return 0;
        },
        .percentage => |p| {
            // 百分比：相对于包含块尺寸
            return context.containing_size * @as(f32, @floatCast(p / 100.0));
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
        return result;
    }
    return null;
}

/// 从ComputedStyle获取长度值
/// 支持单位：px, em, rem, %, vw, vh, vmin, vmax
pub fn getPropertyLength(computed_style: *const cascade.ComputedStyle, name: []const u8, context: UnitContext) ?f32 {
    if (computed_style.getProperty(name)) |decl| {
        // 只返回长度值，如果是其他类型（如关键字），返回null
        return switch (decl.value) {
            .length => |l| {
                const num_value = @as(f32, @floatCast(l.value));

                // 根据单位类型计算
                if (std.mem.eql(u8, l.unit, "px")) {
                    return num_value;
                } else if (std.mem.eql(u8, l.unit, "em")) {
                    return num_value * context.parent_font_size;
                } else if (std.mem.eql(u8, l.unit, "rem")) {
                    return num_value * context.root_font_size;
                } else if (std.mem.eql(u8, l.unit, "vw")) {
                    return num_value * context.viewport_width / 100.0;
                } else if (std.mem.eql(u8, l.unit, "vh")) {
                    return num_value * context.viewport_height / 100.0;
                } else if (std.mem.eql(u8, l.unit, "vmin")) {
                    const min_viewport = @min(context.viewport_width, context.viewport_height);
                    return num_value * min_viewport / 100.0;
                } else if (std.mem.eql(u8, l.unit, "vmax")) {
                    const max_viewport = @max(context.viewport_width, context.viewport_height);
                    return num_value * max_viewport / 100.0;
                }
                // 未知单位，返回null
                return null;
            },
            .percentage => |p| {
                return context.containing_size * @as(f32, @floatCast(p / 100.0));
            },
            else => null, // 关键字值或其他类型，返回null
        };
    }
    return null;
}

/// 创建单位计算上下文（简化版本，使用默认值）
/// 用于向后兼容，当只需要containing_size时使用
pub fn createUnitContext(containing_size: f32) UnitContext {
    return UnitContext{
        .containing_size = containing_size,
        .parent_font_size = 16.0,
        .root_font_size = 16.0,
        .viewport_width = 800.0,
        .viewport_height = 600.0,
    };
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
    }

    // 解析float
    if (getPropertyKeyword(computed_style, "float")) |float_value| {
        layout_box.float = parseFloatType(float_value);
    }

    // 解析定位属性（top, right, bottom, left）
    // TODO: 获取实际的字体大小和视口尺寸
    const top_context = createUnitContext(containing_size.height);
    if (getPropertyLength(computed_style, "top", top_context)) |top| {
        layout_box.position_top = top;
    }
    const right_context = createUnitContext(containing_size.width);
    if (getPropertyLength(computed_style, "right", right_context)) |right| {
        layout_box.position_right = right;
    }
    const bottom_context = createUnitContext(containing_size.height);
    if (getPropertyLength(computed_style, "bottom", bottom_context)) |bottom| {
        layout_box.position_bottom = bottom;
    }
    const left_context = createUnitContext(containing_size.width);
    if (getPropertyLength(computed_style, "left", left_context)) |left| {
        layout_box.position_left = left;
    }

    // 先解析font-size（margin的em单位需要相对于元素自己的font-size）
    var element_font_size: f32 = 16.0; // 默认字体大小
    const font_size_context = createUnitContext(containing_size.width);
    if (getPropertyLength(computed_style, "font-size", font_size_context)) |fs| {
        element_font_size = fs;
        // 调试日志：记录大字体元素的font-size
        if (fs > 24.0) {
            const tag_name = if (layout_box.node.node_type == .element)
                if (layout_box.node.asElement()) |elem| elem.tag_name else "unknown"
            else "text";
            debugPrint("[STYLE] {s} font-size parsed: {d:.1}px\n", .{ tag_name, fs });
        }
    }

    // 解析margin（使用元素自己的font-size）
    parseMargin(layout_box, computed_style, containing_size, element_font_size);

    // 解析padding
    parsePadding(layout_box, computed_style, containing_size);

    // 解析grid-row和grid-column（Grid子元素的属性）
    if (getGridRow(computed_style)) |grid_row| {
        layout_box.grid_row_start = grid_row.start;
        layout_box.grid_row_end = grid_row.end;
    }
    if (getGridColumn(computed_style)) |grid_column| {
        layout_box.grid_column_start = grid_column.start;
        layout_box.grid_column_end = grid_column.end;
    }

    // 解析text-align
    if (getPropertyKeyword(computed_style, "text-align")) |text_align_value| {
        layout_box.text_align = parseTextAlign(text_align_value);
    }

    // 解析text-decoration
    if (getPropertyKeyword(computed_style, "text-decoration")) |text_decoration_value| {
        layout_box.text_decoration = parseTextDecoration(text_decoration_value);
    }

    // 解析line-height
    // 使用之前解析的element_font_size（用于计算实际行高）
    const font_size: f32 = element_font_size; // 使用之前解析的font-size
    
    if (getPropertyKeyword(computed_style, "line-height")) |line_height_value| {
        layout_box.line_height = parseLineHeight(line_height_value, font_size);
    } else if (getPropertyLength(computed_style, "line-height", createUnitContext(containing_size.width))) |line_height_length| {
        // line-height是长度值（如20px）
        layout_box.line_height = .{ .length = line_height_length };
    }

    // 解析overflow
    if (getPropertyKeyword(computed_style, "overflow")) |overflow_value| {
        layout_box.overflow = parseOverflow(overflow_value);
    }

    // 解析letter-spacing
    const letter_spacing_context = createUnitContext(containing_size.width);
    if (getPropertyLength(computed_style, "letter-spacing", letter_spacing_context)) |spacing| {
        layout_box.letter_spacing = spacing;
    } else if (getPropertyKeyword(computed_style, "letter-spacing")) |spacing_value| {
        // 支持normal关键字（表示0）
        if (std.mem.eql(u8, spacing_value, "normal")) {
            layout_box.letter_spacing = null; // null表示使用默认间距（0）
        }
    }

    // 解析opacity
    if (getPropertyKeyword(computed_style, "opacity")) |opacity_value| {
        // 尝试解析为数字（0.0到1.0）
        if (std.fmt.parseFloat(f32, opacity_value)) |opacity| {
            // 限制在0.0到1.0范围内
            layout_box.opacity = @max(0.0, @min(1.0, opacity));
        } else |_| {
            // 解析失败，使用默认值1.0
        }
    }

    // 解析z-index
    if (getPropertyKeyword(computed_style, "z-index")) |z_index_value| {
        // 支持auto关键字（表示null）
        if (std.mem.eql(u8, z_index_value, "auto")) {
            layout_box.z_index = null; // null表示使用auto堆叠顺序
        } else {
            // 尝试解析为整数
            if (std.fmt.parseInt(i32, z_index_value, 10)) |z_index| {
                layout_box.z_index = z_index;
            } else |_| {
                // 解析失败，使用默认值null（auto）
            }
        }
    }

    // 解析vertical-align
    if (getPropertyKeyword(computed_style, "vertical-align")) |vertical_align_value| {
        layout_box.vertical_align = parseVerticalAlign(vertical_align_value);
    }

    // 解析white-space
    if (getPropertyKeyword(computed_style, "white-space")) |white_space_value| {
        layout_box.white_space = parseWhiteSpace(white_space_value);
    }

    // 解析word-wrap/overflow-wrap（overflow-wrap是word-wrap的别名）
    if (getPropertyKeyword(computed_style, "word-wrap")) |word_wrap_value| {
        layout_box.word_wrap = parseWordWrap(word_wrap_value);
    } else if (getPropertyKeyword(computed_style, "overflow-wrap")) |overflow_wrap_value| {
        layout_box.word_wrap = parseWordWrap(overflow_wrap_value);
    }

    // 解析word-break
    if (getPropertyKeyword(computed_style, "word-break")) |word_break_value| {
        layout_box.word_break = parseWordBreak(word_break_value);
    }

    // 解析text-transform
    if (getPropertyKeyword(computed_style, "text-transform")) |text_transform_value| {
        layout_box.text_transform = parseTextTransform(text_transform_value);
    }

    // 解析box-shadow
    if (getPropertyKeyword(computed_style, "box-shadow")) |box_shadow_value| {
        layout_box.box_shadow = parseBoxShadow(box_shadow_value);
    }

    // 解析border-radius
    if (getPropertyLength(computed_style, "border-radius", createUnitContext(containing_size.width))) |border_radius_value| {
        layout_box.box_model.border_radius = border_radius_value;
    } else if (getPropertyKeyword(computed_style, "border-radius")) |border_radius_value| {
        // 尝试解析关键字（如"0"）
        if (parseBorderRadius(border_radius_value, containing_size)) |radius| {
            layout_box.box_model.border_radius = radius;
        }
    }

    // 解析box-sizing（需要在width/height之前解析，因为width/height的解析依赖于box-sizing）
    if (getPropertyKeyword(computed_style, "box-sizing")) |box_sizing_value| {
        if (std.mem.eql(u8, box_sizing_value, "border-box")) {
            layout_box.box_model.box_sizing = .border_box;
        } else if (std.mem.eql(u8, box_sizing_value, "content-box")) {
            layout_box.box_model.box_sizing = .content_box;
        }
    }

    // 解析width和height
    // 注意：width和height的解析需要考虑box-sizing
    // 如果box-sizing是border-box，width/height包含padding和border
    // 如果box-sizing是content-box，width/height只包含内容区域
    const width_context = createUnitContext(containing_size.width);
    if (getPropertyLength(computed_style, "width", width_context)) |width| {
        // 根据box-sizing调整
        if (layout_box.box_model.box_sizing == .border_box) {
            // border-box: width包含padding和border，需要减去这些值得到content width
            const padding_horizontal = layout_box.box_model.padding.left + layout_box.box_model.padding.right;
            const border_horizontal = layout_box.box_model.border.left + layout_box.box_model.border.right;
            layout_box.box_model.content.width = width - padding_horizontal - border_horizontal;
        } else {
            // content-box: width直接是content width
            layout_box.box_model.content.width = width;
        }
    }
    
    const height_context = createUnitContext(containing_size.height);
    if (getPropertyLength(computed_style, "height", height_context)) |height| {
        // 根据box-sizing调整
        if (layout_box.box_model.box_sizing == .border_box) {
            // border-box: height包含padding和border，需要减去这些值得到content height
            const padding_vertical = layout_box.box_model.padding.top + layout_box.box_model.padding.bottom;
            const border_vertical = layout_box.box_model.border.top + layout_box.box_model.border.bottom;
            layout_box.box_model.content.height = height - padding_vertical - border_vertical;
        } else {
            // content-box: height直接是content height
            layout_box.box_model.content.height = height;
        }
    }

    // 解析min-width和min-height
    if (getPropertyLength(computed_style, "min-width", width_context)) |min_width| {
        layout_box.box_model.min_width = min_width;
    }
    if (getPropertyLength(computed_style, "min-height", height_context)) |min_height| {
        layout_box.box_model.min_height = min_height;
    }

    // 解析max-width和max-height
    if (getPropertyLength(computed_style, "max-width", width_context)) |max_width| {
        layout_box.box_model.max_width = max_width;
    }
    if (getPropertyLength(computed_style, "max-height", height_context)) |max_height| {
        layout_box.box_model.max_height = max_height;
    }

    // 解析border（简写属性）
    // 格式：border: <width> <style> <color>
    // 例如：border: 2px solid #2196f3
    if (getPropertyKeyword(computed_style, "border")) |border_value| {
        if (parseBorderShorthand(border_value, width_context)) |border_info| {
            // 应用border宽度到所有边
            if (border_info.width) |width| {
                layout_box.box_model.border.top = width;
                layout_box.box_model.border.right = width;
                layout_box.box_model.border.bottom = width;
                layout_box.box_model.border.left = width;
            }
        }
    } else {
        // 如果没有border简写属性，尝试解析单独的border-width属性
        const border_width_context = createUnitContext(containing_size.width);
        if (getPropertyLength(computed_style, "border-width", border_width_context)) |width| {
            layout_box.box_model.border.top = width;
            layout_box.box_model.border.right = width;
            layout_box.box_model.border.bottom = width;
            layout_box.box_model.border.left = width;
        } else {
            // 尝试解析单独的border-top-width等属性
            if (getPropertyLength(computed_style, "border-top-width", border_width_context)) |width| {
                layout_box.box_model.border.top = width;
            }
            if (getPropertyLength(computed_style, "border-right-width", border_width_context)) |width| {
                layout_box.box_model.border.right = width;
            }
            if (getPropertyLength(computed_style, "border-bottom-width", border_width_context)) |width| {
                layout_box.box_model.border.bottom = width;
            }
            if (getPropertyLength(computed_style, "border-left-width", border_width_context)) |width| {
                layout_box.box_model.border.left = width;
            }
        }
    }
}

/// 解析border简写属性
/// 格式：border: <width> <style> <color>
/// 例如：border: 2px solid #2196f3
/// 返回解析的宽度、样式和颜色（用于布局阶段只需要宽度）
fn parseBorderShorthand(border_value: []const u8, _: UnitContext) ?struct { width: ?f32, style: ?[]const u8 } {
    // 按空格分割值
    var parts = std.mem.splitSequence(u8, border_value, " ");
    var width: ?f32 = null;
    var style: ?[]const u8 = null;

    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\n\r");
        if (trimmed.len == 0) continue;

        // 检查是否是长度值（如 "2px"）
        if (parsePxValue(trimmed)) |px_value| {
            width = px_value;
            continue;
        }

        // 检查是否是边框样式关键字（solid, dashed, dotted等）
        if (std.mem.eql(u8, trimmed, "solid") or
            std.mem.eql(u8, trimmed, "dashed") or
            std.mem.eql(u8, trimmed, "dotted") or
            std.mem.eql(u8, trimmed, "double") or
            std.mem.eql(u8, trimmed, "none"))
        {
            style = trimmed;
            continue;
        }

        // 检查是否是颜色值（以#开头）- 在布局阶段不需要颜色，但可以识别
        if (trimmed.len > 0 and trimmed[0] == '#') {
            // 颜色值，跳过（布局阶段不需要）
            continue;
        }
    }

    return .{ .width = width, .style = style };
}

/// 解析margin属性
/// 支持格式：
/// - margin: 10px (所有边)
/// - margin: 10px 0 (上下 左右)
/// - margin: 10px 0 5px 0 (上 右 下 左)
/// - margin-top, margin-right, margin-bottom, margin-left (单独属性)
fn parseMargin(layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, containing_size: box.Size, element_font_size: f32) void {
    // 先检查单独的margin属性
    // 注意：margin的em单位是相对于元素自己的font-size，而不是父元素的font-size
    var margin_top_context = createUnitContext(containing_size.height);
    margin_top_context.parent_font_size = element_font_size; // 使用元素自己的font-size
    if (getPropertyLength(computed_style, "margin-top", margin_top_context)) |top| {
        layout_box.box_model.margin.top = top;
    }
    var margin_right_context = createUnitContext(containing_size.width);
    margin_right_context.parent_font_size = element_font_size;
    if (getPropertyLength(computed_style, "margin-right", margin_right_context)) |right| {
        layout_box.box_model.margin.right = right;
    }
    var margin_bottom_context = createUnitContext(containing_size.height);
    margin_bottom_context.parent_font_size = element_font_size;
    if (getPropertyLength(computed_style, "margin-bottom", margin_bottom_context)) |bottom| {
        layout_box.box_model.margin.bottom = bottom;
    }
    var margin_left_context = createUnitContext(containing_size.width);
    margin_left_context.parent_font_size = element_font_size;
    if (getPropertyLength(computed_style, "margin-left", margin_left_context)) |left| {
        layout_box.box_model.margin.left = left;
    }

    // 检查margin简写属性（会覆盖单独属性）
    // 先尝试从length获取（如果margin是单个值，可能被解析为length）
    var margin_context = createUnitContext(containing_size.width);
    margin_context.parent_font_size = element_font_size; // 使用元素自己的font-size
    if (getPropertyLength(computed_style, "margin", margin_context)) |margin_length| {
        // 单个长度值，所有边都是这个值
        layout_box.box_model.margin.top = margin_length;
        layout_box.box_model.margin.right = margin_length;
        layout_box.box_model.margin.bottom = margin_length;
        layout_box.box_model.margin.left = margin_length;
    } else if (getPropertyKeyword(computed_style, "margin")) |margin_value| {
        parseMarginShorthand(layout_box, margin_value, containing_size, element_font_size);
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
/// 注意：parseFourSidesShorthand返回的是字符串值，需要解析为长度值
/// TODO: 完整实现需要解析em单位（相对于element_font_size）
fn parseMarginShorthand(layout_box: *box.LayoutBox, margin_value: []const u8, _: box.Size, element_font_size: f32) void {
    // TODO: 完整实现需要解析margin简写属性中的em单位
    // 当前简化实现：parseFourSidesShorthand只返回字符串，需要进一步解析
    // 暂时跳过，因为margin简写属性通常已经在CSS中解析为单独属性
    _ = layout_box;
    _ = margin_value;
    _ = element_font_size;
}

/// 解析padding属性
/// 支持格式：
/// - padding: 10px (所有边)
/// - padding: 10px 0 (上下 左右)
/// - padding: 10px 0 5px 0 (上 右 下 左)
/// - padding-top, padding-right, padding-bottom, padding-left (单独属性)
fn parsePadding(layout_box: *box.LayoutBox, computed_style: *const cascade.ComputedStyle, containing_size: box.Size) void {
    // 先检查单独的padding属性
    const padding_top_context = createUnitContext(containing_size.height);
    if (getPropertyLength(computed_style, "padding-top", padding_top_context)) |top| {
        layout_box.box_model.padding.top = top;
    }
    const padding_right_context = createUnitContext(containing_size.width);
    if (getPropertyLength(computed_style, "padding-right", padding_right_context)) |right| {
        layout_box.box_model.padding.right = right;
    }
    const padding_bottom_context = createUnitContext(containing_size.height);
    if (getPropertyLength(computed_style, "padding-bottom", padding_bottom_context)) |bottom| {
        layout_box.box_model.padding.bottom = bottom;
    }
    const padding_left_context = createUnitContext(containing_size.width);
    if (getPropertyLength(computed_style, "padding-left", padding_left_context)) |left| {
        layout_box.box_model.padding.left = left;
    }

    // 检查padding简写属性（会覆盖单独属性）
    // 先尝试从length获取（如果padding是单个值，可能被解析为length）
    const padding_context = createUnitContext(containing_size.width);
    if (getPropertyLength(computed_style, "padding", padding_context)) |padding_length| {
        // 单个长度值，所有边都是这个值
        layout_box.box_model.padding.top = padding_length;
        layout_box.box_model.padding.right = padding_length;
        layout_box.box_model.padding.bottom = padding_length;
        layout_box.box_model.padding.left = padding_length;
    } else if (getPropertyKeyword(computed_style, "padding")) |padding_value| {
        parsePaddingShorthand(layout_box, padding_value, containing_size);
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

/// 解析flex简写属性
/// 支持格式：
/// - "1" -> grow=1, shrink=1, basis=auto
/// - "1 2" -> grow=1, shrink=2, basis=auto
/// - "1 2 100px" -> grow=1, shrink=2, basis=100px
/// - "auto" -> grow=1, shrink=1, basis=auto
/// - "none" -> grow=0, shrink=0, basis=auto
/// - "initial" -> grow=0, shrink=1, basis=auto
fn parseFlexShorthand(value: []const u8, containing_size: f32) FlexItemProperties {
    const trimmed = std.mem.trim(u8, value, " \t\n\r");
    if (trimmed.len == 0) {
        return .{ .grow = 0.0, .shrink = 1.0, .basis = null };
    }

    // 检查关键字
    if (std.mem.eql(u8, trimmed, "auto")) {
        return .{ .grow = 1.0, .shrink = 1.0, .basis = null };
    }
    if (std.mem.eql(u8, trimmed, "none")) {
        return .{ .grow = 0.0, .shrink = 0.0, .basis = null };
    }
    if (std.mem.eql(u8, trimmed, "initial")) {
        return .{ .grow = 0.0, .shrink = 1.0, .basis = null };
    }

    // 按空格分割值
    var parts = std.mem.splitSequence(u8, trimmed, " ");
    var grow: ?f32 = null;
    var shrink: ?f32 = null;
    var basis: ?f32 = null;

    var part_count: usize = 0;
    while (parts.next()) |part| {
        const part_trimmed = std.mem.trim(u8, part, " \t\n\r");
        if (part_trimmed.len == 0) continue;
        part_count += 1;

        // 尝试解析为数字（grow或shrink）
        if (std.fmt.parseFloat(f32, part_trimmed)) |num| {
            if (grow == null) {
                grow = num;
            } else if (shrink == null) {
                shrink = num;
            } else {
                // 第三个值应该是basis，但如果是数字，也作为basis处理（如"0"表示0px）
                // 实际上，basis应该是长度值，这里简化处理
            }
        } else |_| {
            // 解析失败，可能是长度值（basis）
            // 尝试解析为长度值
            if (parsePxValue(part_trimmed)) |px_value| {
                basis = px_value;
            } else if (part_trimmed.len > 1 and part_trimmed[part_trimmed.len - 1] == '%') {
                // 百分比值
                if (std.fmt.parseFloat(f32, part_trimmed[0..part_trimmed.len - 1])) |percent| {
                    basis = containing_size * percent / 100.0;
                } else |_| {
                    // 解析失败，忽略
                }
            } else if (std.mem.eql(u8, part_trimmed, "auto")) {
                basis = null; // auto
            } else {
                // 无法解析，忽略
            }
        }
    }

    // 根据解析的值设置结果
    return .{
        .grow = grow orelse 0.0,
        .shrink = shrink orelse (if (grow != null) 1.0 else 1.0), // 如果指定了grow，shrink默认为1.0
        .basis = basis,
    };
}

/// 从ComputedStyle获取flex-basis值
/// 返回null表示auto
pub fn getFlexBasis(computed_style: *const cascade.ComputedStyle, containing_size: f32) ?f32 {
    // 先检查flex-basis属性
    const context = createUnitContext(containing_size);
    if (getPropertyLength(computed_style, "flex-basis", context)) |basis| {
        return basis;
    }
    // 检查flex简写属性
    if (getPropertyKeyword(computed_style, "flex")) |flex_value| {
        const flex_props = parseFlexShorthand(flex_value, containing_size);
        return flex_props.basis;
    }
    return null; // auto
}

/// 从ComputedStyle获取完整的flex属性
pub fn getFlexProperties(computed_style: *const cascade.ComputedStyle, containing_size: f32) FlexItemProperties {
    // 先检查flex简写属性（优先级最高）
    if (getPropertyKeyword(computed_style, "flex")) |flex_value| {
        return parseFlexShorthand(flex_value, containing_size);
    }
    
    // 如果没有flex简写属性，分别获取各个属性
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

/// Grid轨道值类型
pub const GridTrackValue = union(enum) {
    /// 固定像素值
    fixed: f32,
    /// fr单位（fractional unit）
    fr: f32,
    /// minmax()函数：minmax(min, max)
    minmax: struct {
        min: f32, // 最小值（固定值或fr单位）
        max: f32, // 最大值（固定值或fr单位）
        min_is_fr: bool, // min是否为fr单位
        max_is_fr: bool, // max是否为fr单位
    },
};

/// Grid属性解析
/// 解析grid-template-rows/columns
/// 支持格式：
/// - 固定值：如"100px 200px"
/// - repeat()函数：如"repeat(3, 1fr)"或"repeat(3, 100px)"
/// - fr单位：如"1fr 2fr 1fr"
/// TODO: 完整实现需要支持minmax()等
pub fn parseGridTemplate(value: []const u8, allocator: std.mem.Allocator) !std.ArrayList(GridTrackValue) {
    var tracks = std.ArrayList(GridTrackValue){
        .items = &[_]GridTrackValue{},
        .capacity = 0,
    };
    errdefer tracks.deinit(allocator);

    // 去除前后空格
    const trimmed = std.mem.trim(u8, value, " \t\n\r");
    if (trimmed.len == 0) {
        return tracks;
    }

    // 解析每个轨道值
    // 注意：repeat()函数内部可能包含空格（如"repeat(3, 1fr)"），需要特殊处理
    var i: usize = 0;
    while (i < trimmed.len) {
        // 跳过空白字符
        while (i < trimmed.len and (trimmed[i] == ' ' or trimmed[i] == '\t' or trimmed[i] == '\n' or trimmed[i] == '\r')) {
            i += 1;
        }
        if (i >= trimmed.len) break;

        // 检查是否是repeat()函数
        if (i + 7 <= trimmed.len and std.mem.eql(u8, trimmed[i..i+7], "repeat(")) {
            // 找到repeat()函数的结束位置（匹配的右括号）
            var depth: usize = 0;
            var j = i;
            while (j < trimmed.len) {
                if (trimmed[j] == '(') {
                    depth += 1;
                } else if (trimmed[j] == ')') {
                    depth -= 1;
                    if (depth == 0) {
                        // 找到匹配的右括号
                        const repeat_str = trimmed[i..j+1];
                        var repeat_tracks = parseRepeatFunction(repeat_str, allocator) catch {
                            i = j + 1;
                            continue;
                        };
                        defer repeat_tracks.deinit(allocator);
                        // 将repeat的结果添加到tracks
                        for (repeat_tracks.items) |track| {
                            try tracks.append(allocator, track);
                        }
                        i = j + 1;
                        break;
                    }
                }
                j += 1;
            }
            if (j >= trimmed.len) {
                // 没有找到匹配的右括号，跳过
                break;
            }
        } else if (i + 7 <= trimmed.len and std.mem.eql(u8, trimmed[i..i+7], "minmax(")) {
            // 检查是否是minmax()函数
            // 找到minmax()函数的结束位置（匹配的右括号）
            var depth: usize = 0;
            var j = i;
            while (j < trimmed.len) {
                if (trimmed[j] == '(') {
                    depth += 1;
                } else if (trimmed[j] == ')') {
                    depth -= 1;
                    if (depth == 0) {
                        // 找到匹配的右括号
                        const minmax_str = trimmed[i..j+1];
                        if (parseMinmaxFunction(minmax_str)) |minmax_track| {
                            try tracks.append(allocator, minmax_track);
                        } else {
                        }
                        i = j + 1;
                        break;
                    }
                }
                j += 1;
            }
            if (j >= trimmed.len) {
                // 没有找到匹配的右括号，跳过
                break;
            }
        } else {
            // 解析单个轨道值（找到下一个空格或字符串结束）
            var j = i;
            while (j < trimmed.len and trimmed[j] != ' ' and trimmed[j] != '\t' and trimmed[j] != '\n' and trimmed[j] != '\r') {
                j += 1;
            }
            const track_str = trimmed[i..j];
            if (parseGridTrackValue(track_str)) |track| {
                try tracks.append(allocator, track);
            } else {
            }
            i = j;
        }
    }

    return tracks;
}

/// 解析repeat()函数
/// 格式：repeat(count, track)
/// 例如：repeat(3, 1fr) 或 repeat(3, 100px)
fn parseRepeatFunction(value: []const u8, allocator: std.mem.Allocator) !std.ArrayList(GridTrackValue) {
    // 去除"repeat("前缀和")"后缀
    if (!std.mem.startsWith(u8, value, "repeat(")) return error.InvalidRepeat;
    if (!std.mem.endsWith(u8, value, ")")) return error.InvalidRepeat;

    const inner = std.mem.trim(u8, value[7..value.len - 1], " \t\n\r");
    if (inner.len == 0) return error.InvalidRepeat;

    // 查找逗号分隔符
    const comma_pos = std.mem.indexOf(u8, inner, ",") orelse return error.InvalidRepeat;
    const count_str = std.mem.trim(u8, inner[0..comma_pos], " \t\n\r");
    const track_str = std.mem.trim(u8, inner[comma_pos + 1..], " \t\n\r");

    // 解析重复次数
    const count = std.fmt.parseInt(usize, count_str, 10) catch return error.InvalidRepeat;
    if (count == 0) return error.InvalidRepeat;

    // 解析轨道值
    const track = parseGridTrackValue(track_str) orelse return error.InvalidRepeat;

    // 创建结果数组
    var tracks = std.ArrayList(GridTrackValue){
        .items = &[_]GridTrackValue{},
        .capacity = 0,
    };
    errdefer tracks.deinit(allocator);

    // 重复添加轨道值
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try tracks.append(allocator, track);
    }

    return tracks;
}

/// 解析minmax()函数
/// 格式：minmax(min, max)
/// 例如：minmax(100px, 1fr) 或 minmax(1fr, 2fr)
fn parseMinmaxFunction(value: []const u8) ?GridTrackValue {
    // 去除"minmax("前缀和")"后缀
    if (!std.mem.startsWith(u8, value, "minmax(")) return null;
    if (!std.mem.endsWith(u8, value, ")")) return null;

    const inner = std.mem.trim(u8, value[7..value.len - 1], " \t\n\r");
    if (inner.len == 0) return null;

    // 查找逗号分隔符
    const comma_pos = std.mem.indexOf(u8, inner, ",") orelse return null;
    const min_str = std.mem.trim(u8, inner[0..comma_pos], " \t\n\r");
    const max_str = std.mem.trim(u8, inner[comma_pos + 1..], " \t\n\r");

    // 解析min值
    var min_value: f32 = 0;
    var min_is_fr = false;
    if (std.mem.endsWith(u8, min_str, "fr")) {
        const num_str = min_str[0..min_str.len - 2];
        if (std.fmt.parseFloat(f32, num_str)) |num| {
            if (num >= 0) {
                min_value = num;
                min_is_fr = true;
            } else {
                return null;
            }
        } else |_| {
            return null;
        }
    } else if (parsePxValue(min_str)) |num| {
        min_value = num;
        min_is_fr = false;
    } else {
        // 不支持auto、min-content、max-content等，返回null
        return null;
    }

    // 解析max值
    var max_value: f32 = 0;
    var max_is_fr = false;
    if (std.mem.endsWith(u8, max_str, "fr")) {
        const num_str = max_str[0..max_str.len - 2];
        if (std.fmt.parseFloat(f32, num_str)) |num| {
            if (num >= 0) {
                max_value = num;
                max_is_fr = true;
            } else {
                return null;
            }
        } else |_| {
            return null;
        }
    } else if (parsePxValue(max_str)) |num| {
        max_value = num;
        max_is_fr = false;
    } else {
        // 不支持auto、min-content、max-content等，返回null
        return null;
    }

    return GridTrackValue{
        .minmax = .{
            .min = min_value,
            .max = max_value,
            .min_is_fr = min_is_fr,
            .max_is_fr = max_is_fr,
        },
    };
}

/// 解析单个Grid轨道值
/// 支持格式：
/// - 固定值：如"100px"
/// - fr单位：如"1fr"
/// - minmax()函数：如"minmax(100px, 1fr)"
fn parseGridTrackValue(value: []const u8) ?GridTrackValue {
    const trimmed = std.mem.trim(u8, value, " \t\n\r");
    if (trimmed.len == 0) return null;

    // 检查是否是minmax()函数
    if (std.mem.startsWith(u8, trimmed, "minmax(")) {
        return parseMinmaxFunction(trimmed);
    }

    // 检查是否是fr单位
    if (std.mem.endsWith(u8, trimmed, "fr")) {
        const num_str = trimmed[0..trimmed.len - 2];
        if (std.fmt.parseFloat(f32, num_str)) |num| {
            if (num >= 0) {
                return GridTrackValue{ .fr = num };
            }
        } else |_| {
            return null;
        }
    }

    // 检查是否是px单位
    if (parsePxValue(trimmed)) |num| {
        return GridTrackValue{ .fixed = num };
    }

    return null;
}

/// 从ComputedStyle获取Grid属性
pub fn getGridTemplateRows(computed_style: *const cascade.ComputedStyle, allocator: std.mem.Allocator) !std.ArrayList(GridTrackValue) {
    if (getPropertyKeyword(computed_style, "grid-template-rows")) |value| {
        return parseGridTemplate(value, allocator);
    }
    // 默认返回空列表
    return std.ArrayList(GridTrackValue){
        .items = &[_]GridTrackValue{},
        .capacity = 0,
    };
}

pub fn getGridTemplateColumns(computed_style: *const cascade.ComputedStyle, allocator: std.mem.Allocator) !std.ArrayList(GridTrackValue) {
    if (computed_style.getProperty("grid-template-columns")) |decl| {
        const value_str = switch (decl.value) {
            .keyword => |k| k,
            .length => |l| blk: {
                // 将长度值转换为字符串（简化：只支持px）
                var buf: [32]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}px", .{l.value}) catch "0px";
                break :blk str;
            },
            else => {
                return std.ArrayList(GridTrackValue){
                    .items = &[_]GridTrackValue{},
                    .capacity = 0,
                };
            },
        };
        return parseGridTemplate(value_str, allocator);
    }
    // 默认返回空列表
    return std.ArrayList(GridTrackValue){
        .items = &[_]GridTrackValue{},
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
    const context = createUnitContext(containing_size);
    if (getPropertyLength(computed_style, "row-gap", context)) |gap| {
        return gap;
    }
    // 检查gap简写属性
    // gap可能是长度值（单个值）或关键字值（多值属性，如 "10px 20px"）
    if (getPropertyLength(computed_style, "gap", context)) |gap| {
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
    const context = createUnitContext(containing_size);
    if (getPropertyLength(computed_style, "column-gap", context)) |gap| {
        return gap;
    }
    // 检查gap简写属性
    // gap可能是长度值（单个值）或关键字值（多值属性，如 "10px 20px"）
    if (getPropertyLength(computed_style, "gap", context)) |gap| {
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

/// Grid行/列位置解析结果
pub const GridLine = struct {
    start: ?usize,
    end: ?usize,
};

/// 解析grid-row或grid-column属性值
/// 支持格式：
/// - "1 / 3" - 从第1行/列到第3行/列（不包含第3行/列，即跨越2行/列）
/// - "1" - 只指定起始位置，结束位置自动（即只占1行/列）
/// - "span 2" - 跨越2行/列（需要知道起始位置，但这里简化处理，返回null表示需要自动计算）
/// 返回解析结果，如果解析失败返回null
pub fn parseGridLine(value: []const u8) ?GridLine {
    // 去除前后空格
    var trimmed = std.mem.trim(u8, value, " \t\n\r");
    if (trimmed.len == 0) return null;

    // 检查是否包含 "/"（表示范围）
    if (std.mem.indexOf(u8, trimmed, "/")) |slash_pos| {
        // 格式：start / end
        const start_str = std.mem.trim(u8, trimmed[0..slash_pos], " \t\n\r");
        const end_str = std.mem.trim(u8, trimmed[slash_pos + 1..], " \t\n\r");

        // 解析起始位置
        const start = parseGridLineNumber(start_str) orelse return null;
        // 解析结束位置
        const end = parseGridLineNumber(end_str) orelse return null;

        // 验证：结束位置必须大于起始位置
        if (end <= start) return null;

        return GridLine{
            .start = start,
            .end = end,
        };
    }

    // 检查是否是 "span N" 格式
    if (std.mem.startsWith(u8, trimmed, "span ")) {
        // 简化处理：span格式需要知道起始位置，这里返回null表示需要自动计算
        // TODO: 完整实现需要支持span格式
        return null;
    }

    // 单个数字：只指定起始位置
    if (parseGridLineNumber(trimmed)) |start| {
        return GridLine{
            .start = start,
            .end = start + 1, // 默认只占1行/列
        };
    }

    return null;
}

/// 解析grid行/列号（支持正整数）
/// 返回解析的行/列号（从1开始），如果解析失败返回null
fn parseGridLineNumber(str: []const u8) ?usize {
    // 去除前后空格
    const trimmed = std.mem.trim(u8, str, " \t\n\r");
    if (trimmed.len == 0) return null;

    // 解析整数
    const num = std.fmt.parseInt(usize, trimmed, 10) catch return null;
    // Grid行/列号从1开始，0无效
    if (num == 0) return null;
    return num;
}

/// 从ComputedStyle获取grid-row属性值
pub fn getGridRow(computed_style: *const cascade.ComputedStyle) ?GridLine {
    if (getPropertyKeyword(computed_style, "grid-row")) |value| {
        return parseGridLine(value);
    }
    return null;
}

/// 从ComputedStyle获取grid-column属性值
pub fn getGridColumn(computed_style: *const cascade.ComputedStyle) ?GridLine {
    if (getPropertyKeyword(computed_style, "grid-column")) |value| {
        return parseGridLine(value);
    }
    return null;
}

/// Grid对齐类型
pub const GridJustifyItems = enum {
    start,
    end,
    center,
    stretch,
    left,
    right,
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
    left,
    right,
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
    if (std.mem.eql(u8, value, "left")) return .left;
    if (std.mem.eql(u8, value, "right")) return .right;
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
    if (std.mem.eql(u8, value, "flex-start")) return .start; // flex-start是start的别名
    if (std.mem.eql(u8, value, "end")) return .end;
    if (std.mem.eql(u8, value, "flex-end")) return .end; // flex-end是end的别名
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "stretch")) return .stretch;
    if (std.mem.eql(u8, value, "space-around")) return .space_around;
    if (std.mem.eql(u8, value, "space-between")) return .space_between;
    if (std.mem.eql(u8, value, "space-evenly")) return .space_evenly;
    if (std.mem.eql(u8, value, "left")) return .left;
    if (std.mem.eql(u8, value, "right")) return .right;
    // 默认值
    return .start;
}

/// 解析align-content属性
pub fn parseGridAlignContent(value: []const u8) GridAlignContent {
    if (std.mem.eql(u8, value, "start")) return .start;
    if (std.mem.eql(u8, value, "flex-start")) return .start; // flex-start是start的别名
    if (std.mem.eql(u8, value, "end")) return .end;
    if (std.mem.eql(u8, value, "flex-end")) return .end; // flex-end是end的别名
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
        return result;
    }
    return .start; // 默认值
}
