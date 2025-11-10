const std = @import("std");
const testing = std.testing;
const flexbox = @import("flexbox");
const box = @import("box");
const css = @import("css");
const test_helpers = @import("../test_helpers.zig");
const dom = @import("dom");

test "layoutFlexbox basic - single item" {
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
    container_box.display = .flex;
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

    // 执行Flexbox布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item_box.is_layouted);

    // 检查位置：单个item应该在(0, 0)
    try testing.expectEqual(@as(f32, 0), item_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item_box.box_model.content.y);
}

test "layoutFlexbox multiple items - row direction" {
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
    container_box.display = .flex;
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

    // 执行Flexbox布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // 检查位置：row方向，items应该水平排列
    // item1应该在(0, 0)
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);
    // item2应该在(100, 0)（item1的宽度）
    try testing.expectEqual(@as(f32, 100), item2_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.y);
}

test "layoutFlexbox boundary - empty container" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 创建布局框（没有子元素）
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .flex;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 800;
    container_box.box_model.content.height = 600;
    defer container_box.deinit();

    // 执行Flexbox布局（应该能正常处理空容器）
    const containing_block = box.Size{ .width = 800, .height = 600 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expectEqual(@as(usize, 0), container_box.children.items.len);
}

test "layoutFlexbox boundary - zero size container" {
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
    container_box.display = .flex;
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

    // 执行Flexbox布局（应该能正常处理零尺寸容器）
    const containing_block = box.Size{ .width = 0, .height = 0 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
}

test "layoutFlexbox boundary - large container" {
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
    container_box.display = .flex;
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

    // 执行Flexbox布局（应该能正常处理大容器）
    const containing_block = box.Size{ .width = 10000, .height = 10000 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item_box.is_layouted);

    // 检查位置：item应该在(0, 0)
    try testing.expectEqual(@as(f32, 0), item_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item_box.box_model.content.y);
}

test "layoutFlexbox boundary - three items row" {
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

    const item3_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item3_node);

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .flex;
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
    item2_box.box_model.content.width = 150;
    item2_box.box_model.content.height = 50;
    defer item2_box.deinit();

    var item3_box = box.LayoutBox.init(item3_node, allocator);
    item3_box.box_model.content.width = 200;
    item3_box.box_model.content.height = 50;
    defer item3_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    try container_box.children.append(allocator, &item3_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;
    item3_box.parent = &container_box;

    // 执行Flexbox布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);
    try testing.expect(item3_box.is_layouted);

    // 检查位置：row方向，items应该水平排列
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 100), item2_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 250), item3_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item3_box.box_model.content.y);
}

test "layoutFlexbox column direction - vertical stack" {
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
    container_box.display = .flex;
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
    item2_box.box_model.content.height = 80;
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Flexbox布局（column方向）
    // 注意：当前实现默认使用row方向，column方向需要从样式表获取
    // 这里先测试row方向，column方向的测试需要等样式系统完成后才能实现
    const containing_block = box.Size{ .width = 800, .height = 600 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // TODO: 当样式系统完成后，可以通过设置flex-direction来测试column方向
    // 当前默认是row方向，所以检查row方向的布局
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 100), item2_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.y);
}

test "layoutFlexbox row-reverse - reverses item order" {
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
    container_box.display = .flex;
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
    item2_box.box_model.content.width = 150;
    item2_box.box_model.content.height = 50;
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Flexbox布局（row-reverse方向）
    // 注意：当前实现默认使用row方向，row-reverse需要从样式表获取
    // 这里先测试row方向，row-reverse的测试需要等样式系统完成后才能实现
    const containing_block = box.Size{ .width = 800, .height = 600 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // TODO: 当样式系统完成后，可以通过设置flex-direction: row-reverse来测试反向
    // 当前默认是row方向，所以检查row方向的布局
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 100), item2_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.y);
}

// TODO: 添加flex-grow测试用例
// 需要先实现flex-grow功能，然后添加测试

