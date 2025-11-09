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
            // 释放 key（HashMap 的 key）
            self.allocator.free(entry.key_ptr.*);
            // 释放 value（Declaration），但不要释放 Declaration.name（因为它是 key）
            // 使用 deinitValueOnly 只释放 value
            entry.value_ptr.deinitValueOnly();
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

        // 添加默认样式
        const default_display_name = try self.allocator.dupe(u8, "display");
        const default_display_value = try self.allocator.dupe(u8, "block");
        const default_decl = parser.Declaration{
            .name = default_display_name,
            .value = parser.Value{ .keyword = default_display_value },
            .important = false,
            .allocator = self.allocator,
        };
        // put 后，key 的所有权转移给 HashMap，不需要单独释放
        try computed.properties.put(default_display_name, default_decl);

        // 遍历所有样式表
        for (stylesheets) |stylesheet| {
            // 遍历所有规则
            for (stylesheet.rules.items) |rule| {
                // 检查选择器是否匹配
                for (rule.selectors.items) |sel| {
                    if (self.matchesSelector(element, &sel)) {
                        // 匹配，添加声明
                        for (rule.declarations.items) |decl| {
                            // 检查 decl.name 是否有效（防止使用已释放的内存）
                            if (decl.name.len == 0) continue;
                            const name = try self.allocator.dupe(u8, decl.name);

                            // 复制值
                            const value = try self.copyValue(decl.value);

                            const new_decl = parser.Declaration{
                                .name = name,
                                .value = value,
                                .important = decl.important,
                                .allocator = self.allocator,
                            };

                            // 如果已存在，根据优先级决定是否覆盖
                            // 注意：使用复制的 name 作为 key，而不是 decl.name（可能已被释放）
                            if (computed.properties.getPtr(name)) |existing| {
                                // 简化：如果新声明是important，覆盖；否则不覆盖
                                if (decl.important and !existing.important) {
                                    existing.deinit();
                                    existing.* = new_decl;
                                } else {
                                    // 不覆盖，释放新声明的资源
                                    self.allocator.free(name);
                                    var mutable_value = value;
                                    mutable_value.deinit(self.allocator);
                                }
                            } else {
                                // put 失败时会清理
                                computed.properties.put(name, new_decl) catch |err| {
                                    self.allocator.free(name);
                                    var mutable_value = value;
                                    mutable_value.deinit(self.allocator);
                                    return err;
                                };
                            }
                        }
                        break; // 一个选择器匹配就够了
                    }
                }
            }
        }

        // 处理内联样式（style属性）- 内联样式优先级最高
        const elem = element.asElement() orelse return computed;
        if (elem.attributes.get("style")) |style_attr| {
            // 解析内联样式（格式：property: value; property: value; ...）
            var declarations = try self.parseInlineStyle(style_attr);
            defer {
                // 注意：declarations 中的 Declaration 的 name 和 value 会被 deinit 释放
                // 但我们已经复制了它们到 computed.properties 中，所以这里释放是安全的
                for (declarations.items) |*decl| {
                    decl.deinit();
                }
                declarations.deinit(self.allocator);
            }

            // 应用内联样式（覆盖之前的样式）
            for (declarations.items) |decl| {
                // 复制 name 和 value（因为 decl 会在 defer 中被释放）
                const name = try self.allocator.dupe(u8, decl.name);
                errdefer self.allocator.free(name);

                const value = try self.copyValue(decl.value);
                errdefer {
                    var mutable_value = value;
                    mutable_value.deinit(self.allocator);
                }

                const new_decl = parser.Declaration{
                    .name = name,
                    .value = value,
                    .important = false, // 内联样式不支持important
                    .allocator = self.allocator,
                };

                // 内联样式总是覆盖之前的样式
                // 注意：使用复制的 name 作为 key，而不是 decl.name（可能已被释放）
                if (computed.properties.fetchRemove(name)) |entry| {
                    // 属性已存在，先释放旧的
                    self.allocator.free(entry.key); // 释放旧的 key
                    var old_value = entry.value;
                    old_value.deinitValueOnly(); // 只释放value，name已经释放
                    // 添加新的属性
                    computed.properties.put(name, new_decl) catch |err| {
                        self.allocator.free(name);
                        var mutable_value = value;
                        mutable_value.deinit(self.allocator);
                        return err;
                    };
                    std.log.debug("[Cascade] computeStyle: inline style '{s}' overwrote existing property", .{name});
                } else {
                    computed.properties.put(name, new_decl) catch |err| {
                        self.allocator.free(name);
                        var mutable_value = value;
                        mutable_value.deinit(self.allocator);
                        return err;
                    };
                    std.log.debug("[Cascade] computeStyle: inline style '{s}' added to computed properties", .{name});
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

    /// 解析内联样式（style属性）
    /// 格式：property: value; property: value; ...
    /// 简化实现：手动解析，不依赖CSS解析器的内部方法
    fn parseInlineStyle(self: Cascade, style_attr: []const u8) !std.ArrayList(parser.Declaration) {
        var declarations = std.ArrayList(parser.Declaration){};
        errdefer {
            for (declarations.items) |*decl| {
                decl.deinit();
            }
            declarations.deinit(self.allocator);
        }

        // 手动解析内联样式（格式：property: value; property: value; ...）
        // 按分号分割
        var iter = std.mem.splitSequence(u8, style_attr, ";");
        while (iter.next()) |decl_str| {
            const trimmed = std.mem.trim(u8, decl_str, " \t\n\r");
            if (trimmed.len == 0) continue;

            // 查找冒号
            const colon_pos = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
            const property_name = std.mem.trim(u8, trimmed[0..colon_pos], " \t\n\r");
            const value_str = std.mem.trim(u8, trimmed[colon_pos + 1 ..], " \t\n\r");

            if (property_name.len == 0 or value_str.len == 0) continue;

            // 复制属性名
            const name = try self.allocator.dupe(u8, property_name);

            // 解析值（简化：只支持关键字和长度值）
            var value: parser.Value = undefined;
            // 检查是否包含空格（多值属性，如 grid-template-columns: 200px 200px）
            if (std.mem.indexOfScalar(u8, value_str, ' ') != null) {
                // 多值属性，作为关键字存储
                const keyword = try self.allocator.dupe(u8, value_str);
                value = parser.Value{ .keyword = keyword };
                std.log.debug("[Cascade] parseInlineStyle: parsed multi-value property '{s}' = '{s}'", .{ property_name, keyword });
            } else if (std.mem.indexOfScalar(u8, value_str, 'p') != null and std.mem.indexOfScalar(u8, value_str, 'x') != null) {
                // 可能是长度值（如 "50px"）
                const px_pos = std.mem.indexOfScalar(u8, value_str, 'p') orelse {
                    self.allocator.free(name);
                    continue;
                };
                if (px_pos + 1 < value_str.len and value_str[px_pos + 1] == 'x') {
                    const num_str = std.mem.trim(u8, value_str[0..px_pos], " \t\n\r");
                    const num = std.fmt.parseFloat(f64, num_str) catch {
                        self.allocator.free(name);
                        continue;
                    };
                    const unit = try self.allocator.dupe(u8, "px");
                    value = parser.Value{
                        .length = .{
                            .value = num,
                            .unit = unit,
                        },
                    };
                    std.log.debug("[Cascade] parseInlineStyle: parsed length property '{s}' = {d}px", .{ property_name, num });
                } else {
                    // 关键字
                    const keyword = try self.allocator.dupe(u8, value_str);
                    value = parser.Value{ .keyword = keyword };
                    std.log.debug("[Cascade] parseInlineStyle: parsed keyword property '{s}' = '{s}'", .{ property_name, keyword });
                }
            } else {
                // 关键字
                const keyword = try self.allocator.dupe(u8, value_str);
                value = parser.Value{ .keyword = keyword };
                std.log.debug("[Cascade] parseInlineStyle: parsed keyword property '{s}' = '{s}'", .{ property_name, keyword });
            }

            const decl = parser.Declaration{
                .name = name,
                .value = value,
                .important = false,
                .allocator = self.allocator,
            };

            try declarations.append(self.allocator, decl);
        }

        return declarations;
    }
};
