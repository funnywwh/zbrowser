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

    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });

    const parser_tests = b.addTest(.{
        .root_module = parser_test_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const run_parser_tests = b.addRunArtifact(parser_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_parser_tests.step);
}
