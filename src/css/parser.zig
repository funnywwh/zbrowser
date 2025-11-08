const std = @import("std");
const tokenizer = @import("tokenizer");
const selector = @import("selector");

/// CSS值类型
pub const Value = union(enum) {
    keyword: []const u8,
    length: Length,
    percentage: f64,
    color: Color,

    pub const Length = struct {
        value: f64,
        unit: []const u8,
    };

    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
    };

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .keyword => |k| allocator.free(k),
            .length => |l| allocator.free(l.unit),
            .percentage, .color => {},
        }
    }
};

/// CSS声明
pub const Declaration = struct {
    name: []const u8,
    value: Value,
    important: bool = false,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Declaration) void {
        self.allocator.free(self.name);
        self.value.deinit(self.allocator);
    }
};

/// CSS规则
pub const Rule = struct {
    selectors: std.ArrayList(selector.Selector),
    declarations: std.ArrayList(Declaration),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Rule) void {
        for (self.selectors.items) |*sel| {
            sel.deinit();
        }
        self.selectors.deinit();
        for (self.declarations.items) |*decl| {
            decl.deinit();
        }
        self.declarations.deinit();
    }
};

/// CSS样式表
pub const Stylesheet = struct {
    rules: std.ArrayList(Rule),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Stylesheet) void {
        for (self.rules.items) |*rule| {
            rule.deinit();
        }
        self.rules.deinit();
    }
};

