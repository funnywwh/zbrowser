const std = @import("std");
const dom = @import("dom");
const string = @import("string");

/// 简单选择器类型
pub const SimpleSelectorType = enum {
    type,
    class,
    id,
    attribute,
    pseudo_class,
    pseudo_element,
    universal,
};

/// 简单选择器
pub const SimpleSelector = struct {
    selector_type: SimpleSelectorType,
    value: []const u8,
    attribute_name: ?[]const u8 = null,
    attribute_value: ?[]const u8 = null,
    allocator: std.mem.Allocator,

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

/// 组合器类型
pub const Combinator = enum {
    descendant, // 空格
    child, // >
    adjacent, // +
    sibling, // ~
};

/// 选择器序列（一个简单选择器序列，可能包含组合器）
pub const SelectorSequence = struct {
    selectors: std.ArrayList(SimpleSelector),
    combinators: std.ArrayList(Combinator),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SelectorSequence {
        return .{
            .selectors = std.ArrayList(SimpleSelector){},
            .combinators = std.ArrayList(Combinator){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SelectorSequence) void {
        for (self.selectors.items) |*selector| {
            selector.deinit();
        }
        self.selectors.deinit(self.allocator);
        self.combinators.deinit(self.allocator);
    }
};

/// 选择器（包含多个序列，用逗号分隔）
pub const Selector = struct {
    sequences: std.ArrayList(SelectorSequence),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Selector {
        return .{
            .sequences = std.ArrayList(SelectorSequence){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Selector) void {
        for (self.sequences.items) |*sequence| {
            sequence.deinit();
        }
        self.sequences.deinit(self.allocator);
    }
};

/// 特异性
pub const Specificity = struct {
    a: u32 = 0, // 内联样式
    b: u32 = 0, // ID选择器
    c: u32 = 0, // 类、属性、伪类选择器
    d: u32 = 0, // 类型和伪元素选择器

    pub fn compare(self: Specificity, other: Specificity) std.math.Order {
        if (self.a != other.a) return std.math.order(self.a, other.a);
        if (self.b != other.b) return std.math.order(self.b, other.b);
        if (self.c != other.c) return std.math.order(self.c, other.c);
        return std.math.order(self.d, other.d);
    }
};

/// 计算选择器序列的特异性
pub fn calculateSequenceSpecificity(sequence: *const SelectorSequence) Specificity {
    var spec = Specificity{};
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

/// 选择器匹配器
pub const Matcher = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Matcher {
        return .{ .allocator = allocator };
    }

    /// 匹配简单选择器
    pub fn matchesSimpleSelector(self: Matcher, element: *dom.Node, selector: *const SimpleSelector) bool {
        _ = self;
        if (element.node_type != .element) return false;
        const elem = element.asElement() orelse return false;

        switch (selector.selector_type) {
            .type => {
                return std.mem.eql(u8, elem.tag_name, selector.value);
            },
            .class => {
                if (elem.attributes.get("class")) |class_attr| {
                    var iter = std.mem.splitSequence(u8, class_attr, " ");
                    while (iter.next()) |class_name| {
                        // 去除前导和尾随空格
                        const trimmed = std.mem.trim(u8, class_name, " \t\n\r");
                        if (trimmed.len > 0 and std.mem.eql(u8, trimmed, selector.value)) {
                            return true;
                        }
                    }
                }
                return false;
            },
            .id => {
                if (elem.attributes.get("id")) |id_attr| {
                    return std.mem.eql(u8, id_attr, selector.value);
                }
                return false;
            },
            .attribute => {
                // 检查属性选择器
                if (selector.attribute_name) |attr_name| {
                    if (elem.attributes.get(attr_name)) |attr_value| {
                        // 如果有指定值，检查值是否匹配
                        if (selector.attribute_value) |expected_value| {
                            return std.mem.eql(u8, attr_value, expected_value);
                        }
                        // 没有指定值，只要属性存在就匹配
                        return true;
                    }
                } else {
                    // 没有属性名，使用value作为属性名（向后兼容）
                    return elem.attributes.contains(selector.value);
                }
                return false;
            },
            .pseudo_class => {
                const pseudo_value = selector.value;
                if (element.parent) |parent| {
                    if (std.mem.eql(u8, pseudo_value, "first-child")) {
                        return parent.first_child == element;
                    } else if (std.mem.eql(u8, pseudo_value, "last-child")) {
                        return parent.last_child == element;
                    } else if (std.mem.eql(u8, pseudo_value, "only-child")) {
                        return parent.first_child == element and parent.last_child == element;
                    } else if (std.mem.eql(u8, pseudo_value, "empty")) {
                        return element.first_child == null;
                    } else if (std.mem.startsWith(u8, pseudo_value, "nth-child(")) {
                        // 简化实现：只处理nth-child(n)格式，n是数字
                        const start = std.mem.indexOfScalar(u8, pseudo_value, '(') orelse return false;
                        const end = std.mem.indexOfScalar(u8, pseudo_value[start..], ')') orelse return false;
                        const n_str = pseudo_value[start + 1 .. start + end];
                        const n = std.fmt.parseInt(usize, n_str, 10) catch return false;

                        // 计算元素在父节点中的位置
                        var count: usize = 1;
                        var current = parent.first_child;
                        while (current) |child| {
                            if (child == element) {
                                return count == n;
                            }
                            count += 1;
                            current = child.next_sibling;
                        }
                        return false;
                    } else if (std.mem.startsWith(u8, pseudo_value, "nth-of-type(")) {
                        // 简化实现：只处理nth-of-type(n)格式
                        const start = std.mem.indexOfScalar(u8, pseudo_value, '(') orelse return false;
                        const end = std.mem.indexOfScalar(u8, pseudo_value[start..], ')') orelse return false;
                        const n_str = pseudo_value[start + 1 .. start + end];
                        const n = std.fmt.parseInt(usize, n_str, 10) catch return false;

                        // 计算同类型元素在父节点中的位置
                        var count: usize = 1;
                        var current = parent.first_child;
                        while (current) |child| {
                            if (child.node_type == .element) {
                                const child_elem = child.asElement() orelse continue;
                                if (std.mem.eql(u8, child_elem.tag_name, elem.tag_name)) {
                                    if (child == element) {
                                        return count == n;
                                    }
                                    count += 1;
                                }
                            }
                            current = child.next_sibling;
                        }
                        return false;
                    }
                }
                return false;
            },
            .universal => return true,
            else => return false,
        }
    }
};
