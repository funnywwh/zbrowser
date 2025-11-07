const std = @import("std");
const string = @import("../utils/string.zig");

/// DOM节点类型
pub const NodeType = enum {
    element,
    text,
    comment,
    document,
    doctype,
};

/// DOM节点
pub const Node = struct {
    node_type: NodeType,
    parent: ?*Node = null,
    first_child: ?*Node = null,
    last_child: ?*Node = null,
    next_sibling: ?*Node = null,
    prev_sibling: ?*Node = null,

    // 节点数据（根据类型使用不同字段）
    data: Data,

    pub const Data = union(NodeType) {
        element: ElementData,
        text: []const u8,
        comment: []const u8,
        document: void,
        doctype: void,
    };

    /// 添加子节点
    pub fn appendChild(self: *Node, child: *Node, _: std.mem.Allocator) !void {
        child.parent = self;

        if (self.last_child) |last| {
            last.next_sibling = child;
            child.prev_sibling = last;
            self.last_child = child;
        } else {
            self.first_child = child;
            self.last_child = child;
        }
    }

    /// 移除子节点
    pub fn removeChild(self: *Node, child: *Node) void {
        if (child.parent != self) return;

        if (child.prev_sibling) |prev| {
            prev.next_sibling = child.next_sibling;
        } else {
            self.first_child = child.next_sibling;
        }

        if (child.next_sibling) |next| {
            next.prev_sibling = child.prev_sibling;
        } else {
            self.last_child = child.prev_sibling;
        }

        child.parent = null;
        child.prev_sibling = null;
        child.next_sibling = null;
    }

    /// 获取元素数据（仅对element类型有效）
    pub fn asElement(self: *Node) ?*ElementData {
        if (self.node_type == .element) {
            return &self.data.element;
        }
        return null;
    }

    /// 获取文本内容（仅对text类型有效）
    pub fn asText(self: *const Node) ?[]const u8 {
        if (self.node_type == .text) {
            return self.data.text;
        }
        return null;
    }

    /// 查找子元素（深度优先）
    pub fn querySelector(self: *Node, tag_name: []const u8) ?*Node {
        var current = self.first_child;
        while (current) |node| {
            if (node.node_type == .element) {
                if (node.asElement()) |elem| {
                    if (std.mem.eql(u8, elem.tag_name, tag_name)) {
                        return node;
                    }
                }
            }
            if (node.first_child) |found| {
                if (found.querySelector(tag_name)) |result| {
                    return result;
                }
            }
            current = node.next_sibling;
        }
        return null;
    }

    /// 获取所有子元素
    pub fn getChildren(self: *Node, allocator: std.mem.Allocator) ![]*Node {
        var children = std.ArrayList(*Node).init(allocator);
        var current = self.first_child;
        while (current) |node| {
            try children.append(node);
            current = node.next_sibling;
        }
        return children.toOwnedSlice();
    }
};

/// 元素数据
pub const ElementData = struct {
    tag_name: []const u8,
    attributes: std.StringHashMap([]const u8),
    namespace: []const u8 = "http://www.w3.org/1999/xhtml",

    pub fn init(allocator: std.mem.Allocator, tag_name: []const u8) ElementData {
        return .{
            .tag_name = tag_name,
            .attributes = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// 获取属性值
    pub fn getAttribute(self: *const ElementData, name: []const u8) ?[]const u8 {
        return self.attributes.get(name);
    }

    /// 设置属性
    pub fn setAttribute(self: *ElementData, name: []const u8, value: []const u8, allocator: std.mem.Allocator) !void {
        const name_owned = try allocator.dupe(u8, name);
        const value_owned = try allocator.dupe(u8, value);
        try self.attributes.put(name_owned, value_owned);
    }

    /// 检查是否有指定属性
    pub fn hasAttribute(self: *const ElementData, name: []const u8) bool {
        return self.attributes.contains(name);
    }

    /// 获取ID属性
    pub fn getId(self: *const ElementData) ?[]const u8 {
        return self.getAttribute("id");
    }

    /// 获取class属性
    pub fn getClasses(self: *const ElementData, allocator: std.mem.Allocator) ![]const []const u8 {
        const class_attr = self.getAttribute("class") orelse return &[_][]const u8{};
        var classes = std.ArrayList([]const u8).init(allocator);

        var iter = std.mem.splitScalar(u8, class_attr, ' ');
        while (iter.next()) |class_name| {
            const trimmed = string.trim(class_name);
            if (trimmed.len > 0) {
                try classes.append(trimmed);
            }
        }

        return classes.toOwnedSlice();
    }

    pub fn deinit(self: *ElementData, allocator: std.mem.Allocator) void {
        var it = self.attributes.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.attributes.deinit();
    }
};

/// 文档节点
pub const Document = struct {
    node: Node,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Document {
        return .{
            .node = .{
                .node_type = .document,
                .data = .{ .document = {} },
            },
            .allocator = allocator,
        };
    }

    /// 获取根元素（html）
    pub fn getDocumentElement(self: *Document) ?*Node {
        return self.node.querySelector("html");
    }

    /// 获取head元素
    pub fn getHead(self: *Document) ?*Node {
        return self.node.querySelector("head");
    }

    /// 获取body元素
    pub fn getBody(self: *Document) ?*Node {
        return self.node.querySelector("body");
    }

    pub fn deinit(self: *Document) void {
        // 递归释放所有节点
        self.freeNode(&self.node);
    }

    fn freeNode(self: *Document, node: *Node) void {
        var current = node.first_child;
        while (current) |child| {
            const next = child.next_sibling;
            self.freeNode(child);
            current = next;
        }

        // 释放节点数据
        switch (node.node_type) {
            .element => {
                if (node.asElement()) |elem| {
                    elem.deinit(self.allocator);
                }
            },
            .text, .comment => {
                if (node.asText()) |text| {
                    self.allocator.free(text);
                }
            },
            else => {},
        }

        self.allocator.destroy(node);
    }
};
