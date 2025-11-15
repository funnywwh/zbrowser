const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 创建所有需要的模块（使用相对路径引用项目根目录的src）
    const string_module = b.createModule(.{
        .root_source_file = b.path("../src/utils/string.zig"),
        .target = target,
        .optimize = optimize,
    });

    const dom_module = b.createModule(.{
        .root_source_file = b.path("../src/html/dom.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "string", .module = string_module },
        },
    });

    const tokenizer_module = b.createModule(.{
        .root_source_file = b.path("../src/html/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "string", .module = string_module },
        },
    });

    const html_module = b.createModule(.{
        .root_source_file = b.path("../src/html/parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module },
            .{ .name = "tokenizer", .module = tokenizer_module },
            .{ .name = "string", .module = string_module },
        },
    });

    const css_tokenizer_module = b.createModule(.{
        .root_source_file = b.path("../src/css/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "string", .module = string_module },
        },
    });

    const css_selector_module = b.createModule(.{
        .root_source_file = b.path("../src/css/selector.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module },
            .{ .name = "string", .module = string_module },
        },
    });

    const css_parser_module = b.createModule(.{
        .root_source_file = b.path("../src/css/parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "tokenizer", .module = css_tokenizer_module },
            .{ .name = "selector", .module = css_selector_module },
        },
    });

    const css_cascade_module = b.createModule(.{
        .root_source_file = b.path("../src/css/cascade.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module },
            .{ .name = "parser", .module = css_parser_module },
            .{ .name = "selector", .module = css_selector_module },
        },
    });

    const layout_box_module = b.createModule(.{
        .root_source_file = b.path("../src/layout/box.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module },
            .{ .name = "cascade", .module = css_cascade_module },
        },
    });

    const layout_context_module = b.createModule(.{
        .root_source_file = b.path("../src/layout/context.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
        },
    });

    const layout_float_module = b.createModule(.{
        .root_source_file = b.path("../src/layout/float.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
        },
    });

    const layout_style_utils_module = b.createModule(.{
        .root_source_file = b.path("../src/layout/style_utils.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "cascade", .module = css_cascade_module },
            .{ .name = "parser", .module = css_parser_module },
        },
    });

    const layout_block_module = b.createModule(.{
        .root_source_file = b.path("../src/layout/block.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "float", .module = layout_float_module },
            .{ .name = "style_utils", .module = layout_style_utils_module },
            .{ .name = "parser", .module = css_parser_module },
            .{ .name = "cascade", .module = css_cascade_module },
        },
    });

    const layout_inline_module = b.createModule(.{
        .root_source_file = b.path("../src/layout/inline.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "context", .module = layout_context_module },
        },
    });

    const layout_position_module = b.createModule(.{
        .root_source_file = b.path("../src/layout/position.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
        },
    });

    const layout_flexbox_module = b.createModule(.{
        .root_source_file = b.path("../src/layout/flexbox.zig"),
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
        .root_source_file = b.path("../src/layout/grid.zig"),
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
        .root_source_file = b.path("../src/layout/engine.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module },
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "block", .module = layout_block_module },
            .{ .name = "inline", .module = layout_inline_module },
            .{ .name = "flexbox", .module = layout_flexbox_module },
            .{ .name = "grid", .module = layout_grid_module },
            .{ .name = "context", .module = layout_context_module },
            .{ .name = "position", .module = layout_position_module },
            .{ .name = "cascade", .module = css_cascade_module },
            .{ .name = "parser", .module = css_parser_module },
            .{ .name = "style_utils", .module = layout_style_utils_module },
        },
    });

    const render_backend_module = b.createModule(.{
        .root_source_file = b.path("../src/render/backend.zig"),
        .target = target,
        .optimize = optimize,
    });

    const font_cff_module = b.createModule(.{
        .root_source_file = b.path("../src/font/cff.zig"),
        .target = target,
        .optimize = optimize,
    });

    const font_ttf_module = b.createModule(.{
        .root_source_file = b.path("../src/font/ttf.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cff", .module = font_cff_module },
        },
    });

    const font_hinting_module = b.createModule(.{
        .root_source_file = b.path("../src/font/hinting.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ttf", .module = font_ttf_module },
        },
    });

    const font_glyph_module = b.createModule(.{
        .root_source_file = b.path("../src/font/glyph.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "backend", .module = render_backend_module },
            .{ .name = "ttf", .module = font_ttf_module },
            .{ .name = "hinting", .module = font_hinting_module },
        },
    });

    const font_module = b.createModule(.{
        .root_source_file = b.path("../src/font/font.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ttf", .module = font_ttf_module },
        },
    });

    const render_cpu_backend_module = b.createModule(.{
        .root_source_file = b.path("../src/render/cpu_backend.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "backend", .module = render_backend_module },
            .{ .name = "font", .module = font_module },
            .{ .name = "glyph", .module = font_glyph_module },
        },
    });

    const render_renderer_module = b.createModule(.{
        .root_source_file = b.path("../src/render/renderer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "dom", .module = dom_module },
            .{ .name = "cascade", .module = css_cascade_module },
            .{ .name = "parser", .module = css_parser_module },
            .{ .name = "backend", .module = render_backend_module },
            .{ .name = "style_utils", .module = layout_style_utils_module },
        },
    });

    const image_deflate_module = b.createModule(.{
        .root_source_file = b.path("../src/image/deflate.zig"),
        .target = target,
        .optimize = optimize,
    });

    const image_png_module = b.createModule(.{
        .root_source_file = b.path("../src/image/png.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "deflate", .module = image_deflate_module },
        },
    });

    const allocator_module = b.createModule(.{
        .root_source_file = b.path("../src/utils/allocator.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 创建main模块（Browser类）
    const main_module = b.createModule(.{
        .root_source_file = b.path("../src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "html", .module = html_module },
            .{ .name = "dom", .module = dom_module },
            .{ .name = "allocator", .module = allocator_module },
            .{ .name = "parser", .module = css_parser_module },
            .{ .name = "engine", .module = layout_engine_module },
            .{ .name = "box", .module = layout_box_module },
            .{ .name = "block", .module = layout_block_module },
            .{ .name = "cpu_backend", .module = render_cpu_backend_module },
            .{ .name = "renderer", .module = render_renderer_module },
            .{ .name = "png", .module = image_png_module },
            .{ .name = "cascade", .module = css_cascade_module },
            .{ .name = "backend", .module = render_backend_module },
            .{ .name = "style_utils", .module = layout_style_utils_module },
        },
    });

    // 创建主程序可执行文件
    const exe = b.addExecutable(.{
        .name = "extract_and_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("extract_and_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "html", .module = html_module },
                .{ .name = "dom", .module = dom_module },
                .{ .name = "allocator", .module = allocator_module },
                .{ .name = "parser", .module = css_parser_module },
                .{ .name = "engine", .module = layout_engine_module },
                .{ .name = "box", .module = layout_box_module },
                .{ .name = "block", .module = layout_block_module },
                .{ .name = "cpu_backend", .module = render_cpu_backend_module },
                .{ .name = "renderer", .module = render_renderer_module },
                .{ .name = "png", .module = image_png_module },
                .{ .name = "cascade", .module = css_cascade_module },
                .{ .name = "backend", .module = render_backend_module },
                .{ .name = "style_utils", .module = layout_style_utils_module },
                .{ .name = "main", .module = main_module },
            },
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run extract_and_test");
    run_step.dependOn(&run_cmd.step);
}

