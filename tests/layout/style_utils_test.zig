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

test "parseLineHeight - number value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 测试数字值（无单位）
    const line_height1 = style_utils.parseLineHeight("1.5", 16.0);
    try testing.expect(line_height1 == .number);
    try testing.expectEqual(@as(f32, 1.5), line_height1.number);
    
    // 测试normal值
    const line_height2 = style_utils.parseLineHeight("normal", 16.0);
    try testing.expect(line_height2 == .normal);
}

test "parseLineHeight - length value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 测试长度值（px单位）
    const line_height = style_utils.parseLineHeight("20px", 16.0);
    try testing.expect(line_height == .length);
    try testing.expectEqual(@as(f32, 20.0), line_height.length);
}

test "parseLineHeight - percent value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 测试百分比值
    const line_height = style_utils.parseLineHeight("150%", 16.0);
    try testing.expect(line_height == .percent);
    try testing.expectEqual(@as(f32, 150.0), line_height.percent);
}

test "parseLineHeight boundary_case - empty input" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 空输入应该返回normal
    const line_height = style_utils.parseLineHeight("", 16.0);
    try testing.expect(line_height == .normal);
}

test "computeLineHeight - all types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const font_size: f32 = 16.0;
    
    // 测试normal
    const normal_height = style_utils.computeLineHeight(.normal, font_size);
    try testing.expectEqual(@as(f32, 19.2), normal_height); // 16 * 1.2
    
    // 测试数字值
    const number_height = style_utils.computeLineHeight(.{ .number = 1.5 }, font_size);
    try testing.expectEqual(@as(f32, 24.0), number_height); // 16 * 1.5
    
    // 测试长度值
    const length_height = style_utils.computeLineHeight(.{ .length = 20.0 }, font_size);
    try testing.expectEqual(@as(f32, 20.0), length_height);
    
    // 测试百分比值
    const percent_height = style_utils.computeLineHeight(.{ .percent = 150.0 }, font_size);
    try testing.expectEqual(@as(f32, 24.0), percent_height); // 16 * 150 / 100
}

test "applyStyleToLayoutBox with line-height" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "line-height: 1.5;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查line-height是否正确应用
    try testing.expect(layout_box.line_height == .number);
    try testing.expectEqual(@as(f32, 1.5), layout_box.line_height.number);
}

test "font-weight lighter parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "font-weight: lighter;", allocator);
    }

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    // 检查font-weight是否正确解析
    const font_weight = style_utils.getPropertyKeyword(&computed_style, "font-weight");
    try testing.expect(font_weight != null);
    try testing.expectEqualStrings("lighter", font_weight.?);
}

test "getFlexProperties with flex shorthand - single value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "flex: 1;", allocator);
    }

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size: f32 = 800.0;
    const flex_props = style_utils.getFlexProperties(&computed_style, containing_size);

    // flex: 1 应该解析为 grow=1, shrink=1, basis=auto
    try testing.expectEqual(@as(f32, 1.0), flex_props.grow);
    try testing.expectEqual(@as(f32, 1.0), flex_props.shrink);
    try testing.expect(flex_props.basis == null); // auto
}

test "getFlexProperties with flex shorthand - two values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "flex: 1 2;", allocator);
    }

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size: f32 = 800.0;
    const flex_props = style_utils.getFlexProperties(&computed_style, containing_size);

    // flex: 1 2 应该解析为 grow=1, shrink=2, basis=auto
    try testing.expectEqual(@as(f32, 1.0), flex_props.grow);
    try testing.expectEqual(@as(f32, 2.0), flex_props.shrink);
    try testing.expect(flex_props.basis == null); // auto
}

test "getFlexProperties with flex shorthand - three values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "flex: 1 2 100px;", allocator);
    }

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size: f32 = 800.0;
    const flex_props = style_utils.getFlexProperties(&computed_style, containing_size);

    // flex: 1 2 100px 应该解析为 grow=1, shrink=2, basis=100px
    try testing.expectEqual(@as(f32, 1.0), flex_props.grow);
    try testing.expectEqual(@as(f32, 2.0), flex_props.shrink);
    try testing.expect(flex_props.basis != null);
    try testing.expectEqual(@as(f32, 100.0), flex_props.basis.?);
}

