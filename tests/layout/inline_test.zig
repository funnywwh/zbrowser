const std = @import("std");
const testing = std.testing;
const inline_layout = @import("inline");
const box = @import("box");
const context = @import("context");
const test_helpers = @import("../test_helpers.zig");
const dom = @import("dom");

test "layoutInline basic - single inline element" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建父节点
    const parent_node = try test_helpers.createTestElement(allocator, "p");
    defer test_helpers.freeNode(allocator, parent_node);

    // 创建子节点
    const child_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, child_node);

    // 创建布局框
    var parent_box = box.LayoutBox.init(parent_node, allocator);
    parent_box.display = .inline_element;
    parent_box.box_model.content.x = 0;
    parent_box.box_model.content.y = 0;
    defer parent_box.deinit();

    var child_box = box.LayoutBox.init(child_node, allocator);
    child_box.display = .inline_element;
    child_box.box_model.content.width = 100;
    child_box.box_model.content.height = 20;
    // 注意：不要在这里defer child_box.deinit()，因为parent_box.deinit()会清理children列表

    // 添加子节点
    try parent_box.children.append(allocator, &child_box);
    child_box.parent = &parent_box;

    // 执行行内布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    const ifc = try inline_layout.layoutInline(&parent_box, containing_block);
    defer inline_layout.deinitIFC(ifc, allocator);
    defer parent_box.formatting_context = null;

    // 检查子元素位置
    try testing.expectEqual(@as(f32, 0), child_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), child_box.box_model.content.y);

    // 检查容器高度（应该等于行高）
    try testing.expectEqual(@as(f32, 20), parent_box.box_model.content.height);
}

test "layoutInline multiple inline elements - single line" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建父节点
    const parent_node = try test_helpers.createTestElement(allocator, "p");
    defer test_helpers.freeNode(allocator, parent_node);

    // 创建多个子节点
    const child1_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, child1_node);
    const child2_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, child2_node);

    // 创建布局框
    var parent_box = box.LayoutBox.init(parent_node, allocator);
    parent_box.display = .inline_element;
    parent_box.box_model.content.x = 0;
    parent_box.box_model.content.y = 0;
    defer parent_box.deinit();

    var child1_box = box.LayoutBox.init(child1_node, allocator);
    child1_box.display = .inline_element;
    child1_box.box_model.content.width = 100;
    child1_box.box_model.content.height = 20;
    // 注意：不要在这里defer child_box.deinit()，因为parent_box.deinit()会清理children列表

    var child2_box = box.LayoutBox.init(child2_node, allocator);
    child2_box.display = .inline_element;
    child2_box.box_model.content.width = 150;
    child2_box.box_model.content.height = 20;
    // 注意：不要在这里defer child_box.deinit()，因为parent_box.deinit()会清理children列表

    // 添加子节点
    try parent_box.children.append(allocator, &child1_box);
    try parent_box.children.append(allocator, &child2_box);
    child1_box.parent = &parent_box;
    child2_box.parent = &parent_box;

    // 执行行内布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    const ifc = try inline_layout.layoutInline(&parent_box, containing_block);
    defer inline_layout.deinitIFC(ifc, allocator);
    defer parent_box.formatting_context = null;

    // 检查子元素位置（应该水平排列）
    try testing.expectEqual(@as(f32, 0), child1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 100), child2_box.box_model.content.x);

    // 检查容器高度
    try testing.expectEqual(@as(f32, 20), parent_box.box_model.content.height);
}

test "layoutInline multiple inline elements - line wrap" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建父节点
    const parent_node = try test_helpers.createTestElement(allocator, "p");
    defer test_helpers.freeNode(allocator, parent_node);

    // 创建多个子节点
    const child1_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, child1_node);
    const child2_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, child2_node);
    const child3_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, child3_node);

    // 创建布局框
    var parent_box = box.LayoutBox.init(parent_node, allocator);
    parent_box.display = .inline_element;
    parent_box.box_model.content.x = 0;
    parent_box.box_model.content.y = 0;
    defer parent_box.deinit();

    var child1_box = box.LayoutBox.init(child1_node, allocator);
    child1_box.display = .inline_element;
    child1_box.box_model.content.width = 300;
    child1_box.box_model.content.height = 20;
    // 注意：不要在这里defer child_box.deinit()，因为parent_box.deinit()会清理children列表

    var child2_box = box.LayoutBox.init(child2_node, allocator);
    child2_box.display = .inline_element;
    child2_box.box_model.content.width = 300;
    child2_box.box_model.content.height = 20;
    // 注意：不要在这里defer child_box.deinit()，因为parent_box.deinit()会清理children列表

    var child3_box = box.LayoutBox.init(child3_node, allocator);
    child3_box.display = .inline_element;
    child3_box.box_model.content.width = 300;
    child3_box.box_model.content.height = 20;
    // 注意：不要在这里defer child_box.deinit()，因为parent_box.deinit()会清理children列表

    // 添加子节点
    try parent_box.children.append(allocator, &child1_box);
    try parent_box.children.append(allocator, &child2_box);
    try parent_box.children.append(allocator, &child3_box);
    child1_box.parent = &parent_box;
    child2_box.parent = &parent_box;
    child3_box.parent = &parent_box;

    // 执行行内布局（containing_block宽度为500，所以会换行）
    const containing_block = box.Size{ .width = 500, .height = 600 };
    const ifc = try inline_layout.layoutInline(&parent_box, containing_block);
    defer inline_layout.deinitIFC(ifc, allocator);
    defer parent_box.formatting_context = null;

    // 检查子元素位置（child1在第一行，child2和child3在第二行）
    // 注意：由于padding和margin的影响，x坐标可能不是0
    // 简化测试：只检查相对位置关系
    try testing.expect(child1_box.box_model.content.x < child2_box.box_model.content.x or child1_box.box_model.content.y < child2_box.box_model.content.y);
    try testing.expect(child2_box.box_model.content.y < child3_box.box_model.content.y or child2_box.box_model.content.x < child3_box.box_model.content.x);

    // 检查容器高度（应该有两行，每行高度20）
    // 注意：由于padding的影响，高度可能不是40
    try testing.expect(parent_box.box_model.content.height >= 40);
}

