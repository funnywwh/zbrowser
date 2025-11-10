const std = @import("std");
const testing = std.testing;
const grid = @import("grid");
const box = @import("box");
const css = @import("css");
const test_helpers = @import("../test_helpers.zig");
const dom = @import("dom");

test "layoutGrid basic - single item" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    const item_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 800;
    container_box.box_model.content.height = 600;
    defer container_box.deinit();

    var item_box = box.LayoutBox.init(item_node, allocator);
    item_box.box_model.content.width = 100;
    item_box.box_model.content.height = 50;
    defer item_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item_box);
    item_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item_box.is_layouted);

    // 检查位置：单个item应该在(0, 0)
    try testing.expectEqual(@as(f32, 0), item_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item_box.box_model.content.y);
}

test "layoutGrid multiple items - basic grid" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 800;
    container_box.box_model.content.height = 600;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    item1_box.box_model.content.width = 100;
    item1_box.box_model.content.height = 50;
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    item2_box.box_model.content.width = 100;
    item2_box.box_model.content.height = 50;
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);
}

test "layoutGrid boundary - empty container" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 创建布局框（没有子元素）
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 800;
    container_box.box_model.content.height = 600;
    defer container_box.deinit();

    // 执行Grid布局（应该能正常处理空容器）
    const containing_block = box.Size{ .width = 800, .height = 600 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expectEqual(@as(usize, 0), container_box.children.items.len);
}

test "layoutGrid boundary - zero size container" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    const item_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 0;
    container_box.box_model.content.height = 0;
    defer container_box.deinit();

    var item_box = box.LayoutBox.init(item_node, allocator);
    item_box.box_model.content.width = 100;
    item_box.box_model.content.height = 50;
    defer item_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item_box);
    item_box.parent = &container_box;

    // 执行Grid布局（应该能正常处理零尺寸容器）
    const containing_block = box.Size{ .width = 0, .height = 0 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
}

test "layoutGrid boundary - large container" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    const item_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 10000;
    container_box.box_model.content.height = 10000;
    defer container_box.deinit();

    var item_box = box.LayoutBox.init(item_node, allocator);
    item_box.box_model.content.width = 100;
    item_box.box_model.content.height = 50;
    defer item_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item_box);
    item_box.parent = &container_box;

    // 执行Grid布局（应该能正常处理大容器）
    const containing_block = box.Size{ .width = 10000, .height = 10000 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item_box.is_layouted);

    // 检查位置：item应该在(0, 0)
    try testing.expectEqual(@as(f32, 0), item_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item_box.box_model.content.y);
}

test "layoutGrid with gap - row-gap and column-gap" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性（通过setAttribute）
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 200px 200px; grid-template-rows: 100px 100px; row-gap: 10px; column-gap: 20px;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    const item3_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item3_node);

    const item4_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item4_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 440; // 2*200 + 20 (gap)
    container_box.box_model.content.height = 210; // 2*100 + 10 (gap)
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    var item3_box = box.LayoutBox.init(item3_node, allocator);
    defer item3_box.deinit();

    var item4_box = box.LayoutBox.init(item4_node, allocator);
    defer item4_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    try container_box.children.append(allocator, &item3_box);
    try container_box.children.append(allocator, &item4_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;
    item3_box.parent = &container_box;
    item4_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 440, .height = 210 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);
    try testing.expect(item3_box.is_layouted);
    try testing.expect(item4_box.is_layouted);

    // 检查位置：item1应该在(0, 0)
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);

    // item2应该在(200 + 20, 0) = (220, 0)
    try testing.expectEqual(@as(f32, 220), item2_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.y);

    // item3应该在(0, 100 + 10) = (0, 110)
    try testing.expectEqual(@as(f32, 0), item3_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 110), item3_box.box_model.content.y);

    // item4应该在(220, 110)
    try testing.expectEqual(@as(f32, 220), item4_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 110), item4_box.box_model.content.y);
}

