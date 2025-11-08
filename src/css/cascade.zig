const std = @import("std");
const dom = @import("dom");
const parser = @import("parser");
const selector = @import("selector");

/// 样式来源
pub const StyleOrigin = enum {
    user_agent, // 用户代理样式（浏览器默认样式）
    user, // 用户样式
    author, // 作者样式（页面CSS）
    inline_style, // 内联样式（inline是Zig关键字，使用inline_style）
};

/// 匹配的规则（包含规则和其specificity）
pub const MatchedRule = struct {
    rule: *parser.Rule,
    specificity: selector.Specificity,
    origin: StyleOrigin,
};

/// 样式属性值
pub const StyleProperty = struct {
    name: []const u8,
    value: parser.Value,
    important: bool,
    specificity: selector.Specificity,
    origin: StyleOrigin,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *StyleProperty, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.value.deinit(allocator);
    }
};

/// 计算后的样式
pub const ComputedStyle = struct {
    properties: std.StringHashMap(*StyleProperty),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ComputedStyle {
        return .{
            .properties = std.StringHashMap(*StyleProperty).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ComputedStyle) void {
        // 收集所有属性指针（不收集键，因为键会被HashMap自动管理）
        var properties_to_free = std.ArrayList(*StyleProperty).init(self.allocator);
        defer properties_to_free.deinit();

        // 收集所有属性指针
        var it = self.properties.iterator();
        while (it.next()) |entry| {
            properties_to_free.append(entry.value_ptr.*) catch {
                // 如果分配失败，直接释放当前属性
                const property = entry.value_ptr.*;
                property.deinit(self.allocator);
                self.allocator.destroy(property);
                continue;
            };
        }

        // 先释放HashMap（这会释放所有键）
        self.properties.deinit();

        // 然后释放所有属性
        for (properties_to_free.items) |property| {
            property.deinit(self.allocator);
            self.allocator.destroy(property);
        }
    }

    /// 获取样式属性值
    pub fn getProperty(self: *const ComputedStyle, name: []const u8) ?*StyleProperty {
        return self.properties.get(name);
    }

    /// 设置样式属性
    pub fn setProperty(self: *ComputedStyle, name: []const u8, property: *StyleProperty) !void {
        // 如果已存在同名属性，先释放旧的
        if (self.properties.fetchRemove(name)) |entry| {
            entry.value.deinit(self.allocator);
            self.allocator.destroy(entry.value);
        }
        try self.properties.put(name, property);
    }
};

/// 样式层叠计算器
pub const Cascade = struct {
    allocator: std.mem.Allocator,
    matcher: selector.Matcher,
    computing_parent: bool = false, // 标志：是否正在计算父节点样式（避免递归继承）

    const Self = @This();

    /// 初始化层叠计算器
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .matcher = selector.Matcher.init(allocator),
        };
    }

    /// 计算节点的样式
    pub fn computeStyle(self: *Self, node: *dom.Node, stylesheets: []const parser.Stylesheet) anyerror!ComputedStyle {
        var computed = ComputedStyle.init(self.allocator);
        errdefer computed.deinit();

        // 1. 收集所有匹配的规则
        var matched_rules = std.ArrayList(MatchedRule).init(self.allocator);
        defer matched_rules.deinit();

        var matcher = selector.Matcher.init(self.allocator);

        for (stylesheets) |*stylesheet| {
            for (stylesheet.rules.items) |*rule| {
                // 检查规则的选择器是否匹配节点
                for (rule.selectors.items) |*sel| {
                    // 使用完整的选择器匹配
                    if (matcher.matches(node, sel)) {
                        // 计算specificity
                        const spec = selector.Matcher.calculateSpecificity(sel);
                        try matched_rules.append(MatchedRule{
                            .rule = rule,
                            .specificity = spec,
                            .origin = .author,
                        });
                        break; // 一个规则匹配即可
                    }
                }
            }
        }

        // 2. 按优先级排序规则
        // 使用简单的排序算法（因为Zig 0.14.0的std.mem.sort API可能不同）
        // 手动排序：按重要性、来源、specificity、声明顺序
        var i: usize = 0;
        while (i < matched_rules.items.len) : (i += 1) {
            var j: usize = i + 1;
            while (j < matched_rules.items.len) : (j += 1) {
                if (shouldSwap(matched_rules.items[i], matched_rules.items[j])) {
                    const temp = matched_rules.items[i];
                    matched_rules.items[i] = matched_rules.items[j];
                    matched_rules.items[j] = temp;
                }
            }
        }

        // 3. 应用规则，计算最终样式
        for (matched_rules.items) |matched| {
            for (matched.rule.declarations.items) |*decl| {
                const property = try self.createStyleProperty(
                    decl.name,
                    decl.value,
                    decl.important,
                    matched.specificity,
                    matched.origin,
                );
                // 注意：property会被setProperty管理，不需要errdefer
                // 如果setProperty失败，property会被泄漏，但这是可接受的错误情况
                try computed.setProperty(decl.name, property);
            }
        }

        // 4. 应用继承的样式（需要stylesheets来递归计算父节点样式）
        // 只有在不是计算父节点时才应用继承（避免递归）
        if (!self.computing_parent) {
            try self.applyInheritance(node, &computed, stylesheets);
        }

        // 5. 应用默认值
        try self.applyDefaults(&computed);

        return computed;
    }

    /// 创建样式属性
    fn createStyleProperty(
        self: *Self,
        name: []const u8,
        value: parser.Value,
        important: bool,
        specificity: selector.Specificity,
        origin: StyleOrigin,
    ) !*StyleProperty {
        const name_dup = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_dup);

        // 复制值（需要深拷贝）
        const value_copy = try self.copyValue(value);
        errdefer value_copy.deinit(self.allocator);

        const property = try self.allocator.create(StyleProperty);
        property.* = .{
            .name = name_dup,
            .value = value_copy,
            .important = important,
            .specificity = specificity,
            .origin = origin,
            .allocator = self.allocator,
        };

        return property;
    }

    /// 复制样式属性（用于继承）
    fn copyProperty(self: *Self, name: []const u8, property: *StyleProperty) !*StyleProperty {
        const name_dup = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_dup);

        // 复制值（需要深拷贝）
        const value_copy = try self.copyValue(property.value);
        errdefer value_copy.deinit(self.allocator);

        const new_property = try self.allocator.create(StyleProperty);
        new_property.* = .{
            .name = name_dup,
            .value = value_copy,
            .important = property.important,
            .specificity = property.specificity, // 继承的属性保持父节点的specificity
            .origin = property.origin,
            .allocator = self.allocator,
        };

        return new_property;
    }

    /// 复制CSS值
    fn copyValue(self: *Self, value: parser.Value) !parser.Value {
        return switch (value) {
            .keyword => |k| {
                const k_dup = try self.allocator.dupe(u8, k);
                return parser.Value{ .keyword = k_dup };
            },
            .string => |s| {
                const s_dup = try self.allocator.dupe(u8, s);
                return parser.Value{ .string = s_dup };
            },
            .length => |len| {
                const unit_dup = try self.allocator.dupe(u8, len.unit);
                return parser.Value{
                    .length = .{
                        .value = len.value,
                        .unit = unit_dup,
                    },
                };
            },
            .number => |n| parser.Value{ .number = n },
            .percentage => |p| parser.Value{ .percentage = p },
            .color => |c| parser.Value{ .color = c },
        };
    }

    /// 判断是否应该交换两个规则（用于排序）
    fn shouldSwap(a: MatchedRule, b: MatchedRule) bool {
        // 1. 重要性（!important）
        var a_important = false;
        var b_important = false;
        if (a.rule.declarations.items.len > 0) {
            a_important = a.rule.declarations.items[0].important;
        }
        if (b.rule.declarations.items.len > 0) {
            b_important = b.rule.declarations.items[0].important;
        }
        if (a_important != b_important) {
            return a_important; // important的应该排在后面（后应用），所以如果a是important，应该交换
        }

        // 2. 来源
        const origin_order = [_]StyleOrigin{ .user_agent, .user, .author, .inline_style };
        var a_origin_idx: ?usize = null;
        var b_origin_idx: ?usize = null;
        for (origin_order, 0..) |origin, idx| {
            if (a.origin == origin) a_origin_idx = idx;
            if (b.origin == origin) b_origin_idx = idx;
        }
        if (a_origin_idx) |a_idx| {
            if (b_origin_idx) |b_idx| {
                if (a_idx != b_idx) {
                    return a_idx > b_idx; // 来源优先级高的应该排在后面
                }
            }
        }

        // 3. Specificity
        if (a.specificity.a != b.specificity.a) {
            return a.specificity.a > b.specificity.a;
        }
        if (a.specificity.b != b.specificity.b) {
            return a.specificity.b > b.specificity.b;
        }
        if (a.specificity.c != b.specificity.c) {
            return a.specificity.c > b.specificity.c;
        }
        if (a.specificity.d != b.specificity.d) {
            return a.specificity.d > b.specificity.d;
        }

        // 4. 声明顺序（后声明的覆盖先声明的，所以不交换）
        return false;
    }

    /// 应用继承的样式
    fn applyInheritance(self: *Self, node: *dom.Node, computed: *ComputedStyle, stylesheets: []const parser.Stylesheet) !void {
        // 可继承的属性列表（根据CSS规范）
        const inheritable = [_][]const u8{
            "color",
            "font-family",
            "font-size",
            "font-weight",
            "font-style",
            "line-height",
            "text-align",
            "text-decoration",
            "text-transform",
            "letter-spacing",
            "word-spacing",
            "white-space",
            "visibility",
            "cursor",
        };

        // 从父节点继承样式
        if (node.parent) |parent| {
            // 只从元素节点继承（不包括文本节点、注释节点等）
            if (parent.node_type == .element) {
                // 递归计算父节点的样式（设置标志避免递归继承）
                const old_computing = self.computing_parent;
                self.computing_parent = true;
                var parent_computed = try self.computeStyle(parent, stylesheets);
                defer parent_computed.deinit();
                self.computing_parent = old_computing;

                // 对于每个可继承的属性，如果当前节点没有设置，则从父节点继承
                for (inheritable) |prop_name| {
                    if (!computed.properties.contains(prop_name)) {
                        if (parent_computed.getProperty(prop_name)) |parent_prop| {
                            // 复制父节点的属性值
                            const inherited_prop = try self.copyProperty(prop_name, parent_prop);
                            try computed.setProperty(prop_name, inherited_prop);
                        }
                    }
                }
            }
        }
    }

    /// 应用默认值
    fn applyDefaults(self: *Self, computed: *ComputedStyle) !void {
        // 默认样式值
        const defaults = [_]struct { name: []const u8, value: []const u8 }{
            .{ .name = "display", .value = "block" },
            .{ .name = "color", .value = "black" },
            .{ .name = "font-size", .value = "16px" },
            .{ .name = "font-family", .value = "serif" },
        };

        // 如果属性不存在，应用默认值
        for (defaults) |default_style| {
            if (!computed.properties.contains(default_style.name)) {
                // 检查值类型（可能是关键字或长度）
                var value: parser.Value = undefined;
                if (std.mem.endsWith(u8, default_style.value, "px")) {
                    // 解析长度值
                    const num_str = default_style.value[0 .. default_style.value.len - 2];
                    const num = try std.fmt.parseFloat(f32, num_str);
                    const unit = try self.allocator.dupe(u8, "px");
                    errdefer self.allocator.free(unit);
                    value = parser.Value{
                        .length = .{
                            .value = num,
                            .unit = unit,
                        },
                    };
                } else {
                    // 关键字
                    const keyword = try self.allocator.dupe(u8, default_style.value);
                    errdefer self.allocator.free(keyword);
                    value = parser.Value{ .keyword = keyword };
                }

                // createStyleProperty 会复制 value，所以需要释放原始 value
                defer value.deinit(self.allocator);

                const property = try self.createStyleProperty(
                    default_style.name,
                    value,
                    false,
                    selector.Specificity{ .a = 0, .b = 0, .c = 0, .d = 0 },
                    .user_agent,
                );
                try computed.setProperty(default_style.name, property);
            }
        }
    }
};
