const std = @import("std");
const testing = std.testing;
const style_utils = @import("style_utils");
const box = @import("box");
const cascade = @import("cascade");
const css_parser = @import("css");
const test_helpers = @import("../test_helpers.zig");
const dom = @import("dom");

test "parseDisplayType - all display types" {
    try testing.expectEqual(box.DisplayType.none, style_utils.parseDisplayType("none"));
    try testing.expectEqual(box.DisplayType.block, style_utils.parseDisplayType("block"));
    try testing.expectEqual(box.DisplayType.inline_block, style_utils.parseDisplayType("inline-block"));
    try testing.expectEqual(box.DisplayType.inline_element, style_utils.parseDisplayType("inline"));
    try testing.expectEqual(box.DisplayType.flex, style_utils.parseDisplayType("flex"));
    try testing.expectEqual(box.DisplayType.inline_flex, style_utils.parseDisplayType("inline-flex"));
    try testing.expectEqual(box.DisplayType.grid, style_utils.parseDisplayType("grid"));
    try testing.expectEqual(box.DisplayType.inline_grid, style_utils.parseDisplayType("inline-grid"));
    try testing.expectEqual(box.DisplayType.table, style_utils.parseDisplayType("table"));
    try testing.expectEqual(box.DisplayType.inline_table, style_utils.parseDisplayType("inline-table"));
    try testing.expectEqual(box.DisplayType.table_row, style_utils.parseDisplayType("table-row"));
    try testing.expectEqual(box.DisplayType.table_cell, style_utils.parseDisplayType("table-cell"));
}

test "parseDisplayType boundary_case - unknown value" {
    // 未知值应该返回默认值block
    try testing.expectEqual(box.DisplayType.block, style_utils.parseDisplayType("unknown"));
    try testing.expectEqual(box.DisplayType.block, style_utils.parseDisplayType(""));
}

test "parsePositionType - all position types" {
    try testing.expectEqual(box.PositionType.static, style_utils.parsePositionType("static"));
    try testing.expectEqual(box.PositionType.relative, style_utils.parsePositionType("relative"));
    try testing.expectEqual(box.PositionType.absolute, style_utils.parsePositionType("absolute"));
    try testing.expectEqual(box.PositionType.fixed, style_utils.parsePositionType("fixed"));
    try testing.expectEqual(box.PositionType.sticky, style_utils.parsePositionType("sticky"));
}

test "parsePositionType boundary_case - unknown value" {
    // 未知值应该返回默认值static
    try testing.expectEqual(box.PositionType.static, style_utils.parsePositionType("unknown"));
    try testing.expectEqual(box.PositionType.static, style_utils.parsePositionType(""));
}

test "parseFloatType - all float types" {
    try testing.expectEqual(box.FloatType.left, style_utils.parseFloatType("left"));
    try testing.expectEqual(box.FloatType.right, style_utils.parseFloatType("right"));
}

test "parseFloatType boundary_case - unknown value" {
    // 未知值应该返回默认值none
    try testing.expectEqual(box.FloatType.none, style_utils.parseFloatType("unknown"));
    try testing.expectEqual(box.FloatType.none, style_utils.parseFloatType(""));
    try testing.expectEqual(box.FloatType.none, style_utils.parseFloatType("none"));
}

test "parseLength - px unit" {
    const context = style_utils.UnitContext{
        .parent_font_size = 16,
        .root_font_size = 16,
        .viewport_width = 800,
        .viewport_height = 600,
        .containing_size = 100,
    };

    const length_value = css_parser.Value{ .length = .{ .value = 10, .unit = "px" } };
    const result = style_utils.parseLength(length_value, context);
    try testing.expectEqual(@as(f32, 10), result);
}

test "parseLength - em unit" {
    const context = style_utils.UnitContext{
        .parent_font_size = 16,
        .root_font_size = 16,
        .viewport_width = 800,
        .viewport_height = 600,
        .containing_size = 100,
    };

    const length_value = css_parser.Value{ .length = .{ .value = 2, .unit = "em" } };
    const result = style_utils.parseLength(length_value, context);
    try testing.expectEqual(@as(f32, 32), result); // 2 * 16 = 32
}

test "parseLength - rem unit" {
    const context = style_utils.UnitContext{
        .parent_font_size = 16,
        .root_font_size = 20,
        .viewport_width = 800,
        .viewport_height = 600,
        .containing_size = 100,
    };

    const length_value = css_parser.Value{ .length = .{ .value = 1.5, .unit = "rem" } };
    const result = style_utils.parseLength(length_value, context);
    try testing.expectEqual(@as(f32, 30), result); // 1.5 * 20 = 30
}

