const std = @import("std");
const testing = std.testing;
const context = @import("context");
const box = @import("box");
const test_helpers = @import("../test_helpers.zig");
const dom = @import("dom");

test "ContextType enum values" {
    try testing.expectEqual(context.ContextType.block, context.ContextType.block);
    try testing.expectEqual(context.ContextType.inline_element, context.ContextType.inline_element);
    try testing.expectEqual(context.ContextType.flex, context.ContextType.flex);
    try testing.expectEqual(context.ContextType.grid, context.ContextType.grid);
}

test "FormattingContext basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    // 创建格式化上下文
    var fmt_ctx = context.FormattingContext{
        .context_type = .block,
        .container = &layout_box,
        .allocator = allocator,
    };

    // 检查初始值
    try testing.expectEqual(context.ContextType.block, fmt_ctx.context_type);
    try testing.expectEqual(&layout_box, fmt_ctx.container);

    // deinit应该不会崩溃
    fmt_ctx.deinit();
}

test "BlockFormattingContext init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    // 创建BFC
    var bfc = context.BlockFormattingContext.init(&layout_box, allocator);
    defer bfc.deinit();

    // 检查初始值
    try testing.expectEqual(context.ContextType.block, bfc.base.context_type);
    try testing.expectEqual(&layout_box, bfc.base.container);
    try testing.expectEqual(@as(usize, 0), bfc.floats.items.len);
    try testing.expectEqual(@as(usize, 0), bfc.clear_elements.items.len);
}

test "BlockFormattingContext add float" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建容器节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 创建浮动元素节点
    const float_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, float_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    defer container_box.deinit();

    var float_box = box.LayoutBox.init(float_node, allocator);
    float_box.float = .left;
    defer float_box.deinit();

    // 创建BFC
    var bfc = context.BlockFormattingContext.init(&container_box, allocator);
    defer bfc.deinit();

    // 添加浮动元素
    try bfc.floats.append(&float_box);

    // 检查
    try testing.expectEqual(@as(usize, 1), bfc.floats.items.len);
    try testing.expectEqual(&float_box, bfc.floats.items[0]);
}

test "BlockFormattingContext add clear element" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建容器节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 创建清除浮动元素节点
    const clear_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, clear_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    defer container_box.deinit();

    var clear_box = box.LayoutBox.init(clear_node, allocator);
    defer clear_box.deinit();

    // 创建BFC
    var bfc = context.BlockFormattingContext.init(&container_box, allocator);
    defer bfc.deinit();

    // 添加清除浮动元素
    try bfc.clear_elements.append(&clear_box);

    // 检查
    try testing.expectEqual(@as(usize, 1), bfc.clear_elements.items.len);
    try testing.expectEqual(&clear_box, bfc.clear_elements.items[0]);
}

test "InlineFormattingContext init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    // 创建IFC
    var ifc = context.InlineFormattingContext.init(&layout_box, allocator);
    defer ifc.deinit();

    // 检查初始值
    try testing.expectEqual(context.ContextType.inline_element, ifc.base.context_type);
    try testing.expectEqual(&layout_box, ifc.base.container);
    try testing.expectEqual(@as(usize, 0), ifc.line_boxes.items.len);
}

test "InlineFormattingContext add line box" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建容器节点
    const container_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, container_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    defer container_box.deinit();

    // 创建IFC
    var ifc = context.InlineFormattingContext.init(&container_box, allocator);
    defer ifc.deinit();

    // 创建行框
    const line_box = context.LineBox{
        .rect = box.Rect{ .x = 0, .y = 0, .width = 100, .height = 20 },
        .inline_boxes = std.ArrayList(*box.LayoutBox).init(allocator),
        .baseline = 15,
        .line_height = 20,
    };
    defer line_box.inline_boxes.deinit();

    // 添加行框
    try ifc.line_boxes.append(line_box);

    // 检查
    try testing.expectEqual(@as(usize, 1), ifc.line_boxes.items.len);
    try testing.expectEqual(@as(f32, 0), ifc.line_boxes.items[0].rect.x);
    try testing.expectEqual(@as(f32, 0), ifc.line_boxes.items[0].rect.y);
    try testing.expectEqual(@as(f32, 100), ifc.line_boxes.items[0].rect.width);
    try testing.expectEqual(@as(f32, 20), ifc.line_boxes.items[0].rect.height);
    try testing.expectEqual(@as(f32, 15), ifc.line_boxes.items[0].baseline);
    try testing.expectEqual(@as(f32, 20), ifc.line_boxes.items[0].line_height);
}

