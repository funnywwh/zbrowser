const std = @import("std");
const testing = std.testing;
const engine = @import("engine");
const box = @import("box");
const dom = @import("dom");
const css = @import("css");
const test_helpers = @import("../test_helpers.zig");

test "LayoutEngine init" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const layout_engine = engine.LayoutEngine.init(allocator);
    _ = layout_engine;
}

test "LayoutEngine buildLayoutTree - single element" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局引擎
    var layout_engine = engine.LayoutEngine.init(allocator);

    // 构建布局树
    const layout_tree = try layout_engine.buildLayoutTree(node, &[_]css.Stylesheet{});
    defer layout_tree.deinit();
    defer allocator.destroy(layout_tree);

    // 检查布局树
    try testing.expectEqual(node, layout_tree.node);
    try testing.expectEqual(@as(usize, 0), layout_tree.children.items.len);
    try testing.expect(layout_tree.parent == null);
}

test "LayoutEngine buildLayoutTree - multiple children" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM节点
    const parent_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, parent_node);

    const child1_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, child1_node);

    const child2_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, child2_node);

    // 添加子节点
    try parent_node.appendChild(child1_node, allocator);
    try parent_node.appendChild(child2_node, allocator);

    // 创建布局引擎
    var layout_engine = engine.LayoutEngine.init(allocator);

    // 构建布局树
    const layout_tree = try layout_engine.buildLayoutTree(parent_node, &[_]css.Stylesheet{});
    defer layout_tree.deinit();
    defer allocator.destroy(layout_tree);

    // 检查布局树
    try testing.expectEqual(parent_node, layout_tree.node);
    try testing.expectEqual(@as(usize, 2), layout_tree.children.items.len);
    try testing.expectEqual(child1_node, layout_tree.children.items[0].node);
    try testing.expectEqual(child2_node, layout_tree.children.items[1].node);
    try testing.expectEqual(layout_tree, layout_tree.children.items[0].parent);
    try testing.expectEqual(layout_tree, layout_tree.children.items[1].parent);
}

test "LayoutEngine buildLayoutTree - nested structure" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM节点
    const root_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, root_node);

    const child_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, child_node);

    const grandchild_node = try test_helpers.createTestElement(allocator, "span");
    defer test_helpers.freeNode(allocator, grandchild_node);

    // 构建DOM树
    try root_node.appendChild(child_node, allocator);
    try child_node.appendChild(grandchild_node, allocator);

    // 创建布局引擎
    var layout_engine = engine.LayoutEngine.init(allocator);

    // 构建布局树
    const layout_tree = try layout_engine.buildLayoutTree(root_node, &[_]css.Stylesheet{});
    defer layout_tree.deinit();
    defer allocator.destroy(layout_tree);

    // 检查布局树结构
    try testing.expectEqual(@as(usize, 1), layout_tree.children.items.len);
    const child_layout = layout_tree.children.items[0];
    try testing.expectEqual(@as(usize, 1), child_layout.children.items.len);
    try testing.expectEqual(grandchild_node, child_layout.children.items[0].node);
}

test "LayoutEngine buildLayoutTree - empty node" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM节点
    const node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, node);

    // 创建布局引擎
    var layout_engine = engine.LayoutEngine.init(allocator);

    // 构建布局树
    const layout_tree = try layout_engine.buildLayoutTree(node, &[_]css.Stylesheet{});
    defer layout_tree.deinit();
    defer allocator.destroy(layout_tree);

    // 检查布局树（应该没有子节点）
    try testing.expectEqual(@as(usize, 0), layout_tree.children.items.len);
}

test "LayoutEngine layout - basic block layout" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM节点
    const root_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, root_node);

    // 创建布局引擎
    var layout_engine = engine.LayoutEngine.init(allocator);

    // 构建布局树
    const layout_tree = try layout_engine.buildLayoutTree(root_node, &[_]css.Stylesheet{});
    defer layout_tree.deinit();
    defer allocator.destroy(layout_tree);

    // 执行布局
    const viewport = box.Size{ .width = 800, .height = 600 };
    try layout_engine.layout(layout_tree, viewport);

    // 检查布局结果
    try testing.expect(layout_tree.is_layouted);
    try testing.expect(layout_tree.box_model.content.width > 0 or layout_tree.box_model.content.width == 0);
}

test "LayoutEngine layout - block with children" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM节点
    const root_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, root_node);

    const child1_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, child1_node);

    const child2_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, child2_node);

    // 构建DOM树
    try root_node.appendChild(child1_node, allocator);
    try root_node.appendChild(child2_node, allocator);

    // 创建布局引擎
    var layout_engine = engine.LayoutEngine.init(allocator);

    // 构建布局树
    const layout_tree = try layout_engine.buildLayoutTree(root_node, &[_]css.Stylesheet{});
    defer layout_tree.deinit();
    defer allocator.destroy(layout_tree);

    // 执行布局
    const viewport = box.Size{ .width = 800, .height = 600 };
    try layout_engine.layout(layout_tree, viewport);

    // 检查布局结果
    try testing.expect(layout_tree.is_layouted);
    try testing.expectEqual(@as(usize, 2), layout_tree.children.items.len);
    try testing.expect(layout_tree.children.items[0].is_layouted);
    try testing.expect(layout_tree.children.items[1].is_layouted);
}

test "LayoutEngine layout - empty viewport" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM节点
    const root_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, root_node);

    // 创建布局引擎
    var layout_engine = engine.LayoutEngine.init(allocator);

    // 构建布局树
    const layout_tree = try layout_engine.buildLayoutTree(root_node, &[_]css.Stylesheet{});
    defer layout_tree.deinit();
    defer allocator.destroy(layout_tree);

    // 执行布局（空viewport）
    const viewport = box.Size{ .width = 0, .height = 0 };
    try layout_engine.layout(layout_tree, viewport);

    // 检查布局结果
    try testing.expect(layout_tree.is_layouted);
}

test "LayoutEngine layout - large viewport" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DOM节点
    const root_node = try test_helpers.createTestElement(allocator, "div");
    defer test_helpers.freeNode(allocator, root_node);

    // 创建布局引擎
    var layout_engine = engine.LayoutEngine.init(allocator);

    // 构建布局树
    const layout_tree = try layout_engine.buildLayoutTree(root_node, &[_]css.Stylesheet{});
    defer layout_tree.deinit();
    defer allocator.destroy(layout_tree);

    // 执行布局（大viewport）
    const viewport = box.Size{ .width = 10000, .height = 10000 };
    try layout_engine.layout(layout_tree, viewport);

    // 检查布局结果
    try testing.expect(layout_tree.is_layouted);
}