test "parseLength - percentage unit" {
    const context = style_utils.UnitContext{
        .parent_font_size = 16,
        .root_font_size = 16,
        .viewport_width = 800,
        .viewport_height = 600,
        .containing_size = 200,
    };

    const percentage_value = css_parser.Value{ .percentage = 50 };
    const result = style_utils.parseLength(percentage_value, context);
    try testing.expectEqual(@as(f32, 100), result); // 50% of 200 = 100
}

test "parseLength - vw unit" {
    const context = style_utils.UnitContext{
        .parent_font_size = 16,
        .root_font_size = 16,
        .viewport_width = 800,
        .viewport_height = 600,
        .containing_size = 100,
    };

    const length_value = css_parser.Value{ .length = .{ .value = 50, .unit = "vw" } };
    const result = style_utils.parseLength(length_value, context);
    try testing.expectEqual(@as(f32, 400), result); // 50% of 800 = 400
}

test "parseLength - vh unit" {
    const context = style_utils.UnitContext{
        .parent_font_size = 16,
        .root_font_size = 16,
        .viewport_width = 800,
        .viewport_height = 600,
        .containing_size = 100,
    };

    const length_value = css_parser.Value{ .length = .{ .value = 25, .unit = "vh" } };
    const result = style_utils.parseLength(length_value, context);
    try testing.expectEqual(@as(f32, 150), result); // 25% of 600 = 150
}

test "parseLength - vmin unit" {
    const context = style_utils.UnitContext{
        .parent_font_size = 16,
        .root_font_size = 16,
        .viewport_width = 800,
        .viewport_height = 600,
        .containing_size = 100,
    };

    const length_value = css_parser.Value{ .length = .{ .value = 10, .unit = "vmin" } };
    const result = style_utils.parseLength(length_value, context);
    // vmin = min(800, 600) = 600, 10% of 600 = 60
    try testing.expectEqual(@as(f32, 60), result);
}

test "parseLength - vmax unit" {
    const context = style_utils.UnitContext{
        .parent_font_size = 16,
        .root_font_size = 16,
        .viewport_width = 800,
        .viewport_height = 600,
        .containing_size = 100,
    };

    const length_value = css_parser.Value{ .length = .{ .value = 10, .unit = "vmax" } };
    const result = style_utils.parseLength(length_value, context);
    // vmax = max(800, 600) = 800, 10% of 800 = 80
    try testing.expectEqual(@as(f32, 80), result);
}

test "parseLength boundary_case - unknown unit" {
    const context = style_utils.UnitContext{
        .parent_font_size = 16,
        .root_font_size = 16,
        .viewport_width = 800,
        .viewport_height = 600,
        .containing_size = 100,
    };

    const length_value = css_parser.Value{ .length = .{ .value = 10, .unit = "unknown" } };
    const result = style_utils.parseLength(length_value, context);
    // 未知单位应该返回0
    try testing.expectEqual(@as(f32, 0), result);
}

test "parseLength boundary_case - non-length value" {
    const context = style_utils.UnitContext{
        .parent_font_size = 16,
        .root_font_size = 16,
        .viewport_width = 800,
        .viewport_height = 600,
        .containing_size = 100,
    };

    const keyword_value = css_parser.Value{ .keyword = "auto" };
    const result = style_utils.parseLength(keyword_value, context);
    // 非长度值应该返回0
    try testing.expectEqual(@as(f32, 0), result);
}

test "createUnitContext - basic" {
    const context = style_utils.createUnitContext(200);
    try testing.expectEqual(@as(f32, 200), context.containing_size);
    // 默认值
    try testing.expectEqual(@as(f32, 16), context.parent_font_size);
    try testing.expectEqual(@as(f32, 16), context.root_font_size);
    try testing.expectEqual(@as(f32, 800), context.viewport_width);
    try testing.expectEqual(@as(f32, 600), context.viewport_height);
}

test "parseFlexDirection - all directions" {
    try testing.expectEqual(style_utils.FlexDirection.row, style_utils.parseFlexDirection("row"));
    try testing.expectEqual(style_utils.FlexDirection.column, style_utils.parseFlexDirection("column"));
    try testing.expectEqual(style_utils.FlexDirection.row_reverse, style_utils.parseFlexDirection("row-reverse"));
    try testing.expectEqual(style_utils.FlexDirection.column_reverse, style_utils.parseFlexDirection("column-reverse"));
}

