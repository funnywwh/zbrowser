const std = @import("std");
const testing = std.testing;
const Browser = @import("main").Browser;
const helpers = @import("test_page_render_helpers.zig");

// 测试：输出h1元素的详细布局信息
test "h1 layout info - detailed" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html_content = try helpers.readTestPage(allocator);
    defer allocator.free(html_content);

    const css_content = try helpers.extractCSSFromHTML(html_content, allocator);
    defer allocator.free(css_content);

    var browser = try Browser.init(allocator);
    defer browser.deinit();

    try browser.loadHTML(html_content);
    try browser.addStylesheet(css_content);

    const width: u32 = 1200;
    const height: u32 = 3000;
    
    // 获取h1的布局信息
    const h1_layout = try helpers.getElementLayoutInfo(&browser, allocator, @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)), "h1", null, null);
    
    if (h1_layout) |layout| {
        std.debug.print("\n=== H1 Element Layout Info ===\n", .{});
        std.debug.print("Position (content box):\n", .{});
        std.debug.print("  x: {d:.2}\n", .{layout.x});
        std.debug.print("  y: {d:.2}\n", .{layout.y});
        std.debug.print("Size (content box):\n", .{});
        std.debug.print("  width: {d:.2}\n", .{layout.width});
        std.debug.print("  height: {d:.2}\n", .{layout.height});
        std.debug.print("Margins:\n", .{});
        std.debug.print("  top: {d:.2}, right: {d:.2}, bottom: {d:.2}, left: {d:.2}\n", .{ layout.margin_top, layout.margin_right, layout.margin_bottom, layout.margin_left });
        std.debug.print("Borders:\n", .{});
        std.debug.print("  top: {d:.2}, right: {d:.2}, bottom: {d:.2}, left: {d:.2}\n", .{ layout.border_top, layout.border_right, layout.border_bottom, layout.border_left });
        std.debug.print("Total Box (including border and margin):\n", .{});
        const total_x = layout.x - layout.margin_left - layout.border_left;
        const total_y = layout.y - layout.margin_top - layout.border_top;
        const total_width = layout.width + layout.margin_left + layout.margin_right + layout.border_left + layout.border_right;
        const total_height = layout.height + layout.margin_top + layout.margin_bottom + layout.border_top + layout.border_bottom;
        std.debug.print("  x: {d:.2}\n", .{total_x});
        std.debug.print("  y: {d:.2}\n", .{total_y});
        std.debug.print("  width: {d:.2}\n", .{total_width});
        std.debug.print("  height: {d:.2}\n", .{total_height});
        std.debug.print("==============================\n\n", .{});
        
        // 验证h1存在
        try testing.expect(layout.width > 0);
        try testing.expect(layout.height > 0);
    } else {
        std.debug.print("ERROR: h1 element not found!\n", .{});
        try testing.expect(false); // 强制失败
    }
}