test "layoutGrid with gap shorthand - two values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性，使用gap简写属性（两个值：row-gap column-gap）
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 200px 200px; grid-template-rows: 100px 100px; gap: 10px 20px;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    const item3_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item3_node);

    const item4_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item4_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 440; // 2*200 + 20 (gap)
    container_box.box_model.content.height = 210; // 2*100 + 10 (gap)
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    var item3_box = box.LayoutBox.init(item3_node, allocator);
    defer item3_box.deinit();

    var item4_box = box.LayoutBox.init(item4_node, allocator);
    defer item4_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    try container_box.children.append(allocator, &item3_box);
    try container_box.children.append(allocator, &item4_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;
    item3_box.parent = &container_box;
    item4_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 440, .height = 210 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);
    try testing.expect(item3_box.is_layouted);
    try testing.expect(item4_box.is_layouted);

    // 检查位置：item1应该在(0, 0)
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);

    // item2应该在(200 + 20, 0) = (220, 0) - gap简写属性的第二个值是column-gap
    try testing.expectEqual(@as(f32, 220), item2_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.y);

    // item3应该在(0, 100 + 10) = (0, 110) - gap简写属性的第一个值是row-gap
    try testing.expectEqual(@as(f32, 0), item3_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 110), item3_box.box_model.content.y);

    // item4应该在(220, 110)
    try testing.expectEqual(@as(f32, 220), item4_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 110), item4_box.box_model.content.y);
}

test "layoutGrid with gap shorthand boundary - single value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性，使用gap简写属性（单个值：同时用于row-gap和column-gap）
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 200px 200px; grid-template-rows: 100px 100px; gap: 15px;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    const item3_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item3_node);

    const item4_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item4_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 430; // 2*200 + 15 (gap)
    container_box.box_model.content.height = 215; // 2*100 + 15 (gap)
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    var item3_box = box.LayoutBox.init(item3_node, allocator);
    defer item3_box.deinit();

    var item4_box = box.LayoutBox.init(item4_node, allocator);
    defer item4_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    try container_box.children.append(allocator, &item3_box);
    try container_box.children.append(allocator, &item4_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;
    item3_box.parent = &container_box;
    item4_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 430, .height = 215 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);
    try testing.expect(item3_box.is_layouted);
    try testing.expect(item4_box.is_layouted);

    // 检查位置：item1应该在(0, 0)
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);

    // item2应该在(200 + 15, 0) = (215, 0) - gap简写属性的单个值同时用于row-gap和column-gap
    try testing.expectEqual(@as(f32, 215), item2_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.y);

    // item3应该在(0, 100 + 15) = (0, 115)
    try testing.expectEqual(@as(f32, 0), item3_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 115), item3_box.box_model.content.y);

    // item4应该在(215, 115)
    try testing.expectEqual(@as(f32, 215), item4_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 115), item4_box.box_model.content.y);
}

test "layoutGrid with gap boundary - zero gap" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性，gap为0
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 200px 200px; grid-template-rows: 100px 100px; row-gap: 0px; column-gap: 0px;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 400; // 2*200 + 0 (gap)
    container_box.box_model.content.height = 200; // 2*100 + 0 (gap)
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 400, .height = 200 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // 检查位置：item1应该在(0, 0)
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);

    // item2应该在(200 + 0, 0) = (200, 0) - gap为0，所以没有间距
    try testing.expectEqual(@as(f32, 200), item2_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.y);
}

test "layoutGrid with gap boundary - no gap property" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性，不设置gap属性（应该使用默认值0）
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 200px 200px; grid-template-rows: 100px 100px;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 400; // 2*200 + 0 (默认gap)
    container_box.box_model.content.height = 200; // 2*100 + 0 (默认gap)
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 400, .height = 200 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // 检查位置：item1应该在(0, 0)
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);

    // item2应该在(200 + 0, 0) = (200, 0) - 默认gap为0
    try testing.expectEqual(@as(f32, 200), item2_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.y);
}

test "layoutGrid with justify-content space-between" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px 100px; grid-template-rows: 50px; justify-content: space-between;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 500; // 容器宽度500，grid宽度200，剩余300
    container_box.box_model.content.height = 50;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 500, .height = 50 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // space-between: 第一个item在开始位置(0)，第二个item在结束位置(500-100=400)
    // 剩余空间300分布在两个items之间
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 400), item2_box.box_model.content.x);
}

test "layoutGrid with justify-content space-around" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px 100px; grid-template-rows: 50px; justify-content: space-around;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 500; // 容器宽度500，grid宽度200，剩余300
    container_box.box_model.content.height = 50;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 500, .height = 50 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // space-around: 每个item两侧都有相等的空间
    // 剩余空间300，2个items，每个item两侧空间 = 300 / (2*2) = 75
    // item1应该在75位置，item2应该在75+100+75=250位置
    try testing.expectEqual(@as(f32, 75), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 250), item2_box.box_model.content.x);
}

test "layoutGrid with justify-content space-evenly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px 100px; grid-template-rows: 50px; justify-content: space-evenly;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 500; // 容器宽度500，grid宽度200，剩余300
    container_box.box_model.content.height = 50;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 500, .height = 50 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // space-evenly: 所有空间（包括两端）均匀分布
    // 剩余空间300，3个间隔（开始-item1、item1-item2、item2-结束），每个间隔 = 300 / 3 = 100
    // item1应该在100位置，item2应该在100+100+100=300位置
    try testing.expectEqual(@as(f32, 100), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 300), item2_box.box_model.content.x);
}

