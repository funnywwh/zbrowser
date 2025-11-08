const std = @import("std");
const testing = std.testing;
const box = @import("box");
const test_helpers = @import("../test_helpers.zig");
const dom = @import("dom");

test "Rect contains point" {
    const rect = box.Rect{
        .x = 10,
        .y = 20,
        .width = 100,
        .height = 50,
    };

    // 点在矩形内
    try testing.expect(rect.contains(box.Point{ .x = 50, .y = 40 }));
    // 点在矩形左上角
    try testing.expect(rect.contains(box.Point{ .x = 10, .y = 20 }));
    // 点在矩形右下角（边界外）
    try testing.expect(!rect.contains(box.Point{ .x = 110, .y = 70 }));
    // 点在矩形外
    try testing.expect(!rect.contains(box.Point{ .x = 5, .y = 15 }));
}

test "Rect intersects" {
    const rect1 = box.Rect{
        .x = 10,
        .y = 20,
        .width = 100,
        .height = 50,
    };

    // 相交
    const rect2 = box.Rect{
        .x = 50,
        .y = 40,
        .width = 100,
        .height = 50,
    };
    try testing.expect(rect1.intersects(rect2));

    // 不相交
    const rect3 = box.Rect{
        .x = 200,
        .y = 200,
        .width = 100,
        .height = 50,
    };
    try testing.expect(!rect1.intersects(rect3));

    // 相邻（不相交）
    const rect4 = box.Rect{
        .x = 110,
        .y = 20,
        .width = 100,
        .height = 50,
    };
    try testing.expect(!rect1.intersects(rect4));
}

test "Edges horizontal and vertical" {
    const edges = box.Edges{
        .top = 10,
        .right = 20,
        .bottom = 30,
        .left = 40,
    };

    try testing.expectEqual(@as(f32, 60), edges.horizontal());
    try testing.expectEqual(@as(f32, 40), edges.vertical());
}

test "BoxModel totalSize content-box" {
    const box_model = box.BoxModel{
        .content = box.Rect{
            .x = 0,
            .y = 0,
            .width = 100,
            .height = 50,
        },
        .padding = box.Edges{
            .top = 10,
            .right = 20,
            .bottom = 30,
            .left = 40,
        },
        .border = box.Edges{
            .top = 5,
            .right = 10,
            .bottom = 15,
            .left = 20,
        },
        .margin = box.Edges{
            .top = 0,
            .right = 0,
            .bottom = 0,
            .left = 0,
        },
        .box_sizing = .content_box,
    };

    const total = box_model.totalSize();
    // content-box: width = content.width + padding + border
    // width = 100 + 40 + 20 + 20 + 10 = 190
    // height = 50 + 10 + 30 + 5 + 15 = 110
    try testing.expectEqual(@as(f32, 190), total.width);
    try testing.expectEqual(@as(f32, 110), total.height);
}

test "BoxModel totalSize border-box" {
    const box_model = box.BoxModel{
        .content = box.Rect{
            .x = 0,
            .y = 0,
            .width = 100,
            .height = 50,
        },
        .padding = box.Edges{
            .top = 10,
            .right = 20,
            .bottom = 30,
            .left = 40,
        },
        .border = box.Edges{
            .top = 5,
            .right = 10,
            .bottom = 15,
            .left = 20,
        },
        .margin = box.Edges{
            .top = 0,
            .right = 0,
            .bottom = 0,
            .left = 0,
        },
        .box_sizing = .border_box,
    };

    const total = box_model.totalSize();
    // border-box: width = content.width (content已经包含padding和border)
    try testing.expectEqual(@as(f32, 100), total.width);
    try testing.expectEqual(@as(f32, 50), total.height);
}

test "LayoutBox init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框（使用值而不是指针）
    var layout_box = box.LayoutBox.init(node, allocator);
    defer layout_box.deinit();

    // 检查初始值
    try testing.expectEqual(node, layout_box.node);
    try testing.expectEqual(box.DisplayType.block, layout_box.display);
    try testing.expectEqual(box.PositionType.static, layout_box.position);
    try testing.expectEqual(box.FloatType.none, layout_box.float);
    try testing.expectEqual(@as(usize, 0), layout_box.children.items.len);
    try testing.expect(layout_box.parent == null);
    try testing.expect(!layout_box.is_layouted);
}

test "LayoutBox with children" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建父节点
    const parent_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, parent_node);

    // 创建子节点
    const child1_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, child1_node);
    const child2_node = try test_helpers.createTestElement(allocator, "p");
    defer test_helpers.freeNode(allocator, child2_node);

    // 创建布局框
    const parent_box = try allocator.create(box.LayoutBox);
    parent_box.* = box.LayoutBox.init(parent_node, allocator);
    defer {
        parent_box.deinit();
        allocator.destroy(parent_box);
    }

    const child1_box = try allocator.create(box.LayoutBox);
    child1_box.* = box.LayoutBox.init(child1_node, allocator);
    // 注意：子节点会被父节点deinit时清理，所以不需要单独deinit

    const child2_box = try allocator.create(box.LayoutBox);
    child2_box.* = box.LayoutBox.init(child2_node, allocator);
    // 注意：子节点会被父节点deinit时清理，所以不需要单独deinit

    // 添加子布局框
    try parent_box.children.append(child1_box);
    try parent_box.children.append(child2_box);
    child1_box.parent = parent_box;
    child2_box.parent = parent_box;

    // 检查
    try testing.expectEqual(@as(usize, 2), parent_box.children.items.len);
    try testing.expectEqual(child1_box, parent_box.children.items[0]);
    try testing.expectEqual(child2_box, parent_box.children.items[1]);
    try testing.expectEqual(parent_box, child1_box.parent);
    try testing.expectEqual(parent_box, child2_box.parent);

    // 清理子节点的内存（deinit已经由父节点完成）
    allocator.destroy(child1_box);
    allocator.destroy(child2_box);
}

test "Size basic operations" {
    const size1 = box.Size{ .width = 100, .height = 50 };
    const size2 = box.Size{ .width = 200, .height = 100 };

    try testing.expectEqual(@as(f32, 100), size1.width);
    try testing.expectEqual(@as(f32, 50), size1.height);
    try testing.expectEqual(@as(f32, 200), size2.width);
    try testing.expectEqual(@as(f32, 100), size2.height);
}

test "Point basic operations" {
    const point1 = box.Point{ .x = 10, .y = 20 };
    const point2 = box.Point{ .x = 30, .y = 40 };

    try testing.expectEqual(@as(f32, 10), point1.x);
    try testing.expectEqual(@as(f32, 20), point1.y);
    try testing.expectEqual(@as(f32, 30), point2.x);
    try testing.expectEqual(@as(f32, 40), point2.y);
}
