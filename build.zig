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

    const exe = b.addExecutable(.{
        .name = "zbrowser",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "html", .module = html_module_exe },
                .{ .name = "dom", .module = dom_module_exe },
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

    // 创建工具模块
    const string_module = b.createModule(.{
        .root_source_file = b.path("src/utils/string.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 创建依赖模块
    const dom_module = b.createModule(.{
        .root_source_file = b.path("src/html/dom.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "string", .module = string_module },
        },
    });

    const tokenizer_module = b.createModule(.{
        .root_source_file = b.path("src/html/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "string", .module = string_module },
        },
    });

    // html模块依赖dom和tokenizer
    const html_module = b.createModule(.{
        .root_source_file = b.path("src/html/parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module },
            .{ .name = "tokenizer", .module = tokenizer_module },
            .{ .name = "string", .module = string_module },
        },
    });

    // 测试模块导入所有需要的模块
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/test/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "html", .module = html_module },
            .{ .name = "dom", .module = dom_module },
            .{ .name = "tokenizer", .module = tokenizer_module },
        },
    });

    // CSS模块
    const css_tokenizer_module = b.createModule(.{
        .root_source_file = b.path("src/css/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "string", .module = string_module },
        },
    });

    const css_module = b.createModule(.{
        .root_source_file = b.path("src/css/parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "tokenizer", .module = css_tokenizer_module },
        },
    });

    // 测试文件模块
    const parser_test_module = b.createModule(.{
        .root_source_file = b.path("tests/html/parser_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "html", .module = html_module },
            .{ .name = "dom", .module = dom_module },
        },
    });

    const css_parser_test_module = b.createModule(.{
        .root_source_file = b.path("tests/css/parser_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "css", .module = css_module },
        },
    });

    const css_selector_module = b.createModule(.{
        .root_source_file = b.path("src/css/selector.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module },
            .{ .name = "string", .module = string_module },
        },
    });

    const css_parser_module_for_cascade = b.createModule(.{
        .root_source_file = b.path("src/css/parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "tokenizer", .module = css_tokenizer_module },
        },
    });

    const css_cascade_module = b.createModule(.{
        .root_source_file = b.path("src/css/cascade.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dom", .module = dom_module },
            .{ .name = "parser", .module = css_parser_module_for_cascade },
            .{ .name = "selector", .module = css_selector_module },
        },
    });

    const css_cascade_test_module = b.createModule(.{
        .root_source_file = b.path("tests/css/cascade_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cascade", .module = css_cascade_module },
            .{ .name = "dom", .module = dom_module },
            .{ .name = "html", .module = html_module },
            .{ .name = "css", .module = css_parser_module_for_cascade },
        },
    });

    const css_selector_test_module = b.createModule(.{
        .root_source_file = b.path("tests/css/selector_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "selector", .module = css_selector_module },
            .{ .name = "dom", .module = dom_module },
            .{ .name = "html", .module = html_module },
        },
    });

    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });

    const parser_tests = b.addTest(.{
        .root_module = parser_test_module,
    });

    const css_parser_tests = b.addTest(.{
        .root_module = css_parser_test_module,
    });

    const css_selector_tests = b.addTest(.{
        .root_module = css_selector_test_module,
    });

    const css_cascade_tests = b.addTest(.{
        .root_module = css_cascade_test_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const run_parser_tests = b.addRunArtifact(parser_tests);
    const run_css_parser_tests = b.addRunArtifact(css_parser_tests);
    const run_css_selector_tests = b.addRunArtifact(css_selector_tests);
    const run_css_cascade_tests = b.addRunArtifact(css_cascade_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_parser_tests.step);
    test_step.dependOn(&run_css_parser_tests.step);
    test_step.dependOn(&run_css_selector_tests.step);
    test_step.dependOn(&run_css_cascade_tests.step);
}