test "layoutGrid with align-content space-between" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px; grid-template-rows: 50px 50px; align-content: space-between;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 100;
    container_box.box_model.content.height = 300; // 容器高度300，grid高度100，剩余200
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 100, .height = 300 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // space-between: 第一个item在开始位置(0)，第二个item在结束位置(300-50=250)
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 250), item2_box.box_model.content.y);
}

test "layoutGrid with align-content space-around" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px; grid-template-rows: 50px 50px; align-content: space-around;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 100;
    container_box.box_model.content.height = 300; // 容器高度300，grid高度100，剩余200
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 100, .height = 300 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // space-around: 行之间和边缘都有间距
    try testing.expect(item1_box.box_model.content.y >= 0);
    try testing.expect(item2_box.box_model.content.y > item1_box.box_model.content.y);
    // 两行都应该在容器内
    try testing.expect(item1_box.box_model.content.y + item1_box.box_model.content.height <= container_box.box_model.content.height);
    try testing.expect(item2_box.box_model.content.y + item2_box.box_model.content.height <= container_box.box_model.content.height);
}

test "layoutGrid with align-content space-evenly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px; grid-template-rows: 50px 50px; align-content: space-evenly;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 100;
    container_box.box_model.content.height = 300;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 100, .height = 300 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // space-evenly: 所有间距（包括边缘）都相等
    try testing.expect(item1_box.box_model.content.y >= 0);
    try testing.expect(item2_box.box_model.content.y > item1_box.box_model.content.y);
    // 两行都应该在容器内
    try testing.expect(item1_box.box_model.content.y + item1_box.box_model.content.height <= container_box.box_model.content.height);
    try testing.expect(item2_box.box_model.content.y + item2_box.box_model.content.height <= container_box.box_model.content.height);
}

test "layoutGrid with align-content center" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px; grid-template-rows: 50px 50px; align-content: center;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 100;
    container_box.box_model.content.height = 300; // 容器高度300，grid高度100，剩余200，居中后应该在100位置
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 100, .height = 300 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // center: grid应该居中，第一行应该在中间位置附近
    try testing.expect(item1_box.box_model.content.y >= 0);
    try testing.expect(item2_box.box_model.content.y > item1_box.box_model.content.y);
    // 两行都应该在容器内
    try testing.expect(item1_box.box_model.content.y + item1_box.box_model.content.height <= container_box.box_model.content.height);
    try testing.expect(item2_box.box_model.content.y + item2_box.box_model.content.height <= container_box.box_model.content.height);
}

test "layoutGrid with align-content flex-start" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px; grid-template-rows: 50px 50px; align-content: flex-start;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 100;
    container_box.box_model.content.height = 300;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 100, .height = 300 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // flex-start: grid应该在顶部
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);
    try testing.expect(item2_box.box_model.content.y > item1_box.box_model.content.y);
}

test "layoutGrid with align-content flex-end" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px; grid-template-rows: 50px 50px; align-content: flex-end;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 100;
    container_box.box_model.content.height = 300; // 容器高度300，grid高度100，flex-end应该在200位置
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 100, .height = 300 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // flex-end: grid应该在底部
    try testing.expect(item1_box.box_model.content.y > 0);
    try testing.expect(item2_box.box_model.content.y > item1_box.box_model.content.y);
    // 第二行应该在底部附近
    try testing.expect(item2_box.box_model.content.y + item2_box.box_model.content.height <= container_box.box_model.content.height);
}

test "layoutGrid with justify-content center" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px; grid-template-rows: 50px; justify-content: center;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 300; // 容器宽度300，grid宽度100，居中后应该在100位置
    container_box.box_model.content.height = 100;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 300, .height = 100 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // center: grid应该居中
    try testing.expect(item1_box.box_model.content.x >= 0);
    try testing.expect(item1_box.box_model.content.x + item1_box.box_model.content.width <= container_box.box_model.content.width);
    try testing.expect(item2_box.box_model.content.x >= 0);
    try testing.expect(item2_box.box_model.content.x + item2_box.box_model.content.width <= container_box.box_model.content.width);
}

