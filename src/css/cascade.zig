const std = @import("std");
const dom = @import("dom");
const parser = @import("parser");
const selector = @import("selector");

/// 计算后的样式
pub const ComputedStyle = struct {
    properties: std.StringHashMap(parser.Declaration),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ComputedStyle {
        return .{
            .properties = std.StringHashMap(parser.Declaration).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ComputedStyle) void {
        var it = self.properties.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.properties.deinit();
    }

    pub fn getProperty(self: *const ComputedStyle, name: []const u8) ?*const parser.Declaration {
        return self.properties.getPtr(name);
    }
};

/// CSS层叠引擎
pub const Cascade = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Cascade {
        return .{ .allocator = allocator };
    }

    /// 计算元素的样式
    pub fn computeStyle(self: Cascade, element: *dom.Node, stylesheets: []const parser.Stylesheet) !ComputedStyle {
        var computed = ComputedStyle.init(self.allocator);
        errdefer computed.deinit();

        if (element.node_type != .element) {
            return computed;
        }

        // 遍历所有样式表
        for (stylesheets) |stylesheet| {
            // 遍历所有规则
            for (stylesheet.rules.items) |rule| {
                // 检查选择器是否匹配
                for (rule.selectors.items) |sel| {
                    if (self.matchesSelector(element, &sel)) {
                        // 匹配，添加声明
                        for (rule.declarations.items) |decl| {
                            const name = try self.allocator.dupe(u8, decl.name);
                            errdefer self.allocator.free(name);
                            
                            // 复制值
                            var value = try self.copyValue(decl.value);
                            errdefer value.deinit(self.allocator);
                            
                            const new_decl = parser.Declaration{
                                .name = name,
                                .value = value,
                                .important = decl.important,
                                .allocator = self.allocator,
                            };
                            
                            // 如果已存在，根据优先级决定是否覆盖
                            if (computed.properties.getPtr(decl.name)) |existing| {
                                // 简化：如果新声明是important，覆盖；否则不覆盖
                                if (decl.important and !existing.important) {
                                    existing.deinit();
                                    existing.* = new_decl;
                                }
                            } else {
                                try computed.properties.put(name, new_decl);
                            }
                        }
                        break; // 一个选择器匹配就够了
                    }
                }
            }
        }

        return computed;
    }

    fn matchesSelector(self: Cascade, element: *dom.Node, sel: *const selector.Selector) bool {
        // 简化实现：只检查第一个序列
        if (sel.sequences.items.len == 0) return false;
        
        const seq = &sel.sequences.items[0];
        if (seq.selectors.items.len == 0) return false;

        // 检查所有简单选择器是否都匹配
        for (seq.selectors.items) |simple_sel| {
            var matcher = selector.Matcher.init(self.allocator);
            if (!matcher.matchesSimpleSelector(element, &simple_sel)) {
                return false;
            }
        }

        return true;
    }

    fn copyValue(self: Cascade, value: parser.Value) !parser.Value {
        return switch (value) {
            .keyword => |k| parser.Value{
                .keyword = try self.allocator.dupe(u8, k),
            },
            .length => |l| parser.Value{
                .length = .{
                    .value = l.value,
                    .unit = try self.allocator.dupe(u8, l.unit),
                },
            },
            .percentage => |p| parser.Value{ .percentage = p },
            .color => |c| parser.Value{ .color = c },
        };
    }
};