test "getFlexProperties with flex shorthand - auto keyword" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "flex: auto;", allocator);
    }

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size: f32 = 800.0;
    const flex_props = style_utils.getFlexProperties(&computed_style, containing_size);

    // flex: auto 应该解析为 grow=1, shrink=1, basis=auto
    try testing.expectEqual(@as(f32, 1.0), flex_props.grow);
    try testing.expectEqual(@as(f32, 1.0), flex_props.shrink);
    try testing.expect(flex_props.basis == null); // auto
}

test "getFlexProperties with flex shorthand - none keyword" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "flex: none;", allocator);
    }

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size: f32 = 800.0;
    const flex_props = style_utils.getFlexProperties(&computed_style, containing_size);

    // flex: none 应该解析为 grow=0, shrink=0, basis=auto
    try testing.expectEqual(@as(f32, 0.0), flex_props.grow);
    try testing.expectEqual(@as(f32, 0.0), flex_props.shrink);
    try testing.expect(flex_props.basis == null); // auto
}

test "parseOverflow - all overflow types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 测试所有overflow值
    try testing.expectEqual(box.Overflow.visible, style_utils.parseOverflow("visible"));
    try testing.expectEqual(box.Overflow.hidden, style_utils.parseOverflow("hidden"));
    try testing.expectEqual(box.Overflow.scroll, style_utils.parseOverflow("scroll"));
    try testing.expectEqual(box.Overflow.auto, style_utils.parseOverflow("auto"));
}

test "parseOverflow boundary_case - unknown value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 未知值应该返回默认值visible
    const overflow = style_utils.parseOverflow("unknown");
    try testing.expectEqual(box.Overflow.visible, overflow);
}

test "applyStyleToLayoutBox with overflow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "overflow: hidden;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查overflow是否正确应用
    try testing.expectEqual(box.Overflow.hidden, layout_box.overflow);
}

test "applyStyleToLayoutBox with min-width and min-height" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "min-width: 100px; min-height: 50px;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查min-width和min-height是否正确应用
    try testing.expect(layout_box.box_model.min_width != null);
    try testing.expectEqual(@as(f32, 100.0), layout_box.box_model.min_width.?);
    try testing.expect(layout_box.box_model.min_height != null);
    try testing.expectEqual(@as(f32, 50.0), layout_box.box_model.min_height.?);
}

test "applyStyleToLayoutBox with max-width and max-height" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "max-width: 500px; max-height: 300px;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查max-width和max-height是否正确应用
    try testing.expect(layout_box.box_model.max_width != null);
    try testing.expectEqual(@as(f32, 500.0), layout_box.box_model.max_width.?);
    try testing.expect(layout_box.box_model.max_height != null);
    try testing.expectEqual(@as(f32, 300.0), layout_box.box_model.max_height.?);
}

test "applyStyleToLayoutBox with border shorthand" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "border: 2px solid #2196f3;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查border宽度是否正确应用
    try testing.expectEqual(@as(f32, 2.0), layout_box.box_model.border.top);
    try testing.expectEqual(@as(f32, 2.0), layout_box.box_model.border.right);
    try testing.expectEqual(@as(f32, 2.0), layout_box.box_model.border.bottom);
    try testing.expectEqual(@as(f32, 2.0), layout_box.box_model.border.left);
}

test "applyStyleToLayoutBox with border-width" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "border-width: 5px;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查border宽度是否正确应用
    try testing.expectEqual(@as(f32, 5.0), layout_box.box_model.border.top);
    try testing.expectEqual(@as(f32, 5.0), layout_box.box_model.border.right);
    try testing.expectEqual(@as(f32, 5.0), layout_box.box_model.border.bottom);
    try testing.expectEqual(@as(f32, 5.0), layout_box.box_model.border.left);
}

test "applyStyleToLayoutBox with individual border widths" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "border-top-width: 1px; border-right-width: 2px; border-bottom-width: 3px; border-left-width: 4px;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查各个border宽度是否正确应用
    try testing.expectEqual(@as(f32, 1.0), layout_box.box_model.border.top);
    try testing.expectEqual(@as(f32, 2.0), layout_box.box_model.border.right);
    try testing.expectEqual(@as(f32, 3.0), layout_box.box_model.border.bottom);
    try testing.expectEqual(@as(f32, 4.0), layout_box.box_model.border.left);
}

test "applyStyleToLayoutBox with letter-spacing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "letter-spacing: 2px;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查letter-spacing是否正确应用
    try testing.expect(layout_box.letter_spacing != null);
    try testing.expectEqual(@as(f32, 2.0), layout_box.letter_spacing.?);
}