test "layoutGrid with justify-content flex-start" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px; grid-template-rows: 50px; justify-content: flex-start;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 300;
    container_box.box_model.content.height = 100;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 300, .height = 100 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // flex-start: grid应该在左边（允许一些误差）
    try testing.expect(item1_box.box_model.content.x >= 0);
    try testing.expect(item1_box.box_model.content.x < 10.0); // 应该在左边附近
    try testing.expect(item2_box.box_model.content.x > item1_box.box_model.content.x);
}

test "layoutGrid with justify-content flex-end" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px; grid-template-rows: 50px; justify-content: flex-end;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 300; // 容器宽度300，grid宽度100，flex-end应该在200位置
    container_box.box_model.content.height = 100;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 300, .height = 100 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // flex-end: grid应该在右边
    try testing.expect(item1_box.box_model.content.x > 0);
    try testing.expect(item2_box.box_model.content.x > item1_box.box_model.content.x);
    // 第二列应该在右边（允许一些误差）
    try testing.expect(item2_box.box_model.content.x + item2_box.box_model.content.width <= container_box.box_model.content.width + 1.0);
}

test "layoutGrid boundary - many items auto-placement" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px 100px; grid-template-rows: 50px 50px 50px;", allocator);
    }

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 200;
    container_box.box_model.content.height = 150;
    defer container_box.deinit();

    // 创建多个items（超过grid容量，但不要太多，避免段错误）
    var item_nodes: [7]*dom.Node = undefined;
    var item_boxes: [7]*box.LayoutBox = undefined;
    for (0..7) |i| {
        item_nodes[i] = try test_helpers.createTestElement(allocator, "div");
        item_boxes[i] = try allocator.create(box.LayoutBox);
        item_boxes[i].* = box.LayoutBox.init(item_nodes[i], allocator);
        item_boxes[i].box_model.content.width = 50;
        item_boxes[i].box_model.content.height = 30;

        try container_box.children.append(allocator, item_boxes[i]);
        item_boxes[i].parent = &container_box;
    }
    // 清理：先清空children（避免container_box.deinit()访问悬空指针），再释放item_boxes，最后释放item_nodes
    defer {
        // 先清空children，避免container_box.deinit()访问悬空指针
        container_box.children.clearAndFree(allocator);
        // 然后释放item_boxes的内存
        for (item_boxes) |item_box| {
            item_box.deinit();
            allocator.destroy(item_box);
        }
        // 最后释放item_nodes
        for (item_nodes) |item_node| {
            test_helpers.freeNode(allocator, item_node);
        }
    }

    // 执行Grid布局
    const containing_block = box.Size{ .width = 200, .height = 150 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    for (item_boxes) |item_box| {
        try testing.expect(item_box.is_layouted);
        // 所有items都应该在容器内
        try testing.expect(item_box.box_model.content.x >= 0);
        try testing.expect(item_box.box_model.content.y >= 0);
        try testing.expect(item_box.box_model.content.x + item_box.box_model.content.width <= container_box.box_model.content.width);
        try testing.expect(item_box.box_model.content.y + item_box.box_model.content.height <= container_box.box_model.content.height);
    }
}

test "layoutGrid boundary - single column grid" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 200px; grid-template-rows: 50px 50px 50px;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    const item3_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item3_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 200;
    container_box.box_model.content.height = 150;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    var item3_box = box.LayoutBox.init(item3_node, allocator);
    defer item3_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    try container_box.children.append(allocator, &item3_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;
    item3_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 200, .height = 150 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);
    try testing.expect(item3_box.is_layouted);

    // 单列grid，items应该垂直排列
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item3_box.box_model.content.x);
    try testing.expect(item2_box.box_model.content.y > item1_box.box_model.content.y);
    try testing.expect(item3_box.box_model.content.y > item2_box.box_model.content.y);
}

test "layoutGrid boundary - single row grid" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置inline style属性
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("style", "display: grid; grid-template-columns: 100px 100px 100px; grid-template-rows: 50px;", allocator);
    }

    const item1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item1_node);

    const item2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item2_node);

    const item3_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item3_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .grid;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 300;
    container_box.box_model.content.height = 50;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    defer item2_box.deinit();

    var item3_box = box.LayoutBox.init(item3_node, allocator);
    defer item3_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    try container_box.children.append(allocator, &item3_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;
    item3_box.parent = &container_box;

    // 执行Grid布局
    const containing_block = box.Size{ .width = 300, .height = 50 };
    grid.layoutGrid(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);
    try testing.expect(item3_box.is_layouted);

    // 单行grid，items应该水平排列
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 0), item3_box.box_model.content.y);
    try testing.expect(item2_box.box_model.content.x > item1_box.box_model.content.x);
    try testing.expect(item3_box.box_model.content.x > item2_box.box_model.content.x);
}
