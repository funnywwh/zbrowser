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

test "layoutPosition relative - with right and bottom" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框
    var layout_box = box.LayoutBox.init(node, allocator);
    layout_box.position = .relative;
    layout_box.box_model.content.x = 100;
    layout_box.box_model.content.y = 200;
    layout_box.box_model.content.width = 50;
    layout_box.box_model.content.height = 30;
    // 不设置left和top，使用right和bottom
    layout_box.position_right = 20;
    layout_box.position_bottom = 10;
    defer layout_box.deinit();

    // relative定位应该相对于正常位置偏移
    // containing_block: 800x600
    // 元素正常位置: (100, 200), 尺寸: 50x30
    // right=20: 从包含块右边缘向左偏移20，即 x = 800 - 20 - 50 = 730
    // bottom=10: 从包含块底边缘向上偏移10，即 y = 600 - 10 - 30 = 560
    // 但relative是相对于正常位置的偏移，所以：
    // x偏移 = (800 - 20 - 50) - 100 = 630
    // y偏移 = (600 - 10 - 30) - 200 = 360
    position.layoutPosition(&layout_box, box.Size{ .width = 800, .height = 600 });

    // 位置应该根据right和bottom计算偏移
    try testing.expectEqual(@as(f32, 730), layout_box.box_model.content.x); // 800 - 20 - 50
    try testing.expectEqual(@as(f32, 560), layout_box.box_model.content.y); // 600 - 10 - 30
}

test "layoutPosition relative - left takes priority over right" {
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
    // 同时设置left和right，left应该优先
    layout_box.position_left = 30;
    layout_box.position_right = 20;
    defer layout_box.deinit();

    // relative定位应该使用left（优先于right）
    position.layoutPosition(&layout_box, box.Size{ .width = 800, .height = 600 });

    // 位置应该根据left计算，忽略right
    try testing.expectEqual(@as(f32, 40), layout_box.box_model.content.x); // 10 + 30
    try testing.expectEqual(@as(f32, 20), layout_box.box_model.content.y); // 20 (没有top/bottom)
}

test "layoutPosition relative - top takes priority over bottom" {
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
    layout_box.box_model.content.width = 50;
    layout_box.box_model.content.height = 30;
    // 同时设置top和bottom，top应该优先
    layout_box.position_top = 40;
    layout_box.position_bottom = 10;
    defer layout_box.deinit();

    // relative定位应该使用top（优先于bottom）
    position.layoutPosition(&layout_box, box.Size{ .width = 800, .height = 600 });

    // 位置应该根据top计算，忽略bottom
    try testing.expectEqual(@as(f32, 10), layout_box.box_model.content.x); // 10 (没有left/right)
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

test "layoutPosition absolute - finds positioned ancestor" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点：创建一个有定位祖先的层次结构
    const ancestor_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, ancestor_node);

    const child_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, child_node);

    // 创建布局框
    var ancestor_box = box.LayoutBox.init(ancestor_node, allocator);
    ancestor_box.position = .relative; // 定位祖先
    ancestor_box.box_model.content.x = 100;
    ancestor_box.box_model.content.y = 200;
    ancestor_box.box_model.content.width = 500;
    ancestor_box.box_model.content.height = 400;
    defer ancestor_box.deinit();

    var child_box = box.LayoutBox.init(child_node, allocator);
    child_box.position = .absolute;
    child_box.box_model.content.width = 50;
    child_box.box_model.content.height = 30;
    child_box.position_left = 20;
    child_box.position_top = 10;
    child_box.parent = &ancestor_box; // 设置父节点
    defer child_box.deinit();

    // absolute定位应该相对于定位祖先定位
    // 定位祖先位置: (100, 200)
    // child应该位于: (100 + 20, 200 + 10) = (120, 210)
    position.layoutPosition(&child_box, box.Size{ .width = 800, .height = 600 });

    // 位置应该相对于定位祖先计算
    try testing.expectEqual(@as(f32, 120), child_box.box_model.content.x); // 100 + 20
    try testing.expectEqual(@as(f32, 210), child_box.box_model.content.y); // 200 + 10
}

test "layoutPosition absolute - no positioned ancestor uses viewport" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点：没有定位祖先
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局框（没有父节点，或父节点是static）
    var layout_box = box.LayoutBox.init(node, allocator);
    layout_box.position = .absolute;
    layout_box.box_model.content.width = 100;
    layout_box.box_model.content.height = 50;
    layout_box.position_left = 50;
    layout_box.position_top = 100;
    layout_box.parent = null; // 没有父节点
    defer layout_box.deinit();

    // absolute定位应该相对于视口定位（因为没有定位祖先）
    position.layoutPosition(&layout_box, box.Size{ .width = 800, .height = 600 });

    // 位置应该相对于视口(0, 0)计算
    try testing.expectEqual(@as(f32, 50), layout_box.box_model.content.x); // 0 + 50
    try testing.expectEqual(@as(f32, 100), layout_box.box_model.content.y); // 0 + 100
}

test "layoutPosition absolute - skips static ancestors" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建测试节点：static父节点 -> relative祖先 -> absolute子节点
    const static_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, static_node);

    const relative_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, relative_node);

    const absolute_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, absolute_node);

    // 创建布局框
    var static_box = box.LayoutBox.init(static_node, allocator);
    static_box.position = .static; // static定位，不应该作为定位祖先
    static_box.box_model.content.x = 10;
    static_box.box_model.content.y = 20;
    static_box.box_model.content.width = 600;
    static_box.box_model.content.height = 500;
    defer static_box.deinit();

    var relative_box = box.LayoutBox.init(relative_node, allocator);
    relative_box.position = .relative; // 定位祖先
    relative_box.box_model.content.x = 100;
    relative_box.box_model.content.y = 200;
    relative_box.box_model.content.width = 500;
    relative_box.box_model.content.height = 400;
    relative_box.parent = &static_box;
    defer relative_box.deinit();

    var absolute_box = box.LayoutBox.init(absolute_node, allocator);
    absolute_box.position = .absolute;
    absolute_box.box_model.content.width = 50;
    absolute_box.box_model.content.height = 30;
    absolute_box.position_left = 20;
    absolute_box.position_top = 10;
    absolute_box.parent = &relative_box; // 父节点是relative_box
    defer absolute_box.deinit();

    // absolute定位应该跳过static父节点，找到relative祖先
    // relative祖先位置: (100, 200)
    // absolute应该位于: (100 + 20, 200 + 10) = (120, 210)
    position.layoutPosition(&absolute_box, box.Size{ .width = 800, .height = 600 });

    // 位置应该相对于relative祖先计算，而不是static父节点
    try testing.expectEqual(@as(f32, 120), absolute_box.box_model.content.x); // 100 + 20
    try testing.expectEqual(@as(f32, 210), absolute_box.box_model.content.y); // 200 + 10
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
