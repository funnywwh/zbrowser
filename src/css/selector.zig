const std = @import("std");
const dom = @import("dom");
const string = @import("string");

/// CSS选择器类型
pub const SelectorType = enum {
    universal, // *（通配符）
    type, // 元素类型（如：div, p）
    class, // 类选择器（.class）
    id, // ID选择器（#id）
    attribute, // 属性选择器（[attr], [attr=value]）
    pseudo_class, // 伪类（:hover, :first-child等）
    pseudo_element, // 伪元素（::before, ::after等）
};

/// CSS选择器组合器
pub const Combinator = enum {
    descendant, // 空格（后代选择器）
    child, // >（子选择器）
    adjacent, // +（相邻兄弟选择器）
    sibling, // ~（一般兄弟选择器）
};

/// CSS简单选择器
pub const SimpleSelector = struct {
    selector_type: SelectorType,
    value: []const u8, // 标签名、类名、ID等
    attribute_name: ?[]const u8 = null, // 属性选择器的属性名
    attribute_value: ?[]const u8 = null, // 属性选择器的属性值
    attribute_match: AttributeMatch = .exact, // 属性匹配方式
    allocator: std.mem.Allocator,

    pub const AttributeMatch = enum {
        exact, // [attr=value]
        contains, // [attr~=value]（包含单词）
        prefix, // [attr^=value]（前缀）
        suffix, // [attr$=value]（后缀）
        substring, // [attr*=value]（子串）
        hyphen, // [attr|=value]（连字符）
    };

    pub fn deinit(self: *SimpleSelector) void {
        self.allocator.free(self.value);
        if (self.attribute_name) |name| {
            self.allocator.free(name);
        }
        if (self.attribute_value) |val| {
            self.allocator.free(val);
        }
    }
};