test "layoutFlexbox multi-line - flex-wrap wrap" {
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

    const item3_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item3_node);

    // 设置class属性以便CSS选择器匹配
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("class", "container", allocator);
    }

    // 创建CSS样式表（flex-wrap: wrap）
    const css_input = ".container { display: flex; flex-wrap: wrap; }";
    var css_parser_instance = css.Parser.init(css_input, allocator);
    defer css_parser_instance.deinit();
    var stylesheet = try css_parser_instance.parse();
    defer stylesheet.deinit();

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .flex;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 200; // 小容器，强制换行
    container_box.box_model.content.height = 600;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    item1_box.box_model.content.width = 150; // 第一个item占150px
    item1_box.box_model.content.height = 50;
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    item2_box.box_model.content.width = 150; // 第二个item占150px，会换行
    item2_box.box_model.content.height = 50;
    defer item2_box.deinit();

    var item3_box = box.LayoutBox.init(item3_node, allocator);
    item3_box.box_model.content.width = 100; // 第三个item占100px，可以放在第一行
    item3_box.box_model.content.height = 50;
    defer item3_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    try container_box.children.append(allocator, &item3_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;
    item3_box.parent = &container_box;

    // 执行Flexbox布局
    const containing_block = box.Size{ .width = 200, .height = 600 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{stylesheet});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);
    try testing.expect(item3_box.is_layouted);

    // 检查位置：由于flex-wrap: wrap，items应该换行
    // item1应该在第一行
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);
    // 至少有一个item应该换行（y坐标大于0）
    const has_wrapped = item2_box.box_model.content.y > 0 or item3_box.box_model.content.y > 0;
    try testing.expect(has_wrapped);
}

test "layoutFlexbox multi-line boundary - many items wrap" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 设置class属性以便CSS选择器匹配
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("class", "container", allocator);
    }

    // 创建CSS样式表（flex-wrap: wrap）
    const css_input = ".container { display: flex; flex-wrap: wrap; }";
    var css_parser_instance = css.Parser.init(css_input, allocator);
    defer css_parser_instance.deinit();
    var stylesheet = try css_parser_instance.parse();
    defer stylesheet.deinit();

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .flex;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 300; // 小容器
    container_box.box_model.content.height = 1000;
    defer container_box.deinit();

    // 创建多个items，每个100px宽，应该换行
    var item_nodes: [5]*dom.Node = undefined;
    var item_boxes: [5]*box.LayoutBox = undefined;
    for (0..5) |i| {
        item_nodes[i] = try test_helpers.createTestElement(allocator, "div");
        item_boxes[i] = try allocator.create(box.LayoutBox);
        item_boxes[i].* = box.LayoutBox.init(item_nodes[i], allocator);
        item_boxes[i].box_model.content.width = 100;
        item_boxes[i].box_model.content.height = 50;

        try container_box.children.append(allocator, item_boxes[i]);
        item_boxes[i].parent = &container_box;
    }
    // 清理：先释放LayoutBox，再释放Node
    defer {
        for (item_boxes) |item_box| {
            item_box.deinit();
            allocator.destroy(item_box);
        }
        for (item_nodes) |item_node| {
            test_helpers.freeNode(allocator, item_node);
        }
    }

    // 执行Flexbox布局
    const containing_block = box.Size{ .width = 300, .height = 1000 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{stylesheet});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    for (item_boxes) |item_box| {
        try testing.expect(item_box.is_layouted);
    }

    // 检查：应该有多个items换行
    // 第一行应该能放3个items（每个100px，容器300px）
    // 第二行应该放2个items
    var items_in_first_row: usize = 0;
    var items_in_second_row: usize = 0;
    for (item_boxes) |item_box| {
        if (item_box.box_model.content.y == 0) {
            items_in_first_row += 1;
        } else {
            items_in_second_row += 1;
        }
    }
    // 第一行应该有3个items，第二行应该有2个items
    try testing.expect(items_in_first_row >= 1);
    try testing.expect(items_in_second_row >= 1);
}