test "LineBox basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建行框
    var line_box = context.LineBox{
        .rect = box.Rect{ .x = 10, .y = 20, .width = 200, .height = 30 },
        .inline_boxes = std.ArrayList(*box.LayoutBox).init(allocator),
        .baseline = 25,
        .line_height = 30,
    };
    defer line_box.inline_boxes.deinit();

    // 检查初始值
    try testing.expectEqual(@as(f32, 10), line_box.rect.x);
    try testing.expectEqual(@as(f32, 20), line_box.rect.y);
    try testing.expectEqual(@as(f32, 200), line_box.rect.width);
    try testing.expectEqual(@as(f32, 30), line_box.rect.height);
    try testing.expectEqual(@as(f32, 25), line_box.baseline);
    try testing.expectEqual(@as(f32, 30), line_box.line_height);
    try testing.expectEqual(@as(usize, 0), line_box.inline_boxes.items.len);
}

test "LineBox add inline box" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建行内元素节点
    const inline_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, inline_node);

    // 创建布局框
    var inline_box = box.LayoutBox.init(inline_node, allocator);
    defer inline_box.deinit();

    // 创建行框
    var line_box = context.LineBox{
        .rect = box.Rect{ .x = 0, .y = 0, .width = 100, .height = 20 },
        .inline_boxes = std.ArrayList(*box.LayoutBox).init(allocator),
        .baseline = 15,
        .line_height = 20,
    };
    defer line_box.inline_boxes.deinit();

    // 添加行内元素
    try line_box.inline_boxes.append(&inline_box);

    // 检查
    try testing.expectEqual(@as(usize, 1), line_box.inline_boxes.items.len);
    try testing.expectEqual(&inline_box, line_box.inline_boxes.items[0]);
}

test "BlockFormattingContext multiple floats" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建容器节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 创建多个浮动元素节点
    const float1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, float1_node);
    const float2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, float2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    defer container_box.deinit();

    var float1_box = box.LayoutBox.init(float1_node, allocator);
    float1_box.float = .left;
    defer float1_box.deinit();

    var float2_box = box.LayoutBox.init(float2_node, allocator);
    float2_box.float = .right;
    defer float2_box.deinit();

    // 创建BFC
    var bfc = context.BlockFormattingContext.init(&container_box, allocator);
    defer bfc.deinit();

    // 添加多个浮动元素
    try bfc.floats.append(&float1_box);
    try bfc.floats.append(&float2_box);

    // 检查
    try testing.expectEqual(@as(usize, 2), bfc.floats.items.len);
    try testing.expectEqual(&float1_box, bfc.floats.items[0]);
    try testing.expectEqual(&float2_box, bfc.floats.items[1]);
}

test "InlineFormattingContext multiple line boxes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建容器节点
    const container_node = try test_helpers.createTestElement(allocator, "p");
    defer test_helpers.freeNode(allocator, container_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    defer container_box.deinit();

    // 创建IFC
    var ifc = context.InlineFormattingContext.init(&container_box, allocator);
    defer ifc.deinit();

    // 创建多个行框
    const line_box1 = context.LineBox{
        .rect = box.Rect{ .x = 0, .y = 0, .width = 100, .height = 20 },
        .inline_boxes = std.ArrayList(*box.LayoutBox).init(allocator),
        .baseline = 15,
        .line_height = 20,
    };
    defer line_box1.inline_boxes.deinit();

    const line_box2 = context.LineBox{
        .rect = box.Rect{ .x = 0, .y = 20, .width = 100, .height = 20 },
        .inline_boxes = std.ArrayList(*box.LayoutBox).init(allocator),
        .baseline = 35,
        .line_height = 20,
    };
    defer line_box2.inline_boxes.deinit();

    // 添加行框
    try ifc.line_boxes.append(line_box1);
    try ifc.line_boxes.append(line_box2);

    // 检查
    try testing.expectEqual(@as(usize, 2), ifc.line_boxes.items.len);
    try testing.expectEqual(@as(f32, 0), ifc.line_boxes.items[0].rect.y);
    try testing.expectEqual(@as(f32, 20), ifc.line_boxes.items[1].rect.y);
}
