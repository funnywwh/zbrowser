const std = @import("std");
const testing = std.testing;
const block = @import("block");
const box = @import("box");
const test_helpers = @import("../test_helpers.zig");
const dom = @import("dom");

test "calculateBlockWidth with auto width" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    // 测试auto宽度（应该使用containing_block的宽度）
    const containing_block = box.Size{ .width = 800, .height = 600 };
    const width = block.calculateBlockWidth(&layout_box, containing_block);

    // auto宽度应该等于containing_block的宽度（简化实现）
    try testing.expectEqual(@as(f32, 800), width);
}

test "calculateBlockWidth with fixed width" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    // 设置固定宽度（通过box_model）
    layout_box.box_model.content.width = 500;

    const containing_block = box.Size{ .width = 800, .height = 600 };
    const width = block.calculateBlockWidth(&layout_box, containing_block);

    // 如果已经设置了宽度，应该使用设置的宽度
    try testing.expectEqual(@as(f32, 500), width);
}

test "layoutBlock basic - single child" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建父节点
    const parent_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, parent_node);

    // 创建子节点
    const child_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, child_node);

    // 创建布局框
    var parent_box = box.LayoutBox.init(parent_node, allocator);
    parent_box.box_model.content.x = 0;
    parent_box.box_model.content.y = 0;
    defer parent_box.deinit();

    var child_box = box.LayoutBox.init(child_node, allocator);
    child_box.box_model.content.width = 100;
    child_box.box_model.content.height = 50;
    defer child_box.deinit();

    // 添加子节点
    try parent_box.children.append(&child_box);
    child_box.parent = &parent_box;

    // 执行块级布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    try block.layoutBlock(&parent_box, containing_block);

    // 检查父元素宽度
    try testing.expectEqual(@as(f32, 800), parent_box.box_model.content.width);

    // 检查子元素位置
    try testing.expectEqual(@as(f32, 0), child_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), child_box.box_model.content.y);

    // 检查父元素高度（应该等于子元素高度）
    try testing.expectEqual(@as(f32, 50), parent_box.box_model.content.height);
}

test "layoutBlock multiple children" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建父节点
    const parent_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, parent_node);

    // 创建多个子节点
    const child1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, child1_node);
    const child2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, child2_node);
    const child3_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, child3_node);

    // 创建布局框
    var parent_box = box.LayoutBox.init(parent_node, allocator);
    parent_box.box_model.content.x = 0;
    parent_box.box_model.content.y = 0;
    defer parent_box.deinit();

    var child1_box = box.LayoutBox.init(child1_node, allocator);
    child1_box.box_model.content.width = 100;
    child1_box.box_model.content.height = 50;
    defer child1_box.deinit();

    var child2_box = box.LayoutBox.init(child2_node, allocator);
    child2_box.box_model.content.width = 100;
    child2_box.box_model.content.height = 60;
    defer child2_box.deinit();

    var child3_box = box.LayoutBox.init(child3_node, allocator);
    child3_box.box_model.content.width = 100;
    child3_box.box_model.content.height = 40;
    defer child3_box.deinit();

    // 添加子节点
    try parent_box.children.append(&child1_box);
    try parent_box.children.append(&child2_box);
    try parent_box.children.append(&child3_box);
    child1_box.parent = &parent_box;
    child2_box.parent = &parent_box;
    child3_box.parent = &parent_box;

    // 执行块级布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    try block.layoutBlock(&parent_box, containing_block);

    // 检查子元素位置（应该垂直排列）
    try testing.expectEqual(@as(f32, 0), child1_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 50), child2_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 110), child3_box.box_model.content.y);

    // 检查父元素高度（应该等于所有子元素高度之和）
    try testing.expectEqual(@as(f32, 150), parent_box.box_model.content.height);
}

test "layoutBlock with margin" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建父节点
    const parent_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, parent_node);

    // 创建子节点
    const child_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, child_node);

    // 创建布局框
    var parent_box = box.LayoutBox.init(parent_node, allocator);
    parent_box.box_model.content.x = 0;
    parent_box.box_model.content.y = 0;
    defer parent_box.deinit();

    var child_box = box.LayoutBox.init(child_node, allocator);
    child_box.box_model.content.width = 100;
    child_box.box_model.content.height = 50;
    child_box.box_model.margin.top = 10;
    child_box.box_model.margin.bottom = 20;
    defer child_box.deinit();

    // 添加子节点
    try parent_box.children.append(&child_box);
    child_box.parent = &parent_box;

    // 执行块级布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    try block.layoutBlock(&parent_box, containing_block);

    // 检查父元素高度（应该包含margin）
    const expected_height = child_box.box_model.content.height + child_box.box_model.margin.top + child_box.box_model.margin.bottom;
    try testing.expectEqual(expected_height, parent_box.box_model.content.height);
}

test "layoutBlock empty container" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建父节点
    const parent_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, parent_node);

    // 创建布局框（无子节点）
    var parent_box = box.LayoutBox.init(parent_node, allocator);
    parent_box.box_model.content.x = 0;
    parent_box.box_model.content.y = 0;
    defer parent_box.deinit();

    // 执行块级布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    try block.layoutBlock(&parent_box, containing_block);

    // 检查父元素宽度
    try testing.expectEqual(@as(f32, 800), parent_box.box_model.content.width);

    // 检查父元素高度（应该为0，因为没有子元素）
    try testing.expectEqual(@as(f32, 0), parent_box.box_model.content.height);
}

test "layoutBlock with padding" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建父节点
    const parent_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, parent_node);

    // 创建子节点
    const child_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, child_node);

    // 创建布局框
    var parent_box = box.LayoutBox.init(parent_node, allocator);
    parent_box.box_model.content.x = 0;
    parent_box.box_model.content.y = 0;
    parent_box.box_model.padding.top = 10;
    parent_box.box_model.padding.bottom = 20;
    defer parent_box.deinit();

    var child_box = box.LayoutBox.init(child_node, allocator);
    child_box.box_model.content.width = 100;
    child_box.box_model.content.height = 50;
    defer child_box.deinit();

    // 添加子节点
    try parent_box.children.append(&child_box);
    child_box.parent = &parent_box;

    // 执行块级布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    try block.layoutBlock(&parent_box, containing_block);

    // 检查子元素位置（应该考虑padding）
    try testing.expectEqual(@as(f32, 10), child_box.box_model.content.y);

    // 检查父元素高度（应该包含padding）
    const expected_height = child_box.box_model.content.height + parent_box.box_model.padding.top + parent_box.box_model.padding.bottom;
    try testing.expectEqual(expected_height, parent_box.box_model.content.height);
}