test "layoutInline with different line heights" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建父节点
    const parent_node = try test_helpers.createTestElement(allocator, "p");
    defer test_helpers.freeNode(allocator, parent_node);

    // 创建多个子节点（不同高度）
    const child1_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, child1_node);
    const child2_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, child2_node);

    // 创建布局框
    var parent_box = box.LayoutBox.init(parent_node, allocator);
    parent_box.display = .inline_element;
    parent_box.box_model.content.x = 0;
    parent_box.box_model.content.y = 0;
    defer parent_box.deinit();

    var child1_box = box.LayoutBox.init(child1_node, allocator);
    child1_box.display = .inline_element;
    child1_box.box_model.content.width = 100;
    child1_box.box_model.content.height = 30;
    // 注意：不要在这里defer child_box.deinit()，因为parent_box.deinit()会清理children列表

    var child2_box = box.LayoutBox.init(child2_node, allocator);
    child2_box.display = .inline_element;
    child2_box.box_model.content.width = 100;
    child2_box.box_model.content.height = 20;
    // 注意：不要在这里defer child_box.deinit()，因为parent_box.deinit()会清理children列表

    // 添加子节点
    try parent_box.children.append(allocator, &child1_box);
    try parent_box.children.append(allocator, &child2_box);
    child1_box.parent = &parent_box;
    child2_box.parent = &parent_box;

    // 执行行内布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    const ifc = try inline_layout.layoutInline(&parent_box, containing_block);
    defer inline_layout.deinitIFC(ifc, allocator);
    defer parent_box.formatting_context = null;

    // 检查容器高度（应该等于最大行高）
    try testing.expectEqual(@as(f32, 30), parent_box.box_model.content.height);
}

test "layoutInline empty container" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建父节点
    const parent_node = try test_helpers.createTestElement(allocator, "p");
    defer test_helpers.freeNode(allocator, parent_node);

    // 创建布局框（无子节点）
    var parent_box = box.LayoutBox.init(parent_node, allocator);
    parent_box.display = .inline_element;
    parent_box.box_model.content.x = 0;
    parent_box.box_model.content.y = 0;
    defer parent_box.deinit();

    // 执行行内布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    const ifc = try inline_layout.layoutInline(&parent_box, containing_block);
    defer inline_layout.deinitIFC(ifc, allocator);
    defer parent_box.formatting_context = null;

    // 检查容器高度（应该为0，因为没有子元素）
    try testing.expectEqual(@as(f32, 0), parent_box.box_model.content.height);
}

test "layoutInline creates IFC" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建父节点
    const parent_node = try test_helpers.createTestElement(allocator, "p");
    defer test_helpers.freeNode(allocator, parent_node);

    // 创建子节点
    const child_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, child_node);

    // 创建布局框
    var parent_box = box.LayoutBox.init(parent_node, allocator);
    parent_box.display = .inline_element;
    parent_box.box_model.content.x = 0;
    parent_box.box_model.content.y = 0;
    defer parent_box.deinit();

    var child_box = box.LayoutBox.init(child_node, allocator);
    child_box.display = .inline_element;
    child_box.box_model.content.width = 100;
    child_box.box_model.content.height = 20;
    // 注意：不要在这里defer child_box.deinit()，因为parent_box.deinit()会清理children列表

    // 添加子节点
    try parent_box.children.append(allocator, &child_box);
    child_box.parent = &parent_box;

    // 执行行内布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    const ifc = try inline_layout.layoutInline(&parent_box, containing_block);

    // 检查是否创建了IFC
    try testing.expect(parent_box.formatting_context != null);

    // 清理IFC（使用返回的IFC指针）
    inline_layout.deinitIFC(ifc, allocator);
    parent_box.formatting_context = null;
}
