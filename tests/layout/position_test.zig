const std = @import("std");
const testing = std.testing;
const position = @import("position");
const box = @import("box");
const test_helpers = @import("../test_helpers.zig");
const dom = @import("dom");

test "layoutPosition static - no offset" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    layout_box.position = .static;
    layout_box.box_model.content.x = 10;
    layout_box.box_model.content.y = 20;
    defer layout_box.deinit();

    // static定位不应该改变位置
    position.layoutPosition(&layout_box, box.Size{ .width = 800, .height = 600 });

    // 位置应该保持不变
    try testing.expectEqual(@as(f32, 10), layout_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 20), layout_box.box_model.content.y);
}

test "layoutPosition relative - with offset" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    layout_box.position = .relative;
    layout_box.box_model.content.x = 10;
    layout_box.box_model.content.y = 20;
    layout_box.position_left = 30;
    layout_box.position_top = 40;
    defer layout_box.deinit();

    // relative定位应该相对于正常位置偏移
    position.layoutPosition(&layout_box, box.Size{ .width = 800, .height = 600 });

    // 位置应该根据offset调整
    try testing.expectEqual(@as(f32, 40), layout_box.box_model.content.x); // 10 + 30
    try testing.expectEqual(@as(f32, 60), layout_box.box_model.content.y); // 20 + 40
}

test "layoutPosition absolute - positioned relative to containing block" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    layout_box.position = .absolute;
    layout_box.box_model.content.x = 0;
    layout_box.box_model.content.y = 0;
    layout_box.box_model.content.width = 100;
    layout_box.box_model.content.height = 50;
    layout_box.position_left = 50;
    layout_box.position_top = 100;
    defer layout_box.deinit();

    // absolute定位应该相对于包含块定位
    position.layoutPosition(&layout_box, box.Size{ .width = 800, .height = 600 });

    // 位置应该根据top、left计算
    try testing.expectEqual(@as(f32, 50), layout_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 100), layout_box.box_model.content.y);
}

test "layoutPosition fixed - positioned relative to viewport" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    layout_box.position = .fixed;
    layout_box.box_model.content.x = 0;
    layout_box.box_model.content.y = 0;
    layout_box.box_model.content.width = 100;
    layout_box.box_model.content.height = 50;
    layout_box.position_left = 200;
    layout_box.position_top = 150;
    defer layout_box.deinit();

    // fixed定位应该相对于视口定位
    position.layoutPosition(&layout_box, box.Size{ .width = 800, .height = 600 });

    // 位置应该根据top、left计算，相对于视口
    try testing.expectEqual(@as(f32, 200), layout_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 150), layout_box.box_model.content.y);
}

test "layoutPosition sticky - sticks to position when scrolling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    layout_box.position = .sticky;
    layout_box.box_model.content.x = 10;
    layout_box.box_model.content.y = 20;
    layout_box.position_left = 30;
    layout_box.position_top = 40;
    defer layout_box.deinit();

    // sticky定位在滚动时会"粘"在指定位置
    // TODO: 完整实现需要跟踪滚动位置，当前只处理初始位置
    position.layoutPosition(&layout_box, box.Size{ .width = 800, .height = 600 });

    // 初始位置应该使用relative定位逻辑
    try testing.expectEqual(@as(f32, 40), layout_box.box_model.content.x); // 10 + 30
    try testing.expectEqual(@as(f32, 60), layout_box.box_model.content.y); // 20 + 40
}

test "layoutPosition boundary - empty input" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    layout_box.position = .static;
    layout_box.box_model.content.x = 0;
    layout_box.box_model.content.y = 0;
    layout_box.box_model.content.width = 0;
    layout_box.box_model.content.height = 0;
    defer layout_box.deinit();

    // 空尺寸的布局框应该能正常处理
    position.layoutPosition(&layout_box, box.Size{ .width = 0, .height = 0 });

    try testing.expectEqual(@as(f32, 0), layout_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 0), layout_box.box_model.content.y);
}

test "layoutPosition boundary - zero viewport" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    layout_box.position = .static;
    layout_box.box_model.content.x = 10;
    layout_box.box_model.content.y = 20;
    defer layout_box.deinit();

    // 零视口应该能正常处理
    position.layoutPosition(&layout_box, box.Size{ .width = 0, .height = 0 });

    // static定位不应该改变位置
    try testing.expectEqual(@as(f32, 10), layout_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 20), layout_box.box_model.content.y);
}

test "layoutPosition boundary - large viewport" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    layout_box.position = .static;
    layout_box.box_model.content.x = 100;
    layout_box.box_model.content.y = 200;
    defer layout_box.deinit();

    // 大视口应该能正常处理
    position.layoutPosition(&layout_box, box.Size{ .width = 10000, .height = 10000 });

    // static定位不应该改变位置
    try testing.expectEqual(@as(f32, 100), layout_box.box_model.content.x);
    try testing.expectEqual(@as(f32, 200), layout_box.box_model.content.y);
}
