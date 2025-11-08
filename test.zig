const std = @import("std");

/// 根测试文件 - 统一导入所有子测试模块
///
/// 这个文件作为所有测试的统一入口点，通过导入各个子测试模块
/// 来确保所有测试都被编译和运行。
///
/// 所有测试都通过此文件统一运行，不需要单独的测试配置。
///
/// 使用方法：
///   zig build test          # 运行所有测试（通过根测试文件）

// HTML模块测试
const html_parser_test = @import("tests/html/parser_test.zig");
const html_tokenizer_test = @import("tests/html/tokenizer_test.zig");
const html_dom_test = @import("tests/html/dom_test.zig");

// CSS模块测试
const css_parser_test = @import("tests/css/parser_test.zig");
const css_tokenizer_test = @import("tests/css/tokenizer_test.zig");
const css_selector_test = @import("tests/css/selector_test.zig");
const css_cascade_test = @import("tests/css/cascade_test.zig");

// Utils模块测试
const string_test = @import("tests/utils/string_test.zig");
const math_test = @import("tests/utils/math_test.zig");
const allocator_test = @import("tests/utils/allocator_test.zig");

// Layout模块测试
const layout_box_test = @import("tests/layout/box_test.zig");
const layout_context_test = @import("tests/layout/context_test.zig");
const layout_block_test = @import("tests/layout/block_test.zig");
const layout_inline_test = @import("tests/layout/inline_test.zig");
const layout_position_test = @import("tests/layout/position_test.zig");
const layout_float_test = @import("tests/layout/float_test.zig");
const layout_flexbox_test = @import("tests/layout/flexbox_test.zig");
const layout_grid_test = @import("tests/layout/grid_test.zig");
const layout_engine_test = @import("tests/layout/engine_test.zig");

// Render模块测试
const render_backend_test = @import("tests/render/backend_test.zig");
const render_cpu_backend_test = @import("tests/render/cpu_backend_test.zig");

/// 测试统计信息
pub const TestStats = struct {
    total: usize = 0,
    passed: usize = 0,
    failed: usize = 0,
};

/// 运行所有测试并收集统计信息
pub fn runAllTests() !TestStats {
    const stats = TestStats{};

    std.debug.print("Running all tests via root test file...\n", .{});

    // 注意：Zig的测试框架会自动运行所有导入的测试
    // 这里主要是为了文档和未来的扩展

    return stats;
}

// 测试：确保所有测试模块都被正确导入
test "all test modules imported" {
    // 这个测试确保所有模块都被导入
    _ = html_parser_test;
    _ = html_tokenizer_test;
    _ = html_dom_test;
    _ = css_parser_test;
    _ = css_tokenizer_test;
    _ = css_selector_test;
    _ = css_cascade_test;
    _ = string_test;
    _ = math_test;
    _ = allocator_test;
    _ = layout_box_test;
    _ = layout_context_test;
    _ = layout_block_test;
    _ = layout_inline_test;
    _ = layout_position_test;
    _ = layout_float_test;
    _ = layout_flexbox_test;
    _ = layout_grid_test;
    _ = layout_engine_test;
    _ = render_backend_test;
    _ = render_cpu_backend_test;

    std.debug.print("All test modules successfully imported via root test file\n", .{});
}
