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

test "parseTextAlign - all text align types" {
    try testing.expectEqual(box.TextAlign.left, style_utils.parseTextAlign("left"));
    try testing.expectEqual(box.TextAlign.center, style_utils.parseTextAlign("center"));
    try testing.expectEqual(box.TextAlign.right, style_utils.parseTextAlign("right"));
    try testing.expectEqual(box.TextAlign.justify, style_utils.parseTextAlign("justify"));
}

test "parseTextAlign boundary_case - unknown value" {
    // 未知值应该返回默认值left
    try testing.expectEqual(box.TextAlign.left, style_utils.parseTextAlign("unknown"));
    try testing.expectEqual(box.TextAlign.left, style_utils.parseTextAlign(""));
}

test "parseTextDecoration - all text decoration types" {
    try testing.expectEqual(box.TextDecoration.none, style_utils.parseTextDecoration("none"));
    try testing.expectEqual(box.TextDecoration.underline, style_utils.parseTextDecoration("underline"));
    try testing.expectEqual(box.TextDecoration.line_through, style_utils.parseTextDecoration("line-through"));
    try testing.expectEqual(box.TextDecoration.overline, style_utils.parseTextDecoration("overline"));
}

test "parseTextDecoration boundary_case - unknown value" {
    // 未知值应该返回默认值none
    try testing.expectEqual(box.TextDecoration.none, style_utils.parseTextDecoration("unknown"));
    try testing.expectEqual(box.TextDecoration.none, style_utils.parseTextDecoration(""));
}

test "parseGridTemplate with repeat() function" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试repeat(3, 1fr)
    var tracks = try style_utils.parseGridTemplate("repeat(3, 1fr)", allocator);
    defer tracks.deinit(allocator);
    try testing.expectEqual(@as(usize, 3), tracks.items.len);
    for (tracks.items) |track| {
        try testing.expect(track == .fr);
        try testing.expectEqual(@as(f32, 1.0), track.fr);
    }

    // 测试repeat(2, 100px)
    var tracks2 = try style_utils.parseGridTemplate("repeat(2, 100px)", allocator);
    defer tracks2.deinit(allocator);
    try testing.expectEqual(@as(usize, 2), tracks2.items.len);
    for (tracks2.items) |track| {
        try testing.expect(track == .fixed);
        try testing.expectEqual(@as(f32, 100.0), track.fixed);
    }
}

test "parseGridTemplate with fr units" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试1fr 2fr 1fr
    var tracks = try style_utils.parseGridTemplate("1fr 2fr 1fr", allocator);
    defer tracks.deinit(allocator);
    try testing.expectEqual(@as(usize, 3), tracks.items.len);
    try testing.expect(tracks.items[0] == .fr);
    try testing.expectEqual(@as(f32, 1.0), tracks.items[0].fr);
    try testing.expect(tracks.items[1] == .fr);
    try testing.expectEqual(@as(f32, 2.0), tracks.items[1].fr);
    try testing.expect(tracks.items[2] == .fr);
    try testing.expectEqual(@as(f32, 1.0), tracks.items[2].fr);
}

test "parseGridTemplate boundary_case - empty input" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tracks = try style_utils.parseGridTemplate("", allocator);
    defer tracks.deinit(allocator);
    try testing.expectEqual(@as(usize, 0), tracks.items.len);
}

test "applyStyleToLayoutBox with width and height" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "width: 200px; height: 100px;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查width和height是否正确应用
    try testing.expectEqual(@as(f32, 200.0), layout_box.box_model.content.width);
    try testing.expectEqual(@as(f32, 100.0), layout_box.box_model.content.height);
}

test "applyStyleToLayoutBox with box-sizing border-box" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性：border-box，width包含padding和border
    // 注意：border解析还未实现，这里只测试padding
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "box-sizing: border-box; width: 200px; height: 100px; padding: 10px;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查box-sizing是否正确设置
    try testing.expectEqual(box.BoxSizing.border_box, layout_box.box_model.box_sizing);
    
    // 检查content width：200px - 10px*2 (padding) = 180px（border还未实现，暂时不考虑）
    try testing.expectEqual(@as(f32, 180.0), layout_box.box_model.content.width);
    // 检查content height：100px - 10px*2 (padding) = 80px（border还未实现，暂时不考虑）
    try testing.expectEqual(@as(f32, 80.0), layout_box.box_model.content.height);
}

test "applyStyleToLayoutBox with text-align" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "text-align: center;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查text-align是否正确应用
    try testing.expectEqual(box.TextAlign.center, layout_box.text_align);
}

test "applyStyleToLayoutBox with text-decoration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "text-decoration: underline;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查text-decoration是否正确应用
    try testing.expectEqual(box.TextDecoration.underline, layout_box.text_decoration);
}

test "applyStyleToLayoutBox with text-decoration line-through" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "text-decoration: line-through;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查text-decoration是否正确应用
    try testing.expectEqual(box.TextDecoration.line_through, layout_box.text_decoration);
}

test "parseBorderRadius - px value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    
    // 测试px值
    const radius1 = style_utils.parseBorderRadius("10px", containing_size);
    try testing.expect(radius1 != null);
    try testing.expectEqual(@as(f32, 10.0), radius1.?);
    
    // 测试0值
    const radius2 = style_utils.parseBorderRadius("0", containing_size);
    try testing.expect(radius2 != null);
    try testing.expectEqual(@as(f32, 0.0), radius2.?);
    
    // 测试百分比值
    const radius3 = style_utils.parseBorderRadius("5%", containing_size);
    try testing.expect(radius3 != null);
    // 5% of min(800, 600) = 5% of 600 = 30
    try testing.expectEqual(@as(f32, 30.0), radius3.?);
}

test "parseBorderRadius boundary_case - empty input" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    
    // 空输入应该返回null
    const radius = style_utils.parseBorderRadius("", containing_size);
    try testing.expect(radius == null);
}

test "applyStyleToLayoutBox with border-radius" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "border-radius: 10px;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查border-radius是否正确应用
    try testing.expect(layout_box.box_model.border_radius != null);
    try testing.expectEqual(@as(f32, 10.0), layout_box.box_model.border_radius.?);
}
