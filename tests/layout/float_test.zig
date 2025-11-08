const std = @import("std");
const testing = std.testing;
const float_layout = @import("float");
const box = @import("box");
const test_helpers = @import("../test_helpers.zig");
const dom = @import("dom");

test "layoutFloat left - single float" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const containing_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, containing_node);

    const float_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, float_node);

    // 创建布局框
    var containing_box = box.LayoutBox.init(containing_node, allocator);
    containing_box.box_model.content.x = 0;
    containing_box.box_model.content.y = 0;
    containing_box.box_model.content.width = 800;
    containing_box.box_model.content.height = 600;
    defer containing_box.deinit();

    var float_box = box.LayoutBox.init(float_node, allocator);
    float_box.float = .left;
    float_box.box_model.content.width = 100;
    float_box.box_model.content.height = 50;
    defer float_box.deinit();

    // 执行浮动布局
    var y: f32 = 0;
    float_layout.layoutFloat(&float_box, &containing_box, &y);

    // 检查浮动元素位置（应该靠左）
    try testing.expectEqual(@as(f32, 0), float_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), float_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 50), y); // y应该更新为浮动元素的高度
}

test "layoutFloat right - single float" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const containing_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, containing_node);

    const float_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, float_node);

    // 创建布局框
    var containing_box = box.LayoutBox.init(containing_node, allocator);
    containing_box.box_model.content.x = 0;
    containing_box.box_model.content.y = 0;
    containing_box.box_model.content.width = 800;
    containing_box.box_model.content.height = 600;
    defer containing_box.deinit();

    var float_box = box.LayoutBox.init(float_node, allocator);
    float_box.float = .right;
    float_box.box_model.content.width = 100;
    float_box.box_model.content.height = 50;
    defer float_box.deinit();

    // 执行浮动布局
    var y: f32 = 0;
    float_layout.layoutFloat(&float_box, &containing_box, &y);

    // 检查浮动元素位置（应该靠右）
    const expected_x = containing_box.box_model.content.width - float_box.box_model.content.width;
    try testing.expectEqual(expected_x, float_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), float_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 50), y); // y应该更新为浮动元素的高度
}

test "layoutFloat multiple floats - left floats stack horizontally" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const containing_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, containing_node);

    const float1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, float1_node);

    const float2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, float2_node);

    // 创建布局框
    var containing_box = box.LayoutBox.init(containing_node, allocator);
    containing_box.box_model.content.x = 0;
    containing_box.box_model.content.y = 0;
    containing_box.box_model.content.width = 800;
    containing_box.box_model.content.height = 600;
    defer containing_box.deinit();

    var float1_box = box.LayoutBox.init(float1_node, allocator);
    float1_box.float = .left;
    float1_box.box_model.content.width = 100;
    float1_box.box_model.content.height = 50;
    defer float1_box.deinit();

    var float2_box = box.LayoutBox.init(float2_node, allocator);
    float2_box.float = .left;
    float2_box.box_model.content.width = 100;
    float2_box.box_model.content.height = 50;
    defer float2_box.deinit();

    // 执行浮动布局（先布局第一个）
    var y: f32 = 0;
    float_layout.layoutFloat(&float1_box, &containing_box, &y);

    // 将第一个浮动元素添加到包含块的children中（用于后续的碰撞检测）
    try containing_box.children.append(allocator, &float1_box);

    // 布局第二个浮动元素（会检测到第一个的碰撞）
    // 注意：y已经被第一个浮动元素更新了，但我们需要在同一行布局，所以重置y
    y = 0;
    float_layout.layoutFloat(&float2_box, &containing_box, &y);

    // 将第二个浮动元素添加到包含块的children中
    try containing_box.children.append(allocator, &float2_box);

    // 检查第一个浮动元素位置
    try testing.expectEqual(@as(f32, 0), float1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), float1_box.box_model.content.y);

    // 检查第二个浮动元素位置（应该紧挨着第一个）
    try testing.expectEqual(@as(f32, 100), float2_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), float2_box.box_model.content.y);
}

