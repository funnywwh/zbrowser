const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 创建主程序需要的模块
    const string_module_exe = b.createModule(.{
        .root_source_file = b.path("src/utils/string.zig"),
        .target = target,
        .optimize = optimize,
    });

    const dom_module_exe = b.createModule(.{
        .root_source_file = b.path("src/html/dom.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "string", .module = string_module_exe },
        },
    });

    const tokenizer_module_exe = b.createModule(.{
        .root_source_file = b.path("src/html/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "string", .module = string_module_exe },
        },
    });

    const html_module_exe = b.createModule(.{
        .root_source_file = b.path("src/html/parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module_exe },
            .{ .name = "tokenizer", .module = tokenizer_module_exe },
            .{ .name = "string", .module = string_module_exe },
        },
    });

    // 注意：exe模块定义需要放在所有依赖模块定义之后
    // 暂时注释掉，稍后重新定义

    // 创建工具模块
    // 注意：string_module已由string_module_exe替代，这里不再定义
    // const string_module = b.createModule(.{
    //     .root_source_file = b.path("src/utils/string.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // 创建依赖模块
    // 注意：dom_module已由dom_module_exe替代，这里不再定义
    // const dom_module = b.createModule(.{
    //     .root_source_file = b.path("src/html/dom.zig"),
    //     .target = target,
    //     .optimize = optimize,
    //     .imports = &.{
    //         .{ .name = "string", .module = string_module },
    //     },
    // });

    const tokenizer_module = b.createModule(.{
        .root_source_file = b.path("src/html/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "string", .module = string_module_exe },
        },
    });

    // html模块依赖dom和tokenizer
    const html_module = b.createModule(.{
        .root_source_file = b.path("src/html/parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module_exe },
            .{ .name = "tokenizer", .module = tokenizer_module },
            .{ .name = "string", .module = string_module_exe },
        },
    });

    // 注意：test_module (src/test/runner.zig) 不再使用
    // 所有测试都通过 test.zig 统一入口运行

    // CSS模块
    const css_tokenizer_module = b.createModule(.{
        .root_source_file = b.path("src/css/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "string", .module = string_module_exe },
        },
    });

    const css_selector_module_for_parser = b.createModule(.{
        .root_source_file = b.path("src/css/selector.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module_exe },
            .{ .name = "string", .module = string_module_exe },
        },
    });

    // CSS parser 模块 - 统一使用一个实例避免冲突
    const css_parser_module = b.createModule(.{
        .root_source_file = b.path("src/css/parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "tokenizer", .module = css_tokenizer_module },
            .{ .name = "selector", .module = css_selector_module_for_parser },
        },
    });

    // 使用统一的 css_parser_module 避免重复
    const css_parser_module_for_cascade = css_parser_module;

    const css_cascade_module = b.createModule(.{
        .root_source_file = b.path("src/css/cascade.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module_exe },
            .{ .name = "parser", .module = css_parser_module_for_cascade },
            .{ .name = "selector", .module = css_selector_module_for_parser },
        },
    });

    // Layout模块
    const layout_box_module = b.createModule(.{
        .root_source_file = b.path("src/layout/box.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module_exe },
        },
    });

    const layout_context_module = b.createModule(.{
        .root_source_file = b.path("src/layout/context.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
        },
    });

    const layout_block_module = b.createModule(.{
        .root_source_file = b.path("src/layout/block.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
        },
    });

    const layout_inline_module = b.createModule(.{
        .root_source_file = b.path("src/layout/inline.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "context", .module = layout_context_module },
        },
    });

    const layout_position_module = b.createModule(.{
        .root_source_file = b.path("src/layout/position.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
        },
    });

    const layout_float_module = b.createModule(.{
        .root_source_file = b.path("src/layout/float.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
        },
    });

    const layout_style_utils_module = b.createModule(.{
        .root_source_file = b.path("src/layout/style_utils.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "cascade", .module = css_cascade_module },
            .{ .name = "parser", .module = css_parser_module },
        },
    });

    const layout_flexbox_module = b.createModule(.{
        .root_source_file = b.path("src/layout/flexbox.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "cascade", .module = css_cascade_module },
            .{ .name = "parser", .module = css_parser_module },
            .{ .name = "style_utils", .module = layout_style_utils_module },
        },
    });

    const layout_grid_module = b.createModule(.{
        .root_source_file = b.path("src/layout/grid.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "cascade", .module = css_cascade_module },
            .{ .name = "parser", .module = css_parser_module },
            .{ .name = "style_utils", .module = layout_style_utils_module },
        },
    });

    const layout_engine_module = b.createModule(.{
        .root_source_file = b.path("src/layout/engine.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module_exe },
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "block", .module = layout_block_module },
            .{ .name = "inline", .module = layout_inline_module },
            .{ .name = "flexbox", .module = layout_flexbox_module },
            .{ .name = "grid", .module = layout_grid_module },
            .{ .name = "cascade", .module = css_cascade_module },
            .{ .name = "parser", .module = css_parser_module },
            .{ .name = "style_utils", .module = layout_style_utils_module },
        },
    });

    // Render模块
    const render_backend_module = b.createModule(.{
        .root_source_file = b.path("src/render/backend.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Font模块（需要在render_cpu_backend_module之前定义）
    const font_ttf_module = b.createModule(.{
        .root_source_file = b.path("src/font/ttf.zig"),
        .target = target,
        .optimize = optimize,
    });

    const font_glyph_module = b.createModule(.{
        .root_source_file = b.path("src/font/glyph.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "backend", .module = render_backend_module },
            .{ .name = "ttf", .module = font_ttf_module },
        },
    });

    const font_module = b.createModule(.{
        .root_source_file = b.path("src/font/font.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ttf", .module = font_ttf_module },
        },
    });

    const render_cpu_backend_module = b.createModule(.{
        .root_source_file = b.path("src/render/cpu_backend.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "backend", .module = render_backend_module },
            .{ .name = "font", .module = font_module },
            .{ .name = "glyph", .module = font_glyph_module },
        },
    });

    const render_renderer_module = b.createModule(.{
        .root_source_file = b.path("src/render/renderer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "dom", .module = dom_module_exe },
            .{ .name = "cascade", .module = css_cascade_module },
            .{ .name = "parser", .module = css_parser_module },
            .{ .name = "backend", .module = render_backend_module },
            .{ .name = "style_utils", .module = layout_style_utils_module },
        },
    });

    // Image模块
    const image_deflate_module = b.createModule(.{
        .root_source_file = b.path("src/image/deflate.zig"),
        .target = target,
        .optimize = optimize,
    });

    const image_png_module = b.createModule(.{
        .root_source_file = b.path("src/image/png.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "deflate", .module = image_deflate_module },
        },
    });

    // 创建allocator模块（用于main可执行文件）
    const allocator_module_for_exe = b.createModule(.{
        .root_source_file = b.path("src/utils/allocator.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 定义exe模块（在所有依赖模块定义之后）
    const exe = b.addExecutable(.{
        .name = "zbrowser",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "html", .module = html_module_exe },
                .{ .name = "dom", .module = dom_module_exe },
                .{ .name = "allocator", .module = allocator_module_for_exe },
                .{ .name = "parser", .module = css_parser_module },
                .{ .name = "engine", .module = layout_engine_module },
                .{ .name = "box", .module = layout_box_module },
                .{ .name = "cpu_backend", .module = render_cpu_backend_module },
                .{ .name = "renderer", .module = render_renderer_module },
                .{ .name = "png", .module = image_png_module },
                // 添加其他依赖模块
                .{ .name = "cascade", .module = css_cascade_module },
                .{ .name = "backend", .module = render_backend_module },
                .{ .name = "style_utils", .module = layout_style_utils_module },
            },
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // 添加PNG直接测试程序
    const png_test_exe = b.addExecutable(.{
        .name = "test_png_direct",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/image/test_png_direct.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "png", .module = image_png_module },
            },
        }),
    });
    b.installArtifact(png_test_exe);
    const run_png_test = b.addRunArtifact(png_test_exe);
    const png_test_step = b.step("test-png", "Test PNG encoder directly");
    png_test_step.dependOn(&run_png_test.step);

    // 创建根测试模块（统一入口）
    // test.zig 作为根测试文件，统一导入所有子测试模块
    // 所有测试都通过 test.zig 运行，不需要单独的测试配置

    // 创建allocator模块（在main模块之前，以便main模块可以引用）
    const allocator_module_for_tests = b.createModule(.{
        .root_source_file = b.path("src/utils/allocator.zig"),
        .target = target,
        .optimize = optimize,
    });

    const root_test_module = b.createModule(.{
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            // HTML模块
            .{ .name = "html", .module = html_module },
            .{ .name = "dom", .module = dom_module_exe },
            .{ .name = "tokenizer", .module = tokenizer_module }, // HTML tokenizer
            // CSS模块
            .{ .name = "css", .module = css_parser_module },
            .{ .name = "selector", .module = css_selector_module_for_parser },
            .{ .name = "cascade", .module = css_cascade_module },
            // CSS tokenizer - 使用不同的名称避免冲突
            .{ .name = "css_tokenizer", .module = css_tokenizer_module },
            // Utils模块
            .{ .name = "string", .module = string_module_exe },
            .{ .name = "math", .module = b.createModule(.{
                .root_source_file = b.path("src/utils/math.zig"),
                .target = target,
                .optimize = optimize,
            }) },
            .{ .name = "allocator", .module = allocator_module_for_tests },
            // Layout模块
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "context", .module = layout_context_module },
            .{ .name = "block", .module = layout_block_module },
            .{ .name = "inline", .module = layout_inline_module },
            .{ .name = "position", .module = layout_position_module },
            .{ .name = "float", .module = layout_float_module },
            .{ .name = "flexbox", .module = layout_flexbox_module },
            .{ .name = "grid", .module = layout_grid_module },
            .{ .name = "style_utils", .module = layout_style_utils_module },
            .{ .name = "engine", .module = layout_engine_module },
            // Render模块
            .{ .name = "backend", .module = render_backend_module },
            .{ .name = "cpu_backend", .module = render_cpu_backend_module },
            .{ .name = "renderer", .module = render_renderer_module },
            .{ .name = "main", .module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "html", .module = html_module },
                    .{ .name = "dom", .module = dom_module_exe },
                    .{ .name = "parser", .module = css_parser_module },
                    .{ .name = "engine", .module = layout_engine_module },
                    .{ .name = "box", .module = layout_box_module },
                    .{ .name = "cpu_backend", .module = render_cpu_backend_module },
                    .{ .name = "renderer", .module = render_renderer_module },
                    .{ .name = "png", .module = image_png_module },
                    .{ .name = "cascade", .module = css_cascade_module },
                    .{ .name = "backend", .module = render_backend_module },
                    .{ .name = "style_utils", .module = layout_style_utils_module },
                    .{ .name = "allocator", .module = allocator_module_for_tests },
                },
            }) },
            // Image模块
            .{ .name = "png", .module = image_png_module },
            .{ .name = "deflate", .module = image_deflate_module },
            // Font模块
            .{ .name = "font", .module = font_module },
            .{ .name = "ttf", .module = font_ttf_module },
            .{ .name = "glyph", .module = font_glyph_module },
            .{ .name = "backend", .module = render_backend_module },
        },
    });

    // 根测试（统一入口）- 所有测试都通过 test.zig 运行
    const root_tests = b.addTest(.{
        .root_module = root_test_module,
    });

    const run_root_tests = b.addRunArtifact(root_tests);

    // 主测试步骤（运行所有测试）
    // 所有测试都通过 test.zig 统一入口运行
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_root_tests.step);
}