test "applyStyleToLayoutBox with letter-spacing normal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "letter-spacing: normal;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查letter-spacing normal应该为null（表示使用默认间距）
    try testing.expect(layout_box.letter_spacing == null);
}

test "applyStyleToLayoutBox with opacity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "opacity: 0.5;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查opacity是否正确应用
    try testing.expectEqual(@as(f32, 0.5), layout_box.opacity);
}

test "applyStyleToLayoutBox with opacity boundary - 0.0" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "opacity: 0.0;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查opacity是否正确应用（应该限制在0.0到1.0范围内）
    try testing.expectEqual(@as(f32, 0.0), layout_box.opacity);
}

test "applyStyleToLayoutBox with opacity boundary - 1.0" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "opacity: 1.0;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查opacity是否正确应用
    try testing.expectEqual(@as(f32, 1.0), layout_box.opacity);
}

test "applyStyleToLayoutBox with opacity boundary - out of range" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性（超出范围的值）
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "opacity: 1.5;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查opacity是否被限制在1.0（超出范围的值应该被限制）
    try testing.expectEqual(@as(f32, 1.0), layout_box.opacity);
}

test "applyStyleToLayoutBox with z-index" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "position: relative; z-index: 10;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查z-index是否正确应用
    try testing.expect(layout_box.z_index != null);
    try testing.expectEqual(@as(i32, 10), layout_box.z_index.?);
}

test "applyStyleToLayoutBox with z-index auto" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "position: relative; z-index: auto;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查z-index auto应该为null（表示使用默认堆叠顺序）
    try testing.expect(layout_box.z_index == null);
}

test "applyStyleToLayoutBox with z-index negative" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "position: relative; z-index: -1;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查z-index负数是否正确应用
    try testing.expect(layout_box.z_index != null);
    try testing.expectEqual(@as(i32, -1), layout_box.z_index.?);
}

test "applyStyleToLayoutBox with z-index zero" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "position: relative; z-index: 0;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查z-index 0是否正确应用
    try testing.expect(layout_box.z_index != null);
    try testing.expectEqual(@as(i32, 0), layout_box.z_index.?);
}

test "applyStyleToLayoutBox with vertical-align" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "vertical-align: top;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查vertical-align是否正确应用
    try testing.expectEqual(box.VerticalAlign.top, layout_box.vertical_align);
}

test "applyStyleToLayoutBox with vertical-align middle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "vertical-align: middle;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查vertical-align是否正确应用
    try testing.expectEqual(box.VerticalAlign.middle, layout_box.vertical_align);
}

test "applyStyleToLayoutBox with vertical-align baseline" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, node);

    // 设置inline style属性
    if (node.asElement()) |elem| {
        try elem.setAttribute("style", "vertical-align: baseline;", allocator);
    }

    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    var cascade_engine = cascade.Cascade.init(allocator);
    var computed_style = try cascade_engine.computeStyle(node, &[_]css_parser.Stylesheet{});
    defer computed_style.deinit();

    const containing_size = box.Size{ .width = 800, .height = 600 };
    style_utils.applyStyleToLayoutBox(&layout_box, &computed_style, containing_size);

    // 检查vertical-align是否正确应用
    try testing.expectEqual(box.VerticalAlign.baseline, layout_box.vertical_align);
}

test "parseVerticalAlign - all values" {
    try testing.expectEqual(box.VerticalAlign.baseline, style_utils.parseVerticalAlign("baseline"));
    try testing.expectEqual(box.VerticalAlign.top, style_utils.parseVerticalAlign("top"));
    try testing.expectEqual(box.VerticalAlign.middle, style_utils.parseVerticalAlign("middle"));
    try testing.expectEqual(box.VerticalAlign.bottom, style_utils.parseVerticalAlign("bottom"));
    try testing.expectEqual(box.VerticalAlign.sub, style_utils.parseVerticalAlign("sub"));
    try testing.expectEqual(box.VerticalAlign.super, style_utils.parseVerticalAlign("super"));
    try testing.expectEqual(box.VerticalAlign.text_top, style_utils.parseVerticalAlign("text-top"));
    try testing.expectEqual(box.VerticalAlign.text_bottom, style_utils.parseVerticalAlign("text-bottom"));
    // 无效值应该返回默认值baseline
    try testing.expectEqual(box.VerticalAlign.baseline, style_utils.parseVerticalAlign("invalid"));
}