test "layoutFloat boundary - empty containing block" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const containing_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, containing_node);

    const float_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, float_node);

    // 创建布局框
    var containing_box = box.LayoutBox.init(containing_node, allocator);
    containing_box.box_model.content.x = 0;
    containing_box.box_model.content.y = 0;
    containing_box.box_model.content.width = 0;
    containing_box.box_model.content.height = 0;
    defer containing_box.deinit();

    var float_box = box.LayoutBox.init(float_node, allocator);
    float_box.float = .left;
    float_box.box_model.content.width = 100;
    float_box.box_model.content.height = 50;
    defer float_box.deinit();

    // 执行浮动布局（应该能正常处理空包含块）
    var y: f32 = 0;
    float_layout.layoutFloat(&float_box, &containing_box, &y);

    // 位置应该仍然有效（即使包含块为空）
    try testing.expect(float_box.box_model.content.x >= 0);
    try testing.expect(float_box.box_model.content.y >= 0);
}

test "layoutFloat boundary - zero size float" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const containing_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, containing_node);

    const float_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, float_node);

    // 创建布局框
    var containing_box = box.LayoutBox.init(containing_node, allocator);
    containing_box.box_model.content.x = 0;
    containing_box.box_model.content.y = 0;
    containing_box.box_model.content.width = 800;
    containing_box.box_model.content.height = 600;
    defer containing_box.deinit();

    var float_box = box.LayoutBox.init(float_node, allocator);
    float_box.float = .left;
    float_box.box_model.content.width = 0;
    float_box.box_model.content.height = 0;
    defer float_box.deinit();

    // 执行浮动布局（应该能正常处理零尺寸浮动元素）
    var y: f32 = 0;
    float_layout.layoutFloat(&float_box, &containing_box, &y);

    // 位置应该仍然有效
    try testing.expect(float_box.box_model.content.x >= 0);
    try testing.expect(float_box.box_model.content.y >= 0);
}

test "clearFloats - calculate max y" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const containing_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, containing_node);

    const float1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, float1_node);

    const float2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, float2_node);

    // 创建布局框
    var containing_box = box.LayoutBox.init(containing_node, allocator);
    containing_box.box_model.content.x = 0;
    containing_box.box_model.content.y = 0;
    containing_box.box_model.content.width = 800;
    containing_box.box_model.content.height = 600;
    defer containing_box.deinit();

    var float1_box = box.LayoutBox.init(float1_node, allocator);
    float1_box.float = .left;
    float1_box.box_model.content.width = 100;
    float1_box.box_model.content.height = 50;
    defer float1_box.deinit();

    var float2_box = box.LayoutBox.init(float2_node, allocator);
    float2_box.float = .left;
    float2_box.box_model.content.width = 100;
    float2_box.box_model.content.height = 80;
    defer float2_box.deinit();

    // 执行浮动布局（先布局第一个）
    var y: f32 = 0;
    float_layout.layoutFloat(&float1_box, &containing_box, &y);

    // 将第一个浮动元素添加到包含块的children中（用于后续的碰撞检测和清除浮动）
    try containing_box.children.append(allocator, &float1_box);

    // 布局第二个浮动元素（会检测到第一个的碰撞）
    float_layout.layoutFloat(&float2_box, &containing_box, &y);

    // 将第二个浮动元素添加到包含块的children中
    try containing_box.children.append(allocator, &float2_box);

    // 清除浮动，应该返回最大y值
    const max_y = float_layout.clearFloats(&containing_box, y);

    // max_y应该是两个浮动元素中最大的底部位置
    // float1: y=0, height=50, bottom=50
    // float2: y=0, height=80, bottom=80
    // 所以max_y应该是80
    try testing.expect(max_y >= 80);
}

test "clearFloats boundary - no floats" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const containing_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, containing_node);

    // 创建布局框（没有浮动元素）
    var containing_box = box.LayoutBox.init(containing_node, allocator);
    containing_box.box_model.content.x = 0;
    containing_box.box_model.content.y = 0;
    containing_box.box_model.content.width = 800;
    containing_box.box_model.content.height = 600;
    defer containing_box.deinit();

    // 清除浮动（没有浮动元素时应该返回原始y值）
    const initial_y: f32 = 100;
    const max_y = float_layout.clearFloats(&containing_box, initial_y);

    // 如果没有浮动元素，应该返回原始y值
    try testing.expectEqual(initial_y, max_y);
}
