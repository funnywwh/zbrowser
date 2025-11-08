const std = @import("std");
const testing = std.testing;
const font = @import("font");

// 测试字体管理器初始化
test "FontManager init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var font_manager = font.FontManager.init(allocator);
    defer font_manager.deinit();

    // 测试：管理器应该可以正常初始化和清理
    try testing.expect(font_manager.font_cache.count() == 0);
}

// 测试字体管理器 - 空缓存
test "FontManager boundary - empty cache" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var font_manager = font.FontManager.init(allocator);
    defer font_manager.deinit();

    // 测试：从空缓存获取字体应该返回null
    const result = font_manager.getFont("nonexistent");
    try testing.expect(result == null);
}

// 测试字体管理器 - 查找不存在的字体
test "FontManager boundary - get non-existent font" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var font_manager = font.FontManager.init(allocator);
    defer font_manager.deinit();

    // 测试：查找不存在的字体
    const result1 = font_manager.getFont("");
    try testing.expect(result1 == null);

    const result2 = font_manager.getFont("Arial");
    try testing.expect(result2 == null);
}
