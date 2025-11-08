const std = @import("std");
const testing = std.testing;
const grid = @import("grid");
const box = @import("box");
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
    grid.layoutGrid(&container_box, containing_block);

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
    grid.layoutGrid(&container_box, containing_block);

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
    grid.layoutGrid(&container_box, containing_block);

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
    grid.layoutGrid(&container_box, containing_block);

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
    grid.layoutGrid(&container_box, containing_block);

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item_box.is_layouted);

    // 检查位置：item应该在(0, 0)
    try testing.expectEqual(@as(f32, 0), item_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item_box.box_model.content.y);
}
