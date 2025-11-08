const std = @import("std");
const tokenizer = @import("tokenizer");
const selector = @import("selector");

/// CSS解析错误
pub const ParseError = error{
    UnexpectedEOF,
    InvalidAttributeSelector,
    InvalidClassSelector,
    InvalidPseudoSelector,
    InvalidValue,
    InvalidColor,
    SelectorParseError,
    InvalidSelector,
};

/// CSS样式表
pub const Stylesheet = struct {
    rules: std.ArrayList(Rule),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Stylesheet {
        return .{
            .rules = std.ArrayList(Rule).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Stylesheet) void {
        for (self.rules.items) |*rule| {
            rule.deinit(self.allocator);
        }
        self.rules.deinit();
    }
};

/// CSS规则
pub const Rule = struct {
    selectors: std.ArrayList(selector.Selector), // 完整的选择器对象
    declarations: std.ArrayList(Declaration),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Rule {
        return .{
            .selectors = std.ArrayList(selector.Selector).init(allocator),
            .declarations = std.ArrayList(Declaration).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Rule, allocator: std.mem.Allocator) void {
        for (self.selectors.items) |*sel| {
            sel.deinit();
        }
        self.selectors.deinit();

        for (self.declarations.items) |*decl| {
            decl.deinit(allocator);
        }
        self.declarations.deinit();
    }
};

/// CSS声明
pub const Declaration = struct {
    name: []const u8,
    value: Value,
    important: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, value: Value, important: bool) !Declaration {
        const name_dup = try allocator.dupe(u8, name);
        return .{
            .name = name_dup,
            .value = value,
            .important = important,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Declaration, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.value.deinit(allocator);
    }
};

/// CSS值
pub const Value = union(enum) {
    keyword: []const u8,
    length: Length,
    color: Color,
    string: []const u8,
    number: f32,
    percentage: f32,

    pub fn deinit(self: *const Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .keyword => |k| allocator.free(k),
            .string => |s| allocator.free(s),
            .length => |len| len.deinit(allocator),
            else => {},
        }
    }
};

/// CSS长度值
pub const Length = struct {
    value: f32,
    unit: []const u8,

    pub fn deinit(self: *const Length, allocator: std.mem.Allocator) void {
        allocator.free(self.unit);
    }
};

/// CSS颜色值
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

/// CSS解析器
pub const Parser = struct {
    tokenizer: tokenizer.Tokenizer,
    allocator: std.mem.Allocator,
    current_token: ?tokenizer.Token = null,

    const Self = @This();

    /// 初始化解析器
    pub fn init(input: []const u8, allocator: std.mem.Allocator) Self {
        return .{
            .tokenizer = tokenizer.Tokenizer.init(input, allocator),
            .allocator = allocator,
        };
    }

    /// 销毁解析器，释放所有资源
    pub fn deinit(self: *Self) void {
        // 释放缓存的 token
        if (self.current_token) |token| {
            token.deinit();
            self.current_token = null;
        }
        // tokenizer 不需要释放（它只存储 input 的引用）
    }

    /// 解析样式表
    pub fn parse(self: *Self) !Stylesheet {
        var stylesheet = Stylesheet.init(self.allocator);
        errdefer stylesheet.deinit();

        const max_iterations: usize = 10000; // 防止死循环
        var iteration_count: usize = 0;
        while (iteration_count < max_iterations) {
            iteration_count += 1;
            const token = try self.next();
            if (token) |t| {
                switch (t.token_type) {
                    .whitespace, .comment => {
                        t.deinit();
                        continue;
                    },
                    .at_keyword => {
                        t.deinit();
                        // TODO: 处理@规则（@media, @keyframes等）
                        try self.skipAtRule();
                    },
                    .eof => {
                        t.deinit();
                        // 确保清理 current_token
                        if (self.current_token) |cached_token| {
                            cached_token.deinit();
                            self.current_token = null;
                        }
                        break;
                    },
                    .ident, .hash => {
                        // 开始解析规则（不回退，直接使用当前token）
                        if (try self.parseRuleFromToken(t)) |rule| {
                            try stylesheet.rules.append(rule);
                        }
                    },
                    else => {
                        // 其他token，可能是选择器的一部分，尝试解析规则
                        if (try self.parseRuleFromToken(t)) |rule| {
                            try stylesheet.rules.append(rule);
                        } else {
                            t.deinit();
                            // 无法解析，跳过
                            break;
                        }
                    },
                }
            } else {
                break;
            }
        }

        if (iteration_count >= max_iterations) {
            // 确保在错误时也清理 current_token
            if (self.current_token) |cached_token| {
                cached_token.deinit();
                self.current_token = null;
            }
            return error.SelectorParseError; // 防止死循环
        }

        // 确保在返回前清理 current_token
        if (self.current_token) |cached_token| {
            cached_token.deinit();
            self.current_token = null;
        }

        return stylesheet;
    }

    /// 从当前token开始解析规则
    fn parseRuleFromToken(self: *Self, first_token: tokenizer.Token) !?Rule {
        // 将第一个token放入缓存（注意：parseRule会负责释放这个token）
        self.current_token = first_token;
        const result = try self.parseRule();
        // 确保current_token被清理（如果parseRule没有消费完）
        if (self.current_token) |token| {
            token.deinit();
            self.current_token = null;
        }
        return result;
    }

    /// 解析规则
    fn parseRule(self: *Self) !?Rule {
        errdefer {
            // 确保在错误时也清理 current_token
            if (self.current_token) |cached_token| {
                cached_token.deinit();
                self.current_token = null;
            }
        }
        var rule = Rule.init(self.allocator);
        errdefer rule.deinit(self.allocator);

        // 解析选择器列表（用逗号分隔）
        var first_selector = true;
        const max_iterations: usize = 1000; // 防止死循环
        var iteration_count: usize = 0;
        while (iteration_count < max_iterations) {
            iteration_count += 1;
            const token = try self.next();
            if (token) |t| {
                var should_defer = true;

                switch (t.token_type) {
                    .whitespace => {
                        t.deinit();
                        continue;
                    },
                    .delim => {
                        const ch = t.data.delim;
                        if (ch == '{') {
                            // 开始解析声明
                            t.deinit();
                            break;
                        }
                        if (ch == ',') {
                            // 逗号分隔的选择器
                            t.deinit();
                            first_selector = true;
                            continue;
                        }
                        // 其他分隔符（如 `.`），回退token，让parseSelector处理
                        self.current_token = t;
                        should_defer = false;
                        const parsed_selector = try self.parseSelector();
                        try rule.selectors.append(parsed_selector);
                        first_selector = false;
                        // 检查下一个token是否是 `{`
                        const next_token = try self.next();
                        if (next_token) |nt| {
                            if (nt.token_type == .delim and nt.data.delim == '{') {
                                nt.deinit();
                                break;
                            }
                            // 回退token
                            self.current_token = nt;
                        }
                        continue;
                    },
                    else => {
                        // 回退token，开始解析选择器
                        // 注意：不要释放token，因为它会被存储在current_token中
                        self.current_token = t;
                        should_defer = false;
                        const parsed_selector = try self.parseSelector();
                        try rule.selectors.append(parsed_selector);
                        first_selector = false;
                        // 检查下一个token是否是 `{`
                        const next_token = try self.next();
                        if (next_token) |nt| {
                            if (nt.token_type == .delim and nt.data.delim == '{') {
                                nt.deinit();
                                break;
                            }
                            // 回退token
                            self.current_token = nt;
                        }
                        continue;
                    },
                }

                if (should_defer) {
                    t.deinit();
                }
            } else {
                break;
            }
        }

        if (iteration_count >= max_iterations) {
            // 确保在错误时也清理 current_token
            if (self.current_token) |cached_token| {
                cached_token.deinit();
                self.current_token = null;
            }
            return error.SelectorParseError; // 防止死循环
        }

        // 解析声明列表
        while (try self.next()) |token| {
            defer token.deinit();

            switch (token.token_type) {
                .whitespace, .comment => continue,
                .delim => {
                    const ch = token.data.delim;
                    if (ch == '}') {
                        break;
                    }
                    if (ch == ';') {
                        continue;
                    }
                },
                .ident => {
                    const name = token.data.ident;
                    // 解析声明
                    if (try self.parseDeclaration(name)) |decl| {
                        try rule.declarations.append(decl);
                    }
                },
                else => {},
            }
        }

        // 确保在返回前清理 current_token（如果还有残留）
        if (self.current_token) |cached_token| {
            cached_token.deinit();
            self.current_token = null;
        }

        return rule;
    }

    /// 解析完整的选择器（可能包含多个序列，用组合器连接）
    fn parseSelector(self: *Self) !selector.Selector {
        var sel = selector.Selector.init(self.allocator);
        errdefer sel.deinit();

        // 解析第一个选择器序列
        var sequence = try self.parseSelectorSequence();
        try sel.sequences.append(sequence);

        // 循环处理组合器和后续选择器
        while (true) {
            const token = try self.next();
            if (token) |t| {
                var is_combinator = false;
                var combinator: ?selector.Combinator = null;

                if (t.token_type == .whitespace) {
                    // 空白表示后代组合器
                    is_combinator = true;
                    combinator = .descendant;
                    t.deinit();
                } else if (t.token_type == .delim) {
                    const ch = t.data.delim;
                    if (ch == '>') {
                        is_combinator = true;
                        combinator = .child;
                        t.deinit();
                    } else if (ch == '+') {
                        is_combinator = true;
                        combinator = .adjacent;
                        t.deinit();
                    } else if (ch == '~') {
                        is_combinator = true;
                        combinator = .sibling;
                        t.deinit();
                    } else if (ch == ',' or ch == '{' or ch == '}') {
                        // 选择器结束，回退token
                        self.current_token = t;
                        break;
                    } else {
                        // 不是组合器，回退token
                        self.current_token = t;
                        break;
                    }
                } else {
                    // 不是组合器，回退token
                    self.current_token = t;
                    break;
                }

                if (is_combinator) {
                    // 解析组合器后的选择器序列
                    var next_sequence = try self.parseSelectorSequence();
                    defer next_sequence.deinit();

                    // 创建新的序列，将组合器添加到前一个序列
                    if (combinator) |comb| {
                        try sequence.combinators.append(comb);
                    }

                    // 将新序列的选择器添加到当前序列
                    for (next_sequence.selectors.items) |*selector_item| {
                        const simple_sel = selector.SimpleSelector{
                            .selector_type = selector_item.selector_type,
                            .value = try self.allocator.dupe(u8, selector_item.value),
                            .attribute_name = if (selector_item.attribute_name) |name|
                                try self.allocator.dupe(u8, name)
                            else
                                null,
                            .attribute_value = if (selector_item.attribute_value) |val|
                                try self.allocator.dupe(u8, val)
                            else
                                null,
                            .attribute_match = selector_item.attribute_match,
                            .allocator = self.allocator,
                        };
                        try sequence.selectors.append(simple_sel);
                    }
                }
            } else {
                break;
            }
        }

        return sel;
    }

    /// 解析选择器序列（由简单选择器和组合器组成）
    fn parseSelectorSequence(self: *Self) !selector.SelectorSequence {
        var sequence = selector.SelectorSequence.init(self.allocator);
        errdefer sequence.deinit();

        var has_prev_selector = false;
        const max_iterations: usize = 1000; // 防止死循环
        var iteration_count: usize = 0;

        while (iteration_count < max_iterations) {
            iteration_count += 1;
            const token = try self.next();
            if (token) |t| {
                var should_defer = true;

                switch (t.token_type) {
                    .whitespace => {
                        // 空白表示后代组合器，结束当前序列
                        if (has_prev_selector) {
                            // 检查下一个token，如果是选择器结束符，直接退出，不回退空白token
                            const next_token = try self.peek();
                            if (next_token) |nt| {
                                if (nt.token_type == .delim) {
                                    const ch = nt.data.delim;
                                    if (ch == ',' or ch == '{' or ch == '}') {
                                        // 选择器结束，不回退空白token，直接退出
                                        // 注意：peek的token还在current_token中，需要消费它
                                        const consumed_token = try self.next();
                                        if (consumed_token) |ct| {
                                            ct.deinit();
                                        }
                                        t.deinit();
                                        should_defer = false;
                                        break;
                                    }
                                }
                                // 如果不是结束符，peek的token还在current_token中，会被后续处理
                            }
                            // 回退空白token，让parseSelector处理组合器
                            self.current_token = t;
                            should_defer = false;
                            break; // 让parseSelector处理组合器
                        }
                        // 如果没有前一个选择器，忽略空白
                        t.deinit();
                        continue;
                    },
                    .delim => {
                        const ch = t.data.delim;
                        if (ch == ',' or ch == '{' or ch == '}') {
                            // 选择器结束，回退token
                            self.current_token = t;
                            should_defer = false;
                            break;
                        }
                        if (ch == '>' or ch == '+' or ch == '~') {
                            // 遇到组合器，结束当前序列
                            if (!has_prev_selector) {
                                t.deinit();
                                return error.InvalidSelector;
                            }
                            self.current_token = t; // 回退组合器token
                            should_defer = false;
                            break;
                        }
                        if (ch == '.') {
                            // 类选择器
                            const class_token = (try self.next()) orelse {
                                return error.UnexpectedEOF;
                            };
                            defer class_token.deinit();
                            if (class_token.token_type == .ident) {
                                const simple_sel = try self.parseClassSelector(class_token.data.ident);
                                try sequence.selectors.append(simple_sel);
                                has_prev_selector = true;
                                continue;
                            } else {
                                return error.InvalidClassSelector;
                            }
                        }
                        if (ch == '[') {
                            // 属性选择器，回退token
                            self.current_token = t;
                            should_defer = false;
                            const simple_sel = try self.parseAttributeSelector();
                            try sequence.selectors.append(simple_sel);
                            has_prev_selector = true;
                            continue;
                        }
                        if (ch == '*') {
                            // 通配符选择器
                            const simple_sel = selector.SimpleSelector{
                                .selector_type = .universal,
                                .value = try self.allocator.dupe(u8, "*"),
                                .allocator = self.allocator,
                            };
                            try sequence.selectors.append(simple_sel);
                            has_prev_selector = true;
                            continue;
                        }
                        // 其他分隔符，可能是选择器的一部分，回退
                        self.current_token = t;
                        should_defer = false;
                        break;
                    },
                    .ident => {
                        // 类型选择器
                        const simple_sel = selector.SimpleSelector{
                            .selector_type = .type,
                            .value = try self.allocator.dupe(u8, t.data.ident),
                            .allocator = self.allocator,
                        };
                        try sequence.selectors.append(simple_sel);
                        has_prev_selector = true;
                        // 继续解析，可能还有类选择器、ID选择器等
                        continue;
                    },
                    .hash => {
                        // ID选择器
                        const simple_sel = selector.SimpleSelector{
                            .selector_type = .id,
                            .value = try self.allocator.dupe(u8, t.data.hash),
                            .allocator = self.allocator,
                        };
                        try sequence.selectors.append(simple_sel);
                        has_prev_selector = true;
                        // 继续解析，可能还有类选择器等
                        continue;
                    },
                    .function => {
                        // 可能是伪类或伪元素（:hover, ::before等）
                        const func_name = t.data.function;
                        if (func_name.len > 0 and func_name[0] == ':') {
                            self.current_token = t;
                            should_defer = false;
                            const simple_sel = try self.parsePseudoSelector();
                            try sequence.selectors.append(simple_sel);
                            has_prev_selector = true;
                            continue;
                        } else {
                            // 不是伪类，回退
                            self.current_token = t;
                            should_defer = false;
                            break;
                        }
                    },
                    else => {
                        // 其他token，回退
                        self.current_token = t;
                        should_defer = false;
                        break;
                    },
                }

                if (should_defer) {
                    t.deinit();
                }
            } else {
                // EOF，退出循环
                break;
            }
        }

        if (iteration_count >= max_iterations) {
            return error.SelectorParseError; // 防止死循环
        }

        return sequence;
    }

    /// 解析类选择器（.class）
    fn parseClassSelector(self: *Self, class_name: []const u8) !selector.SimpleSelector {
        return selector.SimpleSelector{
            .selector_type = .class,
            .value = try self.allocator.dupe(u8, class_name),
            .allocator = self.allocator,
        };
    }

    /// 解析属性选择器（[attr], [attr=value], [attr~=value]等）
    fn parseAttributeSelector(self: *Self) !selector.SimpleSelector {
        // 跳过 '['
        _ = try self.next();

        // 解析属性名
        const attr_token = (try self.next()) orelse return error.UnexpectedEOF;
        defer attr_token.deinit();
        if (attr_token.token_type != .ident) {
            return error.InvalidAttributeSelector;
        }
        const attr_name = try self.allocator.dupe(u8, attr_token.data.ident);
        errdefer self.allocator.free(attr_name);

        var attr_value: ?[]const u8 = null;
        var match_type = selector.SimpleSelector.AttributeMatch.exact;

        // 检查是否有匹配操作符
        while (try self.next()) |token| {
            defer token.deinit();

            switch (token.token_type) {
                .delim => {
                    const ch = token.data.delim;
                    if (ch == ']') {
                        // 属性选择器结束
                        break;
                    }
                    if (ch == '=') {
                        match_type = .exact;
                        // 解析值
                        const value_token = (try self.next()) orelse return error.UnexpectedEOF;
                        defer value_token.deinit();
                        if (value_token.token_type == .ident or value_token.token_type == .string) {
                            const value = if (value_token.token_type == .ident)
                                value_token.data.ident
                            else
                                value_token.data.string;
                            attr_value = try self.allocator.dupe(u8, value);
                        }
                    } else if (ch == '~') {
                        // [attr~=value]
                        match_type = .contains;
                        const eq_token = (try self.next()) orelse return error.UnexpectedEOF;
                        defer eq_token.deinit();
                        if (eq_token.token_type == .delim and eq_token.data.delim == '=') {
                            const value_token = (try self.next()) orelse return error.UnexpectedEOF;
                            defer value_token.deinit();
                            if (value_token.token_type == .ident or value_token.token_type == .string) {
                                const value = if (value_token.token_type == .ident)
                                    value_token.data.ident
                                else
                                    value_token.data.string;
                                attr_value = try self.allocator.dupe(u8, value);
                            }
                        }
                    } else if (ch == '^') {
                        // [attr^=value]
                        match_type = .prefix;
                        const eq_token = (try self.next()) orelse return error.UnexpectedEOF;
                        defer eq_token.deinit();
                        if (eq_token.token_type == .delim and eq_token.data.delim == '=') {
                            const value_token = (try self.next()) orelse return error.UnexpectedEOF;
                            defer value_token.deinit();
                            if (value_token.token_type == .ident or value_token.token_type == .string) {
                                const value = if (value_token.token_type == .ident)
                                    value_token.data.ident
                                else
                                    value_token.data.string;
                                attr_value = try self.allocator.dupe(u8, value);
                            }
                        }
                    } else if (ch == '$') {
                        // [attr$=value]
                        match_type = .suffix;
                        const eq_token = (try self.next()) orelse return error.UnexpectedEOF;
                        defer eq_token.deinit();
                        if (eq_token.token_type == .delim and eq_token.data.delim == '=') {
                            const value_token = (try self.next()) orelse return error.UnexpectedEOF;
                            defer value_token.deinit();
                            if (value_token.token_type == .ident or value_token.token_type == .string) {
                                const value = if (value_token.token_type == .ident)
                                    value_token.data.ident
                                else
                                    value_token.data.string;
                                attr_value = try self.allocator.dupe(u8, value);
                            }
                        }
                    } else if (ch == '*') {
                        // [attr*=value]
                        match_type = .substring;
                        const eq_token = (try self.next()) orelse return error.UnexpectedEOF;
                        defer eq_token.deinit();
                        if (eq_token.token_type == .delim and eq_token.data.delim == '=') {
                            const value_token = (try self.next()) orelse return error.UnexpectedEOF;
                            defer value_token.deinit();
                            if (value_token.token_type == .ident or value_token.token_type == .string) {
                                const value = if (value_token.token_type == .ident)
                                    value_token.data.ident
                                else
                                    value_token.data.string;
                                attr_value = try self.allocator.dupe(u8, value);
                            }
                        }
                    } else if (ch == '|') {
                        // [attr|=value]
                        match_type = .hyphen;
                        const eq_token = (try self.next()) orelse return error.UnexpectedEOF;
                        defer eq_token.deinit();
                        if (eq_token.token_type == .delim and eq_token.data.delim == '=') {
                            const value_token = (try self.next()) orelse return error.UnexpectedEOF;
                            defer value_token.deinit();
                            if (value_token.token_type == .ident or value_token.token_type == .string) {
                                const value = if (value_token.token_type == .ident)
                                    value_token.data.ident
                                else
                                    value_token.data.string;
                                attr_value = try self.allocator.dupe(u8, value);
                            }
                        }
                    }
                },
                .whitespace => continue,
                else => {},
            }
        }

        return selector.SimpleSelector{
            .selector_type = .attribute,
            .value = try self.allocator.dupe(u8, ""), // 属性选择器不需要value字段
            .attribute_name = attr_name,
            .attribute_value = attr_value,
            .attribute_match = match_type,
            .allocator = self.allocator,
        };
    }

    /// 解析伪类或伪元素选择器（:hover, ::before等）
    fn parsePseudoSelector(self: *Self) !selector.SimpleSelector {
        const token = (try self.next()) orelse return error.UnexpectedEOF;
        defer token.deinit();

        if (token.token_type != .function) {
            return error.InvalidPseudoSelector;
        }

        const func_name = token.data.function;
        const selector_type: selector.SelectorType = if (func_name.len > 1 and func_name[1] == ':')
            .pseudo_element
        else
            .pseudo_class;

        // 移除开头的:或::
        const pseudo_name = func_name[if (selector_type == .pseudo_element) 2 else 1..];

        return selector.SimpleSelector{
            .selector_type = selector_type,
            .value = try self.allocator.dupe(u8, pseudo_name),
            .allocator = self.allocator,
        };
    }

    /// 解析声明
    fn parseDeclaration(self: *Self, name: []const u8) !?Declaration {
        // 跳过冒号
        while (try self.next()) |token| {
            defer token.deinit();
            if (token.token_type == .delim and token.data.delim == ':') {
                break;
            }
        }

        // 解析值
        const value = try self.parseValue();
        var important = false;

        // 检查!important（需要先检查是否有!）
        // 跳过可能的空白
        var found_important = false;
        while (try self.next()) |token| {
            defer token.deinit();
            if (token.token_type == .whitespace) {
                continue;
            }
            if (token.token_type == .delim and token.data.delim == '!') {
                // 检查important
                if (try self.next()) |important_token| {
                    defer important_token.deinit();
                    if (important_token.token_type == .ident) {
                        const ident = important_token.data.ident;
                        if (std.mem.eql(u8, ident, "important")) {
                            important = true;
                            found_important = true;
                        }
                    }
                }
                break;
            } else {
                // 不是!，回退token
                self.current_token = token;
                break;
            }
        }

        return try Declaration.init(self.allocator, name, value, important);
    }

    /// 解析值
    fn parseValue(self: *Self) !Value {
        // 跳过空白字符
        var token = (try self.next()) orelse {
            return error.UnexpectedEOF;
        };
        while (token.token_type == .whitespace) {
            token.deinit();
            token = (try self.next()) orelse {
                return error.UnexpectedEOF;
            };
        }
        defer token.deinit();

        return switch (token.token_type) {
            .ident => {
                const ident = token.data.ident;
                const keyword = try self.allocator.dupe(u8, ident);
                return Value{ .keyword = keyword };
            },
            .string => {
                const str = token.data.string;
                const str_dup = try self.allocator.dupe(u8, str);
                return Value{ .string = str_dup };
            },
            .number => Value{ .number = token.data.number },
            .percentage => Value{ .percentage = token.data.percentage },
            .dimension => {
                const dim = token.data.dimension;
                const unit = try self.allocator.dupe(u8, dim.unit);
                return Value{
                    .length = .{
                        .value = dim.value,
                        .unit = unit,
                    },
                };
            },
            .hash => {
                const hash = token.data.hash;
                // 解析颜色
                const color = try self.parseColor(hash);
                return Value{ .color = color };
            },
            else => {
                // 默认作为关键字处理
                return error.InvalidValue;
            },
        };
    }

    /// 解析颜色
    fn parseColor(self: *Self, hash: []const u8) !Color {
        _ = self;
        // 简化的颜色解析，支持#rgb和#rrggbb
        if (hash.len == 3) {
            var r_buf: [2]u8 = undefined;
            r_buf[0] = hash[0];
            r_buf[1] = hash[0];
            var g_buf: [2]u8 = undefined;
            g_buf[0] = hash[1];
            g_buf[1] = hash[1];
            var b_buf: [2]u8 = undefined;
            b_buf[0] = hash[2];
            b_buf[1] = hash[2];
            const r = try std.fmt.parseInt(u8, &r_buf, 16);
            const g = try std.fmt.parseInt(u8, &g_buf, 16);
            const b = try std.fmt.parseInt(u8, &b_buf, 16);
            return Color{ .r = r, .g = g, .b = b };
        } else if (hash.len == 6) {
            const r = try std.fmt.parseInt(u8, hash[0..2], 16);
            const g = try std.fmt.parseInt(u8, hash[2..4], 16);
            const b = try std.fmt.parseInt(u8, hash[4..6], 16);
            return Color{ .r = r, .g = g, .b = b };
        }
        return error.InvalidColor;
    }

    /// 获取下一个token（带缓存）
    fn next(self: *Self) !?tokenizer.Token {
        if (self.current_token) |token| {
            self.current_token = null;
            return token;
        }
        return try self.tokenizer.next();
    }

    /// 查看下一个token但不消耗（peek）
    fn peek(self: *Self) !?tokenizer.Token {
        if (self.current_token) |token| {
            return token;
        }
        // 从tokenizer读取一个token，但不消耗（回退到current_token）
        const token = try self.tokenizer.next();
        if (token) |t| {
            self.current_token = t;
        }
        return token;
    }

    /// 跳过@规则
    fn skipAtRule(self: *Self) !void {
        var depth: usize = 0;
        while (try self.next()) |token| {
            defer token.deinit();
            switch (token.token_type) {
                .delim => {
                    const ch = token.data.delim;
                    if (ch == '{') {
                        depth += 1;
                    } else if (ch == '}') {
                        if (depth == 0) {
                            break;
                        }
                        depth -= 1;
                    }
                },
                .eof => break,
                else => {},
            }
        }
    }
};