/// CSS选择器序列（由简单选择器和组合器组成）
pub const SelectorSequence = struct {
    selectors: std.ArrayList(SimpleSelector),
    combinators: std.ArrayList(Combinator),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SelectorSequence {
        return .{
            .selectors = std.ArrayList(SimpleSelector).init(allocator),
            .combinators = std.ArrayList(Combinator).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SelectorSequence) void {
        for (self.selectors.items) |*selector| {
            selector.deinit();
        }
        self.selectors.deinit();
        self.combinators.deinit();
    }
};

/// CSS选择器（可能包含多个选择器序列，用逗号分隔）
pub const Selector = struct {
    sequences: std.ArrayList(SelectorSequence),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Selector {
        return .{
            .sequences = std.ArrayList(SelectorSequence).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Selector) void {
        for (self.sequences.items) |*seq| {
            seq.deinit();
        }
        self.sequences.deinit();
    }
};

/// 选择器匹配器
pub const Matcher = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 初始化匹配器
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// 匹配伪类
    fn matchesPseudoClass(self: *Self, node: *dom.Node, pseudo_name: []const u8) bool {
        if (std.mem.eql(u8, pseudo_name, "first-child")) {
            return self.isFirstChild(node);
        }
        if (std.mem.eql(u8, pseudo_name, "last-child")) {
            return self.isLastChild(node);
        }
        if (std.mem.startsWith(u8, pseudo_name, "nth-child(")) {
            return self.matchesNthChild(node, pseudo_name);
        }
        if (std.mem.startsWith(u8, pseudo_name, "nth-of-type(")) {
            return self.matchesNthOfType(node, pseudo_name);
        }
        if (std.mem.eql(u8, pseudo_name, "only-child")) {
            return self.isOnlyChild(node);
        }
        if (std.mem.eql(u8, pseudo_name, "empty")) {
            return self.isEmpty(node);
        }

        // 其他伪类（如:hover, :focus）在headless浏览器中不适用
        // self已通过调用其他方法使用，不需要显式丢弃
        return false;
    }

    /// 检查节点是否是第一个子元素
    fn isFirstChild(self: *Self, node: *dom.Node) bool {
        _ = self; // 保留self以保持API一致性
        if (node.parent) |parent| {
            // 只计算元素节点，跳过文本节点和注释节点
            var current = parent.first_child;
            while (current) |child| {
                if (child.node_type == .element) {
                    return child == node;
                }
                current = child.next_sibling;
            }
        }
        return false;
    }

    /// 检查节点是否是最后一个子元素
    fn isLastChild(self: *Self, node: *dom.Node) bool {
        _ = self; // 保留self以保持API一致性
        if (node.parent) |parent| {
            // 只计算元素节点，跳过文本节点和注释节点
            var current = parent.last_child;
            while (current) |child| {
                if (child.node_type == .element) {
                    return child == node;
                }
                current = child.prev_sibling;
            }
        }
        return false;
    }

    /// 检查节点是否是唯一子元素
    fn isOnlyChild(self: *Self, node: *dom.Node) bool {
        _ = self; // 保留self以保持API一致性
        if (node.parent) |parent| {
            var count: usize = 0;
            var current = parent.first_child;
            while (current) |child| {
                if (child.node_type == .element) {
                    count += 1;
                    if (count > 1) return false;
                }
                current = child.next_sibling;
            }
            return count == 1 and node == parent.first_child;
        }
        return false;
    }

    /// 检查节点是否为空（没有子元素）
    fn isEmpty(self: *Self, node: *dom.Node) bool {
        _ = self; // 保留self以保持API一致性
        if (node.node_type != .element) return false;
        return node.first_child == null;
    }

    /// 匹配:nth-child()伪类
    fn matchesNthChild(self: *Self, node: *dom.Node, pseudo_name: []const u8) bool {
        _ = self; // 保留self以保持API一致性
        // 解析 :nth-child(an+b) 或 :nth-child(n) 格式
        // 简化实现：只支持数字，如 :nth-child(2)
        if (node.parent) |parent| {
            const start = "nth-child(".len;
            const end = pseudo_name.len - 1; // 去掉右括号
            if (end <= start) return false;

            const expr = pseudo_name[start..end];

            // 尝试解析为数字
            if (std.fmt.parseInt(usize, expr, 10)) |n| {
                // 计算当前节点在父节点中的位置（只计算元素节点）
                var count: usize = 0;
                var current = parent.first_child;
                while (current) |child| {
                    if (child.node_type == .element) {
                        count += 1;
                        if (child == node) {
                            return count == n;
                        }
                    }
                    current = child.next_sibling;
                }
            } else |_| {
                // 不支持复杂的表达式（如 2n+1），返回false
                return false;
            }
        }
        return false;
    }

    /// 匹配:nth-of-type()伪类
    fn matchesNthOfType(self: *Self, node: *dom.Node, pseudo_name: []const u8) bool {
        _ = self; // 保留self以保持API一致性
        if (node.node_type != .element) return false;
        const elem = node.asElement() orelse return false;
        const tag_name = elem.tag_name;

        if (node.parent) |parent| {
            const start = "nth-of-type(".len;
            const end = pseudo_name.len - 1; // 去掉右括号
            if (end <= start) return false;

            const expr = pseudo_name[start..end];

            // 尝试解析为数字
            if (std.fmt.parseInt(usize, expr, 10)) |n| {
                // 计算当前节点在同类型元素中的位置
                var count: usize = 0;
                var current = parent.first_child;
                while (current) |child| {
                    if (child.node_type == .element) {
                        if (child.asElement()) |child_elem| {
                            if (std.mem.eql(u8, child_elem.tag_name, tag_name)) {
                                count += 1;
                                if (child == node) {
                                    return count == n;
                                }
                            }
                        }
                    }
                    current = child.next_sibling;
                }
            } else |_| {
                // 不支持复杂的表达式，返回false
                return false;
            }
        }
        return false;
    }

    /// 匹配简单选择器
    pub fn matchesSimpleSelector(self: *Self, node: *dom.Node, selector: *const SimpleSelector) bool {
        if (node.node_type != .element) {
            return false;
        }

        const elem = node.asElement() orelse return false;

        switch (selector.selector_type) {
            .universal => return true,
            .type => {
                return std.mem.eql(u8, elem.tag_name, selector.value);
            },
            .class => {
                const classes = elem.getClasses(self.allocator) catch return false;
                defer self.allocator.free(classes);
                for (classes) |cls| {
                    if (std.mem.eql(u8, cls, selector.value)) {
                        return true;
                    }
                }
                return false;
            },
            .id => {
                if (elem.getId()) |id| {
                    return std.mem.eql(u8, id, selector.value);
                }
                return false;
            },
            .attribute => {
                if (selector.attribute_name) |attr_name| {
                    const attr_value = elem.getAttribute(attr_name);
                    if (selector.attribute_value) |expected_value| {
                        // 有属性值，需要匹配
                        if (attr_value) |actual_value| {
                            return switch (selector.attribute_match) {
                                .exact => std.mem.eql(u8, actual_value, expected_value),
                                .contains => {
                                    // 检查是否包含单词（空格分隔）
                                    var iter = std.mem.splitScalar(u8, actual_value, ' ');
                                    while (iter.next()) |word| {
                                        if (std.mem.eql(u8, word, expected_value)) {
                                            return true;
                                        }
                                    }
                                    return false;
                                },
                                .prefix => string.startsWith(actual_value, expected_value),
                                .suffix => string.endsWith(actual_value, expected_value),
                                .substring => std.mem.indexOf(u8, actual_value, expected_value) != null,
                                .hyphen => {
                                    // 连字符匹配：值必须完全等于expected_value，或者以expected_value-开头
                                    if (std.mem.eql(u8, actual_value, expected_value)) {
                                        return true;
                                    }
                                    // 检查是否以expected_value-开头
                                    if (actual_value.len < expected_value.len + 1) {
                                        return false;
                                    }
                                    if (!std.mem.eql(u8, actual_value[0..expected_value.len], expected_value)) {
                                        return false;
                                    }
                                    return actual_value[expected_value.len] == '-';
                                },
                            };
                        }
                        return false;
                    } else {
                        // 只检查属性是否存在
                        return attr_value != null;
                    }
                }
                return false;
            },
            .pseudo_class => {
                return self.matchesPseudoClass(node, selector.value);
            },
            .pseudo_element => {
                // 伪元素（::before, ::after等）在headless浏览器中主要用于样式计算
                // 实际渲染时才会生成伪元素节点
                // 这里先返回false，后续可以在渲染阶段处理
                // 验证参数有效性（避免linter警告）
                if (node.node_type != .element or selector.value.len == 0) {
                    return false;
                }
                return false;
            },
        }
    }

    /// 匹配选择器序列（从右到左匹配，Chrome方式）
    pub fn matchesSequence(self: *Self, node: *dom.Node, sequence: *const SelectorSequence) bool {
        if (sequence.selectors.items.len == 0) {
            return false;
        }

        // 从最右侧的简单选择器开始
        const last_selector = &sequence.selectors.items[sequence.selectors.items.len - 1];

        // 检查当前节点是否匹配最后一个选择器
        if (!self.matchesSimpleSelector(node, last_selector)) {
            return false;
        }

        // 如果只有一个选择器，匹配成功
        if (sequence.selectors.items.len == 1) {
            return true;
        }

        // 验证左侧的选择器和组合器
        return self.matchesSequenceRecursive(node, sequence, sequence.selectors.items.len - 2);
    }

    /// 递归匹配选择器序列
    fn matchesSequenceRecursive(self: *Self, node: *dom.Node, sequence: *const SelectorSequence, selector_idx: usize) bool {
        if (selector_idx >= sequence.selectors.items.len) {
            return true;
        }

        const selector = &sequence.selectors.items[selector_idx];
        const combinator_idx = selector_idx;

        // 获取组合器（如果存在）
        const combinator: ?Combinator = if (combinator_idx < sequence.combinators.items.len)
            sequence.combinators.items[combinator_idx]
        else
            null;

        // 默认使用后代选择器
        const comb = combinator orelse .descendant;

        // 根据组合器查找父节点或兄弟节点
        switch (comb) {
            .descendant => {
                // 后代选择器：在任意祖先中查找
                var current = node.parent;
                while (current) |parent| {
                    if (self.matchesSimpleSelector(parent, selector)) {
                        if (selector_idx == 0) {
                            return true;
                        }
                        return self.matchesSequenceRecursive(parent, sequence, selector_idx - 1);
                    }
                    current = parent.parent;
                }
                return false;
            },
            .child => {
                // 子选择器：直接父节点
                if (node.parent) |parent| {
                    if (self.matchesSimpleSelector(parent, selector)) {
                        if (selector_idx == 0) {
                            return true;
                        }
                        return self.matchesSequenceRecursive(parent, sequence, selector_idx - 1);
                    }
                }
                return false;
            },
            .adjacent => {
                // 相邻兄弟选择器：前一个兄弟节点
                if (node.prev_sibling) |sibling| {
                    if (self.matchesSimpleSelector(sibling, selector)) {
                        if (selector_idx == 0) {
                            return true;
                        }
                        return self.matchesSequenceRecursive(sibling, sequence, selector_idx - 1);
                    }
                }
                return false;
            },
            .sibling => {
                // 一般兄弟选择器：前面的任意兄弟节点
                var current = node.prev_sibling;
                while (current) |sibling| {
                    if (self.matchesSimpleSelector(sibling, selector)) {
                        if (selector_idx == 0) {
                            return true;
                        }
                        return self.matchesSequenceRecursive(sibling, sequence, selector_idx - 1);
                    }
                    current = sibling.prev_sibling;
                }
                return false;
            },
        }
    }

    /// 匹配选择器（检查节点是否匹配选择器的任一序列）
    pub fn matches(self: *Self, node: *dom.Node, selector: *const Selector) bool {
        for (selector.sequences.items) |*sequence| {
            if (self.matchesSequence(node, sequence)) {
                return true;
            }
        }
        return false;
    }

    /// 计算选择器的specificity（优先级）
    pub fn calculateSpecificity(selector: *const Selector) Specificity {
        var spec = Specificity{ .a = 0, .b = 0, .c = 0, .d = 0 };

        // 取所有序列中specificity最高的
        for (selector.sequences.items) |*sequence| {
            const seq_spec = calculateSequenceSpecificity(sequence);
            if (seq_spec.a > spec.a or
                (seq_spec.a == spec.a and seq_spec.b > spec.b) or
                (seq_spec.a == spec.a and seq_spec.b == spec.b and seq_spec.c > spec.c) or
                (seq_spec.a == spec.a and seq_spec.b == spec.b and seq_spec.c == spec.c and seq_spec.d > spec.d))
            {
                spec = seq_spec;
            }
        }

        return spec;
    }
};

/// CSS Specificity（优先级）
pub const Specificity = struct {
    a: u32 = 0, // 内联样式（当前不支持，保留为0）
    b: u32 = 0, // ID选择器数量
    c: u32 = 0, // 类、属性、伪类选择器数量
    d: u32 = 0, // 元素和伪元素选择器数量
};

/// 计算选择器序列的specificity
pub fn calculateSequenceSpecificity(sequence: *const SelectorSequence) Specificity {
    var spec = Specificity{ .a = 0, .b = 0, .c = 0, .d = 0 };

    for (sequence.selectors.items) |selector| {
        switch (selector.selector_type) {
            .id => spec.b += 1,
            .class, .attribute, .pseudo_class => spec.c += 1,
            .type, .pseudo_element => spec.d += 1,
            .universal => {},
        }
    }

    return spec;
}