/// CSS递归下降解析器
pub const Parser = struct {
    tokenizer: tokenizer.Tokenizer,
    current_token: ?tokenizer.Token = null,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(input: []const u8, allocator: std.mem.Allocator) Self {
        return .{
            .tokenizer = tokenizer.Tokenizer.init(input, allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.current_token) |*token| {
            token.deinit(self.allocator);
        }
    }

    /// 解析样式表
    pub fn parse(self: *Self) !Stylesheet {
        var stylesheet = Stylesheet{
            .rules = std.ArrayList(Rule).init(self.allocator),
            .allocator = self.allocator,
        };
        errdefer stylesheet.deinit();

        try self.advance();
        while (self.current_token) |token| {
            switch (token.token_type) {
                .cdo, .cdc, .comment, .whitespace => {
                    // 跳过CDO、CDC、注释和空白
                    try self.advance();
                },
                .eof => break,
                else => {
                    // 尝试解析规则
                    const rule_result = self.parseRule();
                    if (rule_result) |rule| {
                        try stylesheet.rules.append(rule);
                    } else |_| {
                        // 解析错误，跳过当前token继续
                        // tokenizer保证总是会推进pos或返回EOF，所以这里直接advance即可
                        try self.advance();
                    }
                },
            }
        }

        return stylesheet;
    }

    /// 解析规则: selector_list '{' declaration_list '}'
    fn parseRule(self: *Self) !Rule {
        // 解析选择器列表
        var selectors = std.ArrayList(selector.Selector).init(self.allocator);
        errdefer {
            for (selectors.items) |*sel| {
                sel.deinit();
            }
            selectors.deinit();
        }

        var sel = try self.parseSelector();
        try selectors.append(sel);

        // 解析逗号分隔的选择器
        while (self.current_token) |token| {
            if (token.token_type == .delim and token.data.delim == ',') {
                try self.advance();
                sel = try self.parseSelector();
                try selectors.append(sel);
            } else {
                break;
            }
        }

        // 期望 '{'
        try self.expectDelim('{');

        // 解析声明列表
        var declarations = std.ArrayList(Declaration).init(self.allocator);
        errdefer {
            for (declarations.items) |*decl| {
                decl.deinit();
            }
            declarations.deinit();
        }

        var last_pos: usize = self.tokenizer.pos;
        while (self.current_token) |token| {
            // 防止死循环
            if (self.tokenizer.pos == last_pos) {
                try self.advance();
                last_pos = self.tokenizer.pos;
                continue;
            }
            last_pos = self.tokenizer.pos;

            if (token.token_type == .delim and token.data.delim == '}') {
                try self.advance();
                break;
            }

            // 跳过分号
            if (token.token_type == .delim and token.data.delim == ';') {
                try self.advance();
                continue;
            }

            // 解析声明
            if (self.parseDeclaration()) |decl| {
                try declarations.append(decl);
            } else |_| {
                // 解析错误，跳过到下一个分号或右大括号
                var skip_last_pos: usize = self.tokenizer.pos;
                while (self.current_token) |t| {
                    if (self.tokenizer.pos == skip_last_pos) {
                        try self.advance();
                        skip_last_pos = self.tokenizer.pos;
                        continue;
                    }
                    skip_last_pos = self.tokenizer.pos;

                    if (t.token_type == .delim and (t.data.delim == ';' or t.data.delim == '}')) {
                        break;
                    }
                    if (t.token_type == .eof) {
                        break;
                    }
                    try self.advance();
                }
            }
        }

        return Rule{
            .selectors = selectors,
            .declarations = declarations,
            .allocator = self.allocator,
        };
    }

    /// 解析选择器: simple_selector_sequence (combinator simple_selector_sequence)*
    fn parseSelector(self: *Self) !selector.Selector {
        var sel = selector.Selector.init(self.allocator);
        errdefer sel.deinit();

        const sequence = try self.parseSelectorSequence();
        try sel.sequences.append(sequence);

        // 解析组合器和后续序列
        while (self.current_token) |token| {
            // 如果遇到规则结束符，直接退出
            if (token.token_type == .delim) {
                const delim = token.data.delim;
                if (delim == ',' or delim == '{' or delim == '}') {
                    break;
                }
            }
            if (token.token_type == .eof) {
                break;
            }

            // 检查是否有显式组合器（>, +, ~）
            if (self.parseCombinator()) |combinator| {
                const next_sequence = try self.parseSelectorSequence();
                try sel.sequences.append(next_sequence);
                // 将组合器添加到前一个序列
                if (sel.sequences.items.len > 1) {
                    const prev_idx = sel.sequences.items.len - 2;
                    try sel.sequences.items[prev_idx].combinators.append(combinator);
                }
            } else {
                // 没有显式组合器，检查是否是后代选择器（空白分隔）
                // 如果下一个token是简单选择器的开始，说明中间有空白（后代组合器）
                if (self.canStartSimpleSelector()) {
                    const next_sequence = try self.parseSelectorSequence();
                    try sel.sequences.append(next_sequence);
                    // 添加后代组合器
                    if (sel.sequences.items.len > 1) {
                        const prev_idx = sel.sequences.items.len - 2;
                        try sel.sequences.items[prev_idx].combinators.append(.descendant);
                    }
                } else {
                    // 不是选择器，退出
                    break;
                }
            }
        }

        return sel;
    }

    /// 检查当前token是否可以开始一个简单选择器
    fn canStartSimpleSelector(self: *Self) bool {
        const token = self.current_token orelse return false;
        return switch (token.token_type) {
            .ident, .hash => true,
            .delim => {
                const d = token.data.delim;
                return d == '.' or d == '#' or d == '*';
            },
            else => false,
        };
    }

    /// 解析选择器序列: simple_selector+
    fn parseSelectorSequence(self: *Self) !selector.SelectorSequence {
        var sequence = selector.SelectorSequence.init(self.allocator);
        errdefer sequence.deinit();

        // 解析一个或多个简单选择器
        // 至少需要一个简单选择器
        if (self.parseSimpleSelector()) |simple_sel| {
            try sequence.selectors.append(simple_sel);
        } else |_| {
            return error.InvalidSelector;
        }

        // 继续解析更多简单选择器（如 div.container#id）
        while (self.current_token) |t| {
            // 如果遇到结束符，停止
            if (t.token_type == .delim) {
                const delim = t.data.delim;
                if (delim == ',' or delim == '{' or delim == '}' or delim == '>' or delim == '+' or delim == '~') {
                    break;
                }
            }
            if (t.token_type == .eof) {
                break;
            }

            // 尝试解析更多简单选择器
            if (self.parseSimpleSelector()) |simple_sel| {
                try sequence.selectors.append(simple_sel);
            } else |_| {
                // 无法解析，停止
                break;
            }
        }

        return sequence;
    }

    /// 解析简单选择器
    fn parseSimpleSelector(self: *Self) !selector.SimpleSelector {
        const token = self.current_token orelse return error.UnexpectedEof;

        switch (token.token_type) {
            .ident => {
                const ident = token.data.ident;
                try self.advance();
                return selector.SimpleSelector{
                    .selector_type = .type,
                    .value = try self.allocator.dupe(u8, ident),
                    .allocator = self.allocator,
                };
            },
            .hash => {
                const hash = token.data.hash;
                try self.advance();
                return selector.SimpleSelector{
                    .selector_type = .id,
                    .value = try self.allocator.dupe(u8, hash),
                    .allocator = self.allocator,
                };
            },
            .delim => {
                const delim = token.data.delim;
                if (delim == '.') {
                    try self.advance();
                    const next_token = self.current_token orelse return error.UnexpectedEof;
                    if (next_token.token_type == .ident) {
                        const ident = next_token.data.ident;
                        try self.advance();
                        return selector.SimpleSelector{
                            .selector_type = .class,
                            .value = try self.allocator.dupe(u8, ident),
                            .allocator = self.allocator,
                        };
                    }
                    return error.InvalidSelector;
                } else if (delim == '*') {
                    try self.advance();
                    return selector.SimpleSelector{
                        .selector_type = .universal,
                        .value = try self.allocator.dupe(u8, "*"),
                        .allocator = self.allocator,
                    };
                }
                return error.InvalidSelector;
            },
            .eof => return error.UnexpectedEof,
            else => return error.InvalidSelector,
        }
    }

    /// 解析组合器
    /// 注意：tokenizer已经跳过了空白，所以空白不会作为token出现
    /// 后代组合器通过检查两个选择器序列之间是否有其他token来判断
    fn parseCombinator(self: *Self) ?selector.Combinator {
        const token = self.current_token orelse return null;

        switch (token.token_type) {
            .delim => {
                const delim = token.data.delim;
                if (delim == '>') {
                    _ = self.advance() catch return null;
                    return .child;
                } else if (delim == '+') {
                    _ = self.advance() catch return null;
                    return .adjacent;
                } else if (delim == '~') {
                    _ = self.advance() catch return null;
                    return .sibling;
                }
                return null;
            },
            else => return null,
        }
    }

    /// 解析声明: property ':' value important?
    fn parseDeclaration(self: *Self) !Declaration {
        // 解析属性名
        const token = self.current_token orelse return error.UnexpectedEof;
        if (token.token_type != .ident) {
            return error.InvalidDeclaration;
        }
        const property_name = try self.allocator.dupe(u8, token.data.ident);
        errdefer self.allocator.free(property_name);
        try self.advance();

        // 期望 ':'
        try self.expectDelim(':');

        // 解析值
        const value = try self.parseValue();

        // 检查!important
        var important = false;
        if (self.current_token) |t| {
            if (t.token_type == .delim and t.data.delim == '!') {
                try self.advance();
                // 跳过空白（限制循环次数防止死循环）
                var whitespace_count: u32 = 0;
                while (self.current_token) |tok| {
                    if (whitespace_count > 100) break; // 防止死循环
                    if (tok.token_type == .whitespace) {
                        try self.advance();
                        whitespace_count += 1;
                    } else {
                        break;
                    }
                }
                // 检查important关键字
                if (self.current_token) |tok| {
                    if (tok.token_type == .ident and std.mem.eql(u8, tok.data.ident, "important")) {
                        important = true;
                        try self.advance();
                    }
                }
            }
        }

        return Declaration{
            .name = property_name,
            .value = value,
            .important = important,
            .allocator = self.allocator,
        };
    }

    /// 解析值
    fn parseValue(self: *Self) !Value {
        const token = self.current_token orelse return error.UnexpectedEof;

        switch (token.token_type) {
            .ident => {
                const ident = token.data.ident;
                try self.advance();
                return Value{
                    .keyword = try self.allocator.dupe(u8, ident),
                };
            },
            .number => {
                const num = token.data.number;
                try self.advance();
                // 检查是否有单位
                if (self.current_token) |t| {
                    if (t.token_type == .ident) {
                        const unit = try self.allocator.dupe(u8, t.data.ident);
                        try self.advance();
                        return Value{
                            .length = .{
                                .value = num,
                                .unit = unit,
                            },
                        };
                    }
                }
                return Value{ .keyword = try self.allocator.dupe(u8, try std.fmt.allocPrint(self.allocator, "{d}", .{num})) };
            },
            .dimension => {
                const dim = token.data.dimension;
                try self.advance();
                return Value{
                    .length = .{
                        .value = dim.value,
                        .unit = dim.unit,
                    },
                };
            },
            .percentage => {
                const pct = token.data.percentage;
                try self.advance();
                return Value{ .percentage = pct };
            },
            .hash => {
                // 解析颜色
                const hash = token.data.hash;
                try self.advance();
                const color = try self.parseColor(hash);
                return Value{ .color = color };
            },
            else => {
                // 尝试解析为关键字
                if (token.token_type == .delim) {
                    const delim = token.data.delim;
                    try self.advance();
                    const keyword = try std.fmt.allocPrint(self.allocator, "{c}", .{delim});
                    return Value{ .keyword = keyword };
                }
                return error.InvalidValue;
            },
        }
    }

    /// 解析颜色值
    fn parseColor(self: *Self, hash: []const u8) !Value.Color {
        _ = self;
        // 解析#rrggbb或#rgb格式
        if (hash.len == 3) {
            // #rgb格式
            const r = try std.fmt.parseInt(u8, &[_]u8{ hash[0], hash[0] }, 16);
            const g = try std.fmt.parseInt(u8, &[_]u8{ hash[1], hash[1] }, 16);
            const b = try std.fmt.parseInt(u8, &[_]u8{ hash[2], hash[2] }, 16);
            return Value.Color{ .r = r, .g = g, .b = b };
        } else if (hash.len == 6) {
            // #rrggbb格式
            const r = try std.fmt.parseInt(u8, hash[0..2], 16);
            const g = try std.fmt.parseInt(u8, hash[2..4], 16);
            const b = try std.fmt.parseInt(u8, hash[4..6], 16);
            return Value.Color{ .r = r, .g = g, .b = b };
        }
        return error.InvalidColor;
    }

    /// 前进到下一个token
    fn advance(self: *Self) !void {
        if (self.current_token) |*token| {
            token.deinit(self.allocator);
        }
        self.current_token = try self.tokenizer.next();
    }

    /// 期望特定的分隔符
    fn expectDelim(self: *Self, expected: u8) !void {
        const token = self.current_token orelse return error.UnexpectedEof;
        if (token.token_type != .delim or token.data.delim != expected) {
            return error.UnexpectedToken;
        }
        try self.advance();
    }
};