test "parseFlexDirection boundary_case - unknown value" {
    // 未知值应该返回默认值row
    try testing.expectEqual(style_utils.FlexDirection.row, style_utils.parseFlexDirection("unknown"));
    try testing.expectEqual(style_utils.FlexDirection.row, style_utils.parseFlexDirection(""));
}

test "parseFlexWrap - all wrap types" {
    try testing.expectEqual(style_utils.FlexWrap.nowrap, style_utils.parseFlexWrap("nowrap"));
    try testing.expectEqual(style_utils.FlexWrap.wrap, style_utils.parseFlexWrap("wrap"));
    try testing.expectEqual(style_utils.FlexWrap.wrap_reverse, style_utils.parseFlexWrap("wrap-reverse"));
}

test "parseFlexWrap boundary_case - unknown value" {
    // 未知值应该返回默认值nowrap
    try testing.expectEqual(style_utils.FlexWrap.nowrap, style_utils.parseFlexWrap("unknown"));
    try testing.expectEqual(style_utils.FlexWrap.nowrap, style_utils.parseFlexWrap(""));
}

test "parseJustifyContent - all justify types" {
    try testing.expectEqual(style_utils.JustifyContent.flex_start, style_utils.parseJustifyContent("flex-start"));
    try testing.expectEqual(style_utils.JustifyContent.flex_end, style_utils.parseJustifyContent("flex-end"));
    try testing.expectEqual(style_utils.JustifyContent.center, style_utils.parseJustifyContent("center"));
    try testing.expectEqual(style_utils.JustifyContent.space_between, style_utils.parseJustifyContent("space-between"));
    try testing.expectEqual(style_utils.JustifyContent.space_around, style_utils.parseJustifyContent("space-around"));
    try testing.expectEqual(style_utils.JustifyContent.space_evenly, style_utils.parseJustifyContent("space-evenly"));
}

test "parseJustifyContent boundary_case - unknown value" {
    // 未知值应该返回默认值flex_start
    try testing.expectEqual(style_utils.JustifyContent.flex_start, style_utils.parseJustifyContent("unknown"));
    try testing.expectEqual(style_utils.JustifyContent.flex_start, style_utils.parseJustifyContent(""));
}

test "parseAlignItems - all align types" {
    try testing.expectEqual(style_utils.AlignItems.flex_start, style_utils.parseAlignItems("flex-start"));
    try testing.expectEqual(style_utils.AlignItems.flex_end, style_utils.parseAlignItems("flex-end"));
    try testing.expectEqual(style_utils.AlignItems.center, style_utils.parseAlignItems("center"));
    try testing.expectEqual(style_utils.AlignItems.stretch, style_utils.parseAlignItems("stretch"));
    try testing.expectEqual(style_utils.AlignItems.baseline, style_utils.parseAlignItems("baseline"));
}

test "parseAlignItems boundary_case - unknown value" {
    // 未知值应该返回默认值stretch
    try testing.expectEqual(style_utils.AlignItems.stretch, style_utils.parseAlignItems("unknown"));
    try testing.expectEqual(style_utils.AlignItems.stretch, style_utils.parseAlignItems(""));
}

test "parseAlignContent - all align content types" {
    try testing.expectEqual(style_utils.AlignContent.flex_start, style_utils.parseAlignContent("flex-start"));
    try testing.expectEqual(style_utils.AlignContent.flex_end, style_utils.parseAlignContent("flex-end"));
    try testing.expectEqual(style_utils.AlignContent.center, style_utils.parseAlignContent("center"));
    try testing.expectEqual(style_utils.AlignContent.stretch, style_utils.parseAlignContent("stretch"));
    try testing.expectEqual(style_utils.AlignContent.space_between, style_utils.parseAlignContent("space-between"));
    try testing.expectEqual(style_utils.AlignContent.space_around, style_utils.parseAlignContent("space-around"));
}

test "parseAlignContent boundary_case - unknown value" {
    // 未知值应该返回默认值stretch
    try testing.expectEqual(style_utils.AlignContent.stretch, style_utils.parseAlignContent("unknown"));
    try testing.expectEqual(style_utils.AlignContent.stretch, style_utils.parseAlignContent(""));
}
