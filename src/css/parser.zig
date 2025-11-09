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
        // 释放 name（在 Rule 中使用时）
        self.allocator.free(self.name);
        // 释放 value
        self.value.deinit(self.allocator);
    }

    /// 只释放 value，不释放 name（用于 HashMap 中，name 是 key）
    pub fn deinitValueOnly(self: *Declaration) void {
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
        self.selectors.deinit(self.allocator);
        for (self.declarations.items) |*decl| {
            decl.deinit();
        }
        self.declarations.deinit(self.allocator);
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
        self.rules.deinit(self.allocator);
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
            self.current_token = null;
        }
    }

    /// 解析样式表
    pub fn parse(self: *Self) !Stylesheet {
        var stylesheet = Stylesheet{
            .rules = std.ArrayList(Rule){},
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
                        try stylesheet.rules.append(self.allocator, rule);
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
        var selectors = std.ArrayList(selector.Selector){};
        errdefer {
            for (selectors.items) |*sel| {
                sel.deinit();
            }
            selectors.deinit(self.allocator);
        }

        var sel = try self.parseSelector();
        try selectors.append(self.allocator, sel);

        // 解析逗号分隔的选择器
        while (self.current_token) |token| {
            if (token.token_type == .delim and token.data.delim == ',') {
                try self.advance();
                sel = try self.parseSelector();
                try selectors.append(self.allocator, sel);
            } else {
                break;
            }
        }

        // 期望 '{'
        try self.expectDelim('{');

        // 解析声明列表
        var declarations = std.ArrayList(Declaration){};
        errdefer {
            for (declarations.items) |*decl| {
                decl.deinit();
            }
            declarations.deinit(self.allocator);
        }

        while (self.current_token) |token| {
            if (token.token_type == .delim and token.data.delim == '}') {
                try self.advance();
                break;
            }

            // 跳过分号
            if (token.token_type == .delim and token.data.delim == ';') {
                try self.advance();
                continue;
            }

            if (token.token_type == .eof) {
                break;
            }

            // 解析声明
            if (self.parseDeclaration()) |decl| {
                try declarations.append(self.allocator, decl);
            } else |_| {
                // 解析错误，跳过到下一个分号或右大括号
                while (self.current_token) |t| {
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

        const first_sequence = try self.parseSelectorSequence();
        try sel.sequences.append(self.allocator, first_sequence);

        // 解析组合器和后续序列
        // 注意：对于后代选择器（空白分隔），应该添加到同一个序列中
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
                // 显式组合器：创建新序列
                const next_sequence = try self.parseSelectorSequence();
                // 先 append，再获取前一个序列的引用（避免引用失效）
                const prev_idx = sel.sequences.items.len;
                try sel.sequences.append(self.allocator, next_sequence);
                // 将组合器添加到前一个序列
                var prev_sequence = &sel.sequences.items[prev_idx - 1];
                try prev_sequence.combinators.append(self.allocator, combinator);
            } else {
                // 没有显式组合器，检查是否是后代选择器（空白分隔）
                // 后代选择器：添加到当前序列
                if (self.canStartSimpleSelector()) {
                    // 获取当前序列（最后一个）
                    const sequence_idx = sel.sequences.items.len - 1;
                    var sequence = &sel.sequences.items[sequence_idx];
                    // 添加后代组合器到当前序列（在选择器之间）
                    try sequence.combinators.append(self.allocator, .descendant);
                    // 解析下一个选择器序列，但将其选择器添加到当前序列
                    var next_sequence = try self.parseSelectorSequence();
                    // 将下一个序列的选择器添加到当前序列
                    for (next_sequence.selectors.items) |simple_sel| {
                        try sequence.selectors.append(self.allocator, simple_sel);
                    }
                    // 清理下一个序列（选择器已移动，但需要清理空的ArrayList）
                    next_sequence.selectors.deinit(self.allocator);
                    next_sequence.combinators.deinit(self.allocator);
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
            try sequence.selectors.append(self.allocator, simple_sel);
        } else |_| {
            return error.InvalidSelector;
        }

        // 继续解析更多简单选择器（如 div.container#id）
        // 注意：这里只解析同一序列中的选择器（如 div.container#id），不处理组合器
        // 组合器（包括后代选择器）在 parseSelector 中处理
        // 如果下一个token是delim（.、#、*），是同一序列的选择器
        // 如果下一个token是ident或hash，可能是后代选择器，停止让 parseSelector 处理
        while (self.current_token) |t| {
            if (t.token_type == .delim) {
                const delim = t.data.delim;
                // 如果是 . 或 # 或 *，是同一序列的选择器，继续解析
                if (delim == '.' or delim == '#' or delim == '*') {
                    // 继续解析同一序列的选择器
                } else {
                    // 其他分隔符（,、{、}、>、+、~等），停止
                    break;
                }
            } else if (t.token_type == .ident or t.token_type == .hash) {
                // ident 或 hash 可能是后代选择器，停止让 parseSelector 处理
                break;
            } else {
                // 其他类型，停止
                break;
            }
            if (t.token_type == .eof) {
                break;
            }

            // 尝试解析更多简单选择器（同一序列中的，如 .container 或 #id）
            if (self.parseSimpleSelector()) |simple_sel| {
                try sequence.selectors.append(self.allocator, simple_sel);
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
                // 先复制，再advance（advance会释放token）
                const ident_copy = try self.allocator.dupe(u8, ident);
                try self.advance();
                return selector.SimpleSelector{
                    .selector_type = .type,
                    .value = ident_copy,
                    .allocator = self.allocator,
                };
            },
            .hash => {
                const hash = token.data.hash;
                // 先复制，再advance（advance会释放token）
                const hash_copy = try self.allocator.dupe(u8, hash);
                try self.advance();
                return selector.SimpleSelector{
                    .selector_type = .id,
                    .value = hash_copy,
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
                        // 先复制，再advance（advance会释放token）
                        const ident_copy = try self.allocator.dupe(u8, ident);
                        try self.advance();
                        return selector.SimpleSelector{
                            .selector_type = .class,
                            .value = ident_copy,
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

        // 解析值（支持多值属性，如 border: 2px solid #2196f3）
        const value = try self.parseValueList();

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

    /// 解析值列表（支持多值属性，如 border: 2px solid #2196f3）
    /// 解析整个值列表，直到遇到分号或右大括号
    fn parseValueList(self: *Self) !Value {
        // 记录开始位置（用于提取原始字符串）
        const start_pos = self.tokenizer.pos;
        
        // 收集所有token的字符串表示，直到遇到分号、右大括号或!important
        var value_parts = std.ArrayList([]const u8){};
        defer {
            for (value_parts.items) |part| {
                self.allocator.free(part);
            }
            value_parts.deinit(self.allocator);
        }
        
        var token_count: usize = 0;
        var end_pos: ?usize = null;
        
        // 收集所有token，直到遇到分号、右大括号或!important
        while (self.current_token) |token| {
            // 如果遇到分号或右大括号，停止
            if (token.token_type == .delim) {
                const delim = token.data.delim;
                if (delim == ';' or delim == '}') {
                    end_pos = self.tokenizer.pos;
                    break;
                }
                // 如果遇到!，可能是!important，停止
                if (delim == '!') {
                    end_pos = self.tokenizer.pos;
                    break;
                }
            }
            // 如果遇到EOF，停止
            if (token.token_type == .eof) {
                end_pos = self.tokenizer.pos;
                break;
            }
            
            // 跳过空白token（但保留在组合字符串中）
            if (token.token_type == .whitespace) {
                try self.advance();
                continue;
            }
            
            // 将token转换为字符串表示
            const token_str = try self.tokenToString(token);
            try value_parts.append(self.allocator, token_str);
            token_count += 1;
            
            // 前进到下一个token
            try self.advance();
        }
        
        // 如果只有一个token，尝试解析为单个值
        if (token_count == 1) {
            // 回退到开始位置，使用parseValue解析
            self.tokenizer.pos = start_pos;
            if (self.current_token) |*token| {
                token.deinit(self.allocator);
            }
            self.current_token = try self.tokenizer.next();
            return try self.parseValue();
        }
        
        // 如果有多个token，组合成关键字字符串
        if (token_count > 1) {
            // 使用收集的token字符串组合
            var result = std.ArrayList(u8){};
            defer result.deinit(self.allocator);
            result.ensureTotalCapacity(self.allocator, 100) catch {};
            
            for (value_parts.items, 0..) |part, i| {
                if (i > 0) {
                    try result.writer(self.allocator).writeAll(" ");
                }
                try result.writer(self.allocator).writeAll(part);
            }
            
            const keyword = try result.toOwnedSlice(self.allocator);
            std.log.debug("[Parser] parseValueList: parsed multi-value property = '{s}' (token_count={d})", .{ keyword, token_count });
            return Value{ .keyword = keyword };
        }
        
        return error.InvalidValue;
    }

    /// 将token转换为字符串表示（用于组合多值属性）
    fn tokenToString(self: *Self, token: tokenizer.Token) ![]const u8 {
        return switch (token.token_type) {
            .ident => try self.allocator.dupe(u8, token.data.ident),
            .string => {
                const str = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{token.data.string});
                return str;
            },
            .number => {
                const str = try std.fmt.allocPrint(self.allocator, "{d}", .{token.data.number});
                return str;
            },
            .dimension => {
                const str = try std.fmt.allocPrint(self.allocator, "{d}{s}", .{ token.data.dimension.value, token.data.dimension.unit });
                return str;
            },
            .percentage => {
                const str = try std.fmt.allocPrint(self.allocator, "{d}%", .{token.data.percentage});
                return str;
            },
            .hash => {
                const str = try std.fmt.allocPrint(self.allocator, "#{s}", .{token.data.hash});
                return str;
            },
            .delim => {
                const str = try std.fmt.allocPrint(self.allocator, "{c}", .{token.data.delim});
                return str;
            },
            .whitespace => try self.allocator.dupe(u8, " "),
            else => return error.UnsupportedTokenType,
        };
    }

    /// 解析值
    fn parseValue(self: *Self) !Value {
        const token = self.current_token orelse return error.UnexpectedEof;

        switch (token.token_type) {
            .ident => {
                const ident = token.data.ident;
                // 先复制，再advance（advance会释放token）
                const ident_copy = try self.allocator.dupe(u8, ident);
                try self.advance();
                return Value{
                    .keyword = ident_copy,
                };
            },
            .number => {
                const num = token.data.number;
                try self.advance();
                // 检查是否有单位
                if (self.current_token) |t| {
                    if (t.token_type == .ident) {
                        // 先复制，再advance（advance会释放token）
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
                const num_str = try std.fmt.allocPrint(self.allocator, "{d}", .{num});
                errdefer self.allocator.free(num_str);
                const keyword = try self.allocator.dupe(u8, num_str);
                self.allocator.free(num_str); // 释放临时字符串
                return Value{ .keyword = keyword };
            },
            .dimension => {
                const dim = token.data.dimension;
                // 先复制unit，再advance（advance会释放token）
                const unit_copy = try self.allocator.dupe(u8, dim.unit);
                try self.advance();
                return Value{
                    .length = .{
                        .value = dim.value,
                        .unit = unit_copy,
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
                // 先复制，再advance（advance会释放token）
                const hash_copy = try self.allocator.dupe(u8, hash);
                try self.advance();
                const color = try self.parseColor(hash_copy);
                self.allocator.free(hash_copy);
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
            self.current_token = null;
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
