const std = @import("std");
const dom = @import("dom");

/// 测试辅助函数模块
/// 提供通用的测试工具函数，减少重复代码
/// 释放所有DOM节点的辅助函数
pub fn freeAllNodes(allocator: std.mem.Allocator, node: *dom.Node) void {
    var current = node.first_child;
    while (current) |child| {
        const next = child.next_sibling;
        freeAllNodes(allocator, child);
        freeNode(allocator, child);
        current = next;
    }
    node.first_child = null;
    node.last_child = null;
}

/// 释放单个节点的辅助函数
pub fn freeNode(allocator: std.mem.Allocator, node: *dom.Node) void {
    std.debug.assert(node.first_child == null);
    std.debug.assert(node.last_child == null);

    switch (node.node_type) {
        .element => {
            if (node.asElement()) |elem| {
                allocator.free(elem.tag_name);
                var it = elem.attributes.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    allocator.free(entry.value_ptr.*);
                }
                elem.attributes.deinit();
            }
        },
        .text => {
            if (node.asText()) |text| {
                allocator.free(text);
            }
        },
        .comment => {
            if (node.node_type == .comment) {
                allocator.free(node.data.comment);
            }
        },
        .document => return,
        else => {},
    }

    if (node.node_type != .document) {
        allocator.destroy(node);
    }
}

/// 创建测试用的Document
pub fn createTestDocument(allocator: std.mem.Allocator) !*dom.Document {
    const doc = try dom.Document.init(allocator);
    const doc_ptr = try allocator.create(dom.Document);
    doc_ptr.* = doc;
    return doc_ptr;
}

/// 清理测试用的Document
pub fn cleanupTestDocument(allocator: std.mem.Allocator, doc_ptr: *dom.Document) void {
    freeAllNodes(allocator, &doc_ptr.node);
    doc_ptr.node.first_child = null;
    doc_ptr.node.last_child = null;
    allocator.destroy(doc_ptr);
}

/// 创建测试用的元素节点
pub fn createTestElement(allocator: std.mem.Allocator, tag_name: []const u8) !*dom.Node {
    // ElementData.init 会复制 tag_name，所以直接传入 tag_name
    const node = try allocator.create(dom.Node);
    node.* = .{
        .node_type = .element,
        .data = .{
            .element = try dom.ElementData.init(allocator, tag_name),
        },
    };
    return node;
}

/// 创建测试用的文本节点
pub fn createTestTextNode(allocator: std.mem.Allocator, text: []const u8) !*dom.Node {
    const text_owned = try allocator.dupe(u8, text);
    const node = try allocator.create(dom.Node);
    node.* = .{
        .node_type = .text,
        .data = .{ .text = text_owned },
    };
    return node;
}

/// 测试配置
pub const TestConfig = struct {
    /// 是否启用详细输出
    verbose: bool = false,
    /// 是否检查内存泄漏
    check_memory_leaks: bool = true,
};

/// 全局测试配置
pub var test_config: TestConfig = .{};

/// 设置测试配置
pub fn setTestConfig(config: TestConfig) void {
    test_config = config;
}

/// 打印测试信息（如果启用详细输出）
pub fn testPrint(comptime format: []const u8, args: anytype) void {
    _ = format;
    _ = args;
    // 已禁用详细输出
}