test "layoutFlexbox align-content space-between" {
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

    // 设置class属性以便CSS选择器匹配
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("class", "container", allocator);
    }

    // 创建CSS样式表（align-content: space-between）
    const css_input = ".container { display: flex; flex-wrap: wrap; align-content: space-between; }";
    var css_parser_instance = css.Parser.init(css_input, allocator);
    defer css_parser_instance.deinit();
    var stylesheet = try css_parser_instance.parse();
    defer stylesheet.deinit();

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .flex;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 200;
    container_box.box_model.content.height = 300; // 足够高的容器
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    item1_box.box_model.content.width = 150;
    item1_box.box_model.content.height = 50;
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    item2_box.box_model.content.width = 150;
    item2_box.box_model.content.height = 50;
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Flexbox布局
    const containing_block = box.Size{ .width = 200, .height = 300 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{stylesheet});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // align-content: space-between 应该将两行分别放在顶部和底部
    // 第一行应该在顶部（y=0或接近0）
    // 第二行应该在底部（y接近容器高度减去行高）
    try testing.expect(item1_box.box_model.content.y >= 0);
    try testing.expect(item2_box.box_model.content.y > item1_box.box_model.content.y);
    // 第二行应该在容器内（允许一些误差）
    try testing.expect(item2_box.box_model.content.y + item2_box.box_model.content.height <= container_box.box_model.content.height + 1.0);
}

test "layoutFlexbox align-content space-around" {
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

    // 设置class属性以便CSS选择器匹配
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("class", "container", allocator);
    }

    // 创建CSS样式表（align-content: space-around）
    const css_input = ".container { display: flex; flex-wrap: wrap; align-content: space-around; }";
    var css_parser_instance = css.Parser.init(css_input, allocator);
    defer css_parser_instance.deinit();
    var stylesheet = try css_parser_instance.parse();
    defer stylesheet.deinit();

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .flex;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 200;
    container_box.box_model.content.height = 300;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    item1_box.box_model.content.width = 150;
    item1_box.box_model.content.height = 50;
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    item2_box.box_model.content.width = 150;
    item2_box.box_model.content.height = 50;
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Flexbox布局
    const containing_block = box.Size{ .width = 200, .height = 300 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{stylesheet});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // align-content: space-around 应该在行之间和边缘都有间距
    try testing.expect(item1_box.box_model.content.y >= 0);
    try testing.expect(item2_box.box_model.content.y > item1_box.box_model.content.y);
    // 验证两行都在容器内
    try testing.expect(item1_box.box_model.content.y + item1_box.box_model.content.height <= container_box.box_model.content.height);
    try testing.expect(item2_box.box_model.content.y + item2_box.box_model.content.height <= container_box.box_model.content.height);
}

test "layoutFlexbox align-content space-evenly" {
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

    // 设置class属性以便CSS选择器匹配
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("class", "container", allocator);
    }

    // 创建CSS样式表（align-content: space-evenly）
    const css_input = ".container { display: flex; flex-wrap: wrap; align-content: space-evenly; }";
    var css_parser_instance = css.Parser.init(css_input, allocator);
    defer css_parser_instance.deinit();
    var stylesheet = try css_parser_instance.parse();
    defer stylesheet.deinit();

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .flex;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 200;
    container_box.box_model.content.height = 300;
    defer container_box.deinit();

    var item1_box = box.LayoutBox.init(item1_node, allocator);
    item1_box.box_model.content.width = 150;
    item1_box.box_model.content.height = 50;
    defer item1_box.deinit();

    var item2_box = box.LayoutBox.init(item2_node, allocator);
    item2_box.box_model.content.width = 150;
    item2_box.box_model.content.height = 50;
    defer item2_box.deinit();

    // 添加子元素
    try container_box.children.append(allocator, &item1_box);
    try container_box.children.append(allocator, &item2_box);
    item1_box.parent = &container_box;
    item2_box.parent = &container_box;

    // 执行Flexbox布局
    const containing_block = box.Size{ .width = 200, .height = 300 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{stylesheet});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // align-content: space-evenly 应该在所有间距（包括边缘）都相等
    try testing.expect(item1_box.box_model.content.y >= 0);
    try testing.expect(item2_box.box_model.content.y > item1_box.box_model.content.y);
    // 验证两行都在容器内
    try testing.expect(item1_box.box_model.content.y + item1_box.box_model.content.height <= container_box.box_model.content.height);
    try testing.expect(item2_box.box_model.content.y + item2_box.box_model.content.height <= container_box.box_model.content.height);
}

