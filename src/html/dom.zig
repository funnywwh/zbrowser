const std = @import("std");
const string = @import("string");

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

    pub fn deinit(self: *ElementData, _: std.mem.Allocator) void {
        // 注意：如果使用Arena分配器，不需要单独释放属性
        // Arena会在销毁时一次性释放所有内存
        // 这里只清理HashMap结构本身
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
        const html_elem = self.getDocumentElement() orelse return null;
        return html_elem.querySelector("head");
    }

    /// 获取body元素
    pub fn getBody(self: *Document) ?*Node {
        const html_elem = self.getDocumentElement() orelse return null;
        return html_elem.querySelector("body");
    }

    /// 查找单个元素（通过标签名）
    ///
    /// 参数:
    ///   - tag_name: 标签名
    ///
    /// 返回:
    ///   - 找到的第一个元素或null
    ///
    /// 示例:
    /// ```zig
    /// const div = doc.querySelector("div");
    /// ```
    pub fn querySelector(self: *Document, tag_name: []const u8) ?*Node {
        return self.node.querySelector(tag_name);
    }

    /// 查找所有匹配的元素（通过标签名）
    ///
    /// 参数:
    ///   - tag_name: 标签名
    ///   - allocator: 内存分配器
    ///
    /// 返回:
    ///   - 匹配的元素数组
    ///
    /// 示例:
    /// ```zig
    /// const divs = try doc.querySelectorAll("div", allocator);
    /// defer allocator.free(divs);
    /// ```
    pub fn querySelectorAll(self: *Document, tag_name: []const u8, allocator: std.mem.Allocator) ![]*Node {
        var results = std.ArrayList(*Node).init(allocator);
        errdefer results.deinit();

        var current = self.node.first_child;
        while (current) |node| {
            if (node.node_type == .element) {
                if (node.asElement()) |elem| {
                    if (std.mem.eql(u8, elem.tag_name, tag_name)) {
                        try results.append(node);
                    }
                }
            }
            // 递归查找子节点
            if (node.first_child) |child| {
                const child_results = try self._querySelectorAllFromNode(child, tag_name, allocator);
                defer allocator.free(child_results);
                try results.appendSlice(child_results);
            }
            current = node.next_sibling;
        }

        return try results.toOwnedSlice();
    }

    /// 通过ID查找元素
    ///
    /// 参数:
    ///   - id: 元素ID
    ///
    /// 返回:
    ///   - 找到的元素或null
    ///
    /// 示例:
    /// ```zig
    /// const elem = doc.getElementById("myId");
    /// ```
    pub fn getElementById(self: *Document, id: []const u8) ?*Node {
        return self._findElementById(&self.node, id);
    }

    /// 通过标签名查找所有元素
    ///
    /// 参数:
    ///   - tag_name: 标签名
    ///   - allocator: 内存分配器
    ///
    /// 返回:
    ///   - 匹配的元素数组
    ///
    /// 示例:
    /// ```zig
    /// const divs = try doc.getElementsByTagName("div", allocator);
    /// defer allocator.free(divs);
    /// ```
    pub fn getElementsByTagName(self: *Document, tag_name: []const u8, allocator: std.mem.Allocator) ![]*Node {
        return self.querySelectorAll(tag_name, allocator);
    }

    /// 通过类名查找所有元素
    ///
    /// 参数:
    ///   - class_name: 类名
    ///   - allocator: 内存分配器
    ///
    /// 返回:
    ///   - 匹配的元素数组
    ///
    /// 示例:
    /// ```zig
    /// const items = try doc.getElementsByClassName("item", allocator);
    /// defer allocator.free(items);
    /// ```
    pub fn getElementsByClassName(self: *Document, class_name: []const u8, allocator: std.mem.Allocator) ![]*Node {
        var results = std.ArrayList(*Node).init(allocator);
        errdefer results.deinit();

        var current = self.node.first_child;
        while (current) |node| {
            if (node.node_type == .element) {
                if (node.asElement()) |elem| {
                    const classes = elem.getClasses(allocator) catch {
                        current = node.next_sibling;
                        continue;
                    };
                    defer allocator.free(classes);

                    for (classes) |cls| {
                        if (std.mem.eql(u8, cls, class_name)) {
                            try results.append(node);
                            break;
                        }
                    }
                }
            }
            // 递归查找子节点
            if (node.first_child) |child| {
                const child_results = try self._getElementsByClassNameFromNode(child, class_name, allocator);
                defer allocator.free(child_results);
                try results.appendSlice(child_results);
            }
            current = node.next_sibling;
        }

        return try results.toOwnedSlice();
    }

    // 内部辅助方法：从指定节点开始递归查找
    fn _querySelectorAllFromNode(self: *Document, node: *Node, tag_name: []const u8, allocator: std.mem.Allocator) ![]*Node {
        var results = std.ArrayList(*Node).init(allocator);
        errdefer results.deinit();

        var current: ?*Node = node;
        while (current) |n| {
            if (n.node_type == .element) {
                if (n.asElement()) |elem| {
                    if (std.mem.eql(u8, elem.tag_name, tag_name)) {
                        try results.append(n);
                    }
                }
            }
            // 递归查找子节点
            if (n.first_child) |child| {
                const child_results = try self._querySelectorAllFromNode(child, tag_name, allocator);
                defer allocator.free(child_results);
                try results.appendSlice(child_results);
            }
            current = n.next_sibling;
        }

        return try results.toOwnedSlice();
    }

    // 内部辅助方法：从指定节点开始递归查找类名
    fn _getElementsByClassNameFromNode(self: *Document, node: *Node, class_name: []const u8, allocator: std.mem.Allocator) ![]*Node {
        var results = std.ArrayList(*Node).init(allocator);
        errdefer results.deinit();

        var current: ?*Node = node;
        while (current) |n| {
            if (n.node_type == .element) {
                if (n.asElement()) |elem| {
                    const classes = elem.getClasses(allocator) catch {
                        current = n.next_sibling;
                        continue;
                    };
                    defer allocator.free(classes);

                    for (classes) |cls| {
                        if (std.mem.eql(u8, cls, class_name)) {
                            try results.append(n);
                            break;
                        }
                    }
                }
            }
            // 递归查找子节点
            if (n.first_child) |child| {
                const child_results = try self._getElementsByClassNameFromNode(child, class_name, allocator);
                defer allocator.free(child_results);
                try results.appendSlice(child_results);
            }
            current = n.next_sibling;
        }

        return try results.toOwnedSlice();
    }

    // 内部辅助方法：通过ID递归查找元素
    fn _findElementById(self: *Document, node: *Node, id: []const u8) ?*Node {
        var current = node.first_child;
        while (current) |n| {
            if (n.node_type == .element) {
                if (n.asElement()) |elem| {
                    if (elem.getId()) |elem_id| {
                        if (std.mem.eql(u8, elem_id, id)) {
                            return n;
                        }
                    }
                }
            }
            // 递归查找子节点
            if (n.first_child) |found| {
                if (self._findElementById(found, id)) |result| {
                    return result;
                }
            }
            current = n.next_sibling;
        }
        return null;
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
        // 注意：如果使用Arena分配器，不需要单独释放
        // 但为了兼容性，我们检查allocator类型
        switch (node.node_type) {
            .element => {
                if (node.asElement()) |elem| {
                    elem.deinit(self.allocator);
                    // 如果不是Arena分配器，需要释放tag_name和attributes
                    // 这里假设使用Arena，所以只清理HashMap结构
                }
            },
            .text, .comment => {
                // 如果是GPA分配器，需要释放文本内容
                // 但为了兼容Arena，这里不释放，由调用者决定
            },
            else => {},
        }

        // 注意：节点本身的内存由分配器管理
        // 如果使用Arena，会在Arena销毁时自动释放
        // 如果使用GPA，需要调用者手动destroy
    }
};