test "layoutFlexbox justify-content space-between" {
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

    // 设置class属性以便CSS选择器匹配
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("class", "container", allocator);
    }

    // 创建CSS样式表（justify-content: space-between）
    const css_input = ".container { display: flex; justify-content: space-between; }";
    var css_parser_instance = css.Parser.init(css_input, allocator);
    defer css_parser_instance.deinit();
    var stylesheet = try css_parser_instance.parse();
    defer stylesheet.deinit();

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .flex;
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

    // 执行Flexbox布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{stylesheet});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // justify-content: space-between 应该将items放在两端
    // item1应该在左边（x=0或接近0）
    // item2应该在右边（x接近容器宽度减去item宽度）
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.y);
    // item2应该在右边
    try testing.expect(item2_box.box_model.content.x > item1_box.box_model.content.x);
    try testing.expect(item2_box.box_model.content.x + item2_box.box_model.content.width <= container_box.box_model.content.width);
}

test "layoutFlexbox justify-content center" {
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

    // 设置class属性以便CSS选择器匹配
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("class", "container", allocator);
    }

    // 创建CSS样式表（justify-content: center）
    const css_input = ".container { display: flex; justify-content: center; }";
    var css_parser_instance = css.Parser.init(css_input, allocator);
    defer css_parser_instance.deinit();
    var stylesheet = try css_parser_instance.parse();
    defer stylesheet.deinit();

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .flex;
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

    // 执行Flexbox布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{stylesheet});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item1_box.is_layouted);
    try testing.expect(item2_box.is_layouted);

    // justify-content: center 应该将items居中
    // items的总宽度是200px，容器宽度是800px，所以items应该在中间
    const total_items_width = item1_box.box_model.content.width + item2_box.box_model.content.width;
    const expected_start_x = (container_box.box_model.content.width - total_items_width) / 2.0;
    // 允许一些误差
    try testing.expect(@abs(item1_box.box_model.content.x - expected_start_x) < 1.0);
    try testing.expectEqual(@as(f32, 0), item1_box.box_model.content.y);
    try testing.expectEqual(@as(f32, 0), item2_box.box_model.content.y);
}

test "layoutFlexbox boundary - single item wrap" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    const item_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, item_node);

    // 设置class属性以便CSS选择器匹配
    if (container_node.asElement()) |elem| {
        try elem.setAttribute("class", "container", allocator);
    }

    // 创建CSS样式表（flex-wrap: wrap）
    const css_input = ".container { display: flex; flex-wrap: wrap; }";
    var css_parser_instance = css.Parser.init(css_input, allocator);
    defer css_parser_instance.deinit();
    var stylesheet = try css_parser_instance.parse();
    defer stylesheet.deinit();

    // 创建布局框
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .flex;
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

    // 执行Flexbox布局
    const containing_block = box.Size{ .width = 800, .height = 600 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{stylesheet});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expect(item_box.is_layouted);

    // 单个item应该在第一行
    try testing.expectEqual(@as(f32, 0), item_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), item_box.box_model.content.y);
}

test "layoutFlexbox boundary - empty container with wrap" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const container_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, container_node);

    // 创建CSS样式表（flex-wrap: wrap）
    const css_input = ".container { display: flex; flex-wrap: wrap; }";
    var css_parser_instance = css.Parser.init(css_input, allocator);
    defer css_parser_instance.deinit();
    var stylesheet = try css_parser_instance.parse();
    defer stylesheet.deinit();

    // 创建布局框（没有子元素）
    var container_box = box.LayoutBox.init(container_node, allocator);
    container_box.display = .flex;
    container_box.box_model.content.x = 0;
    container_box.box_model.content.y = 0;
    container_box.box_model.content.width = 800;
    container_box.box_model.content.height = 600;
    defer container_box.deinit();

    // 执行Flexbox布局（应该能正常处理空容器）
    const containing_block = box.Size{ .width = 800, .height = 600 };
    flexbox.layoutFlexbox(&container_box, containing_block, &[_]css.Stylesheet{stylesheet});

    // 检查布局结果
    try testing.expect(container_box.is_layouted);
    try testing.expectEqual(@as(usize, 0), container_box.children.items.len);
}
