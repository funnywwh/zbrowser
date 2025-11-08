const std = @import("std");
const tokenizer = @import("tokenizer");
const selector = @import("selector");
const parser = @import("parser");

/// LR 解析错误
pub const ParseError = error{
    InvalidToken,
    InvalidProduction,
    InvalidReduce,
    InvalidAccept,
    ParseTimeout,
    InvalidColor,
};

/// CSS LR 解析器
/// 使用 comptime 生成解析表，提升性能
pub const LRParser = struct {
    tokenizer: tokenizer.Tokenizer,
    allocator: std.mem.Allocator,
    state_stack: std.ArrayList(usize),
    symbol_stack: std.ArrayList(Symbol),
    current_token: ?tokenizer.Token = null,

    const Self = @This();

    /// 符号类型（终结符和非终结符）
    pub const SymbolType = enum {
        // 终结符
        T_IDENT,
        T_STRING,
        T_NUMBER,
        T_PERCENTAGE,
        T_DIMENSION,
        T_HASH,
        T_FUNCTION,
        T_AT_KEYWORD,
        T_DELIM,
        T_WHITESPACE,
        T_COMMENT,
        T_EOF,

        // 非终结符
        N_STYLESHEET,
        N_RULE,
        N_SELECTOR_LIST,
        N_SELECTOR,
        N_SELECTOR_SEQUENCE,
        N_SIMPLE_SELECTOR,
        N_COMBINATOR,
        N_DECLARATION_LIST,
        N_DECLARATION,
        N_PROPERTY,
        N_VALUE,
    };

    /// 符号
    pub const Symbol = struct {
        symbol_type: SymbolType,
        data: Data,

        /// 释放符号资源
        pub fn deinit(self: Symbol, allocator: std.mem.Allocator) void {
            var self_mut = self; // 创建可变副本
            switch (self_mut.symbol_type) {
                .T_IDENT => allocator.free(self_mut.data.ident),
                .T_STRING => allocator.free(self_mut.data.string),
                .T_DIMENSION => self_mut.data.dimension.deinit(allocator),
                .T_HASH => allocator.free(self_mut.data.hash),
                .T_FUNCTION => allocator.free(self_mut.data.function),
                .T_AT_KEYWORD => allocator.free(self_mut.data.at_keyword),
                .T_COMMENT => allocator.free(self_mut.data.comment),
                .N_STYLESHEET => self_mut.data.stylesheet.deinit(),
                .N_RULE => self_mut.data.rule.deinit(allocator),
                .N_SELECTOR_LIST => {
                    for (self_mut.data.selector_list.items) |*sel| {
                        sel.deinit();
                    }
                    self_mut.data.selector_list.deinit();
                },
                .N_SELECTOR => self_mut.data.selector.deinit(),
                .N_SELECTOR_SEQUENCE => self_mut.data.selector_sequence.deinit(),
                .N_SIMPLE_SELECTOR => self_mut.data.simple_selector.deinit(),
                .N_DECLARATION_LIST => {
                    for (self_mut.data.declaration_list.items) |*decl| {
                        decl.deinit(allocator);
                    }
                    self_mut.data.declaration_list.deinit();
                },
                .N_DECLARATION => self_mut.data.declaration.deinit(allocator),
                .N_PROPERTY => allocator.free(self_mut.data.property),
                .N_VALUE => self_mut.data.value.deinit(allocator),
                else => {},
            }
        }

        pub const Data = union {
            // 终结符数据
            ident: []const u8,
            string: []const u8,
            number: f32,
            percentage: f32,
            dimension: tokenizer.Token.DimensionData,
            hash: []const u8,
            function: []const u8,
            at_keyword: []const u8,
            delim: u8,
            whitespace: void,
            comment: []const u8,
            eof: void,

            // 非终结符数据（解析结果）
            stylesheet: parser.Stylesheet,
            rule: parser.Rule,
            selector_list: std.ArrayList(selector.Selector),
            selector: selector.Selector,
            selector_sequence: selector.SelectorSequence,
            simple_selector: selector.SimpleSelector,
            combinator: selector.Combinator,
            declaration_list: std.ArrayList(parser.Declaration),
            declaration: parser.Declaration,
            property: []const u8,
            value: parser.Value,
        };
    };

    /// 解析动作
    pub const Action = enum {
        shift,
        reduce,
        accept,
        parse_error,
    };

    /// 解析动作详情
    const ParseAction = union(Action) {
        shift: usize, // 转移到状态
        reduce: usize, // 归约规则编号
        accept: void, // 接受
        parse_error: void, // 错误
    };

    /// 语法规则
    const Production = struct {
        lhs: SymbolType, // 左部（非终结符）
        rhs: []const SymbolType, // 右部（符号序列）
        action: fn (allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol, // 归约动作
    };

    /// 语法规则定义
    const productions = [_]Production{
        // 0: stylesheet -> rule*
        .{
            .lhs = .N_STYLESHEET,
            .rhs = &[_]SymbolType{.N_RULE},
            .action = reduceStylesheet,
        },
        // 1: rule -> selector_list '{' declaration_list '}'
        .{
            .lhs = .N_RULE,
            .rhs = &[_]SymbolType{ .N_SELECTOR_LIST, .T_DELIM, .N_DECLARATION_LIST, .T_DELIM },
            .action = reduceRule,
        },
        // 2: selector_list -> selector
        .{
            .lhs = .N_SELECTOR_LIST,
            .rhs = &[_]SymbolType{.N_SELECTOR},
            .action = reduceSelectorList,
        },
        // 3: selector_list -> selector_list ',' selector
        .{
            .lhs = .N_SELECTOR_LIST,
            .rhs = &[_]SymbolType{ .N_SELECTOR_LIST, .T_DELIM, .N_SELECTOR },
            .action = reduceSelectorListAppend,
        },
        // 4: selector -> selector_sequence
        .{
            .lhs = .N_SELECTOR,
            .rhs = &[_]SymbolType{.N_SELECTOR_SEQUENCE},
            .action = reduceSelector,
        },
        // 5: selector -> selector combinator selector_sequence
        .{
            .lhs = .N_SELECTOR,
            .rhs = &[_]SymbolType{ .N_SELECTOR, .N_COMBINATOR, .N_SELECTOR_SEQUENCE },
            .action = reduceSelectorWithCombinator,
        },
        // 6: selector_sequence -> simple_selector
        .{
            .lhs = .N_SELECTOR_SEQUENCE,
            .rhs = &[_]SymbolType{.N_SIMPLE_SELECTOR},
            .action = reduceSelectorSequence,
        },
        // 7: selector_sequence -> selector_sequence simple_selector
        .{
            .lhs = .N_SELECTOR_SEQUENCE,
            .rhs = &[_]SymbolType{ .N_SELECTOR_SEQUENCE, .N_SIMPLE_SELECTOR },
            .action = reduceSelectorSequenceAppend,
        },
        // 8: simple_selector -> T_IDENT (type selector)
        .{
            .lhs = .N_SIMPLE_SELECTOR,
            .rhs = &[_]SymbolType{.T_IDENT},
            .action = reduceSimpleSelectorType,
        },
        // 9: simple_selector -> T_HASH (id selector)
        .{
            .lhs = .N_SIMPLE_SELECTOR,
            .rhs = &[_]SymbolType{.T_HASH},
            .action = reduceSimpleSelectorId,
        },
        // 10: combinator -> T_WHITESPACE (descendant)
        .{
            .lhs = .N_COMBINATOR,
            .rhs = &[_]SymbolType{.T_WHITESPACE},
            .action = reduceCombinatorDescendant,
        },
        // 11: combinator -> '>'
        .{
            .lhs = .N_COMBINATOR,
            .rhs = &[_]SymbolType{.T_DELIM},
            .action = reduceCombinatorChild,
        },
        // 12: declaration_list -> declaration
        .{
            .lhs = .N_DECLARATION_LIST,
            .rhs = &[_]SymbolType{.N_DECLARATION},
            .action = reduceDeclarationList,
        },
        // 13: declaration_list -> declaration_list ';' declaration
        .{
            .lhs = .N_DECLARATION_LIST,
            .rhs = &[_]SymbolType{ .N_DECLARATION_LIST, .T_DELIM, .N_DECLARATION },
            .action = reduceDeclarationListAppend,
        },
        // 14: declaration -> property ':' value
        .{
            .lhs = .N_DECLARATION,
            .rhs = &[_]SymbolType{ .N_PROPERTY, .T_DELIM, .N_VALUE },
            .action = reduceDeclaration,
        },
        // 15: property -> T_IDENT
        .{
            .lhs = .N_PROPERTY,
            .rhs = &[_]SymbolType{.T_IDENT},
            .action = reduceProperty,
        },
        // 16: value -> T_IDENT (keyword)
        .{
            .lhs = .N_VALUE,
            .rhs = &[_]SymbolType{.T_IDENT},
            .action = reduceValueKeyword,
        },
        // 17: value -> T_NUMBER
        .{
            .lhs = .N_VALUE,
            .rhs = &[_]SymbolType{.T_NUMBER},
            .action = reduceValueNumber,
        },
        // 18: value -> T_STRING
        .{
            .lhs = .N_VALUE,
            .rhs = &[_]SymbolType{.T_STRING},
            .action = reduceValueString,
        },
        // 19: value -> T_HASH (color)
        .{
            .lhs = .N_VALUE,
            .rhs = &[_]SymbolType{.T_HASH},
            .action = reduceValueColor,
        },
    };

    /// 归约动作函数
    fn reduceStylesheet(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // stylesheet -> rule
        std.debug.assert(symbols.len == 1);
        const rule_sym = symbols[0];
        std.debug.assert(rule_sym.symbol_type == .N_RULE);

        var stylesheet = parser.Stylesheet.init(allocator);
        try stylesheet.rules.append(rule_sym.data.rule);

        return Symbol{
            .symbol_type = .N_STYLESHEET,
            .data = .{ .stylesheet = stylesheet },
        };
    }

    fn reduceRule(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // rule -> selector_list '{' declaration_list '}'
        std.debug.assert(symbols.len == 4);
        const selector_list_sym = symbols[0];
        const delim1 = symbols[1]; // '{'
        const declaration_list_sym = symbols[2];
        const delim2 = symbols[3]; // '}'

        _ = delim1;
        _ = delim2;

        std.debug.assert(selector_list_sym.symbol_type == .N_SELECTOR_LIST);
        std.debug.assert(declaration_list_sym.symbol_type == .N_DECLARATION_LIST);

        var rule = parser.Rule.init(allocator);
        // 复制选择器列表
        for (selector_list_sym.data.selector_list.items) |sel| {
            try rule.selectors.append(sel);
        }
        // 复制声明列表
        for (declaration_list_sym.data.declaration_list.items) |decl| {
            try rule.declarations.append(decl);
        }

        return Symbol{
            .symbol_type = .N_RULE,
            .data = .{ .rule = rule },
        };
    }

    fn reduceSelectorList(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // selector_list -> selector
        std.debug.assert(symbols.len == 1);
        const selector_sym = symbols[0];
        std.debug.assert(selector_sym.symbol_type == .N_SELECTOR);

        var selector_list = std.ArrayList(selector.Selector).init(allocator);
        try selector_list.append(selector_sym.data.selector);

        return Symbol{
            .symbol_type = .N_SELECTOR_LIST,
            .data = .{ .selector_list = selector_list },
        };
    }

    fn reduceSelectorListAppend(_: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // selector_list -> selector_list ',' selector
        std.debug.assert(symbols.len == 3);
        const selector_list_sym = symbols[0];
        const delim = symbols[1]; // ','
        const selector_sym = symbols[2];

        _ = delim;

        std.debug.assert(selector_list_sym.symbol_type == .N_SELECTOR_LIST);
        std.debug.assert(selector_sym.symbol_type == .N_SELECTOR);

        var selector_list = selector_list_sym.data.selector_list;
        try selector_list.append(selector_sym.data.selector);

        return Symbol{
            .symbol_type = .N_SELECTOR_LIST,
            .data = .{ .selector_list = selector_list },
        };
    }

    fn reduceSelector(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // selector -> selector_sequence
        std.debug.assert(symbols.len == 1);
        const sequence_sym = symbols[0];
        std.debug.assert(sequence_sym.symbol_type == .N_SELECTOR_SEQUENCE);

        var sel = selector.Selector.init(allocator);
        try sel.sequences.append(sequence_sym.data.selector_sequence);

        return Symbol{
            .symbol_type = .N_SELECTOR,
            .data = .{ .selector = sel },
        };
    }

    fn reduceSelectorWithCombinator(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // selector -> selector combinator selector_sequence
        std.debug.assert(symbols.len == 3);
        const selector_sym = symbols[0];
        const combinator_sym = symbols[1];
        const sequence_sym = symbols[2];

        std.debug.assert(selector_sym.symbol_type == .N_SELECTOR);
        std.debug.assert(combinator_sym.symbol_type == .N_COMBINATOR);
        std.debug.assert(sequence_sym.symbol_type == .N_SELECTOR_SEQUENCE);

        var sel = selector_sym.data.selector;
        const comb = combinator_sym.data.combinator;
        const seq = sequence_sym.data.selector_sequence;

        // 将组合器和序列添加到最后一个序列
        if (sel.sequences.items.len > 0) {
            const last_seq = &sel.sequences.items[sel.sequences.items.len - 1];
            try last_seq.combinators.append(comb);
            // 将新序列的选择器添加到当前序列
            for (seq.selectors.items) |simple_sel| {
                const simple_sel_copy = selector.SimpleSelector{
                    .selector_type = simple_sel.selector_type,
                    .value = try allocator.dupe(u8, simple_sel.value),
                    .attribute_name = if (simple_sel.attribute_name) |name|
                        try allocator.dupe(u8, name)
                    else
                        null,
                    .attribute_value = if (simple_sel.attribute_value) |val|
                        try allocator.dupe(u8, val)
                    else
                        null,
                    .attribute_match = simple_sel.attribute_match,
                    .allocator = allocator,
                };
                try last_seq.selectors.append(simple_sel_copy);
            }
        }

        return Symbol{
            .symbol_type = .N_SELECTOR,
            .data = .{ .selector = sel },
        };
    }

    fn reduceSelectorSequence(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // selector_sequence -> simple_selector
        std.debug.assert(symbols.len == 1);
        const simple_sym = symbols[0];
        std.debug.assert(simple_sym.symbol_type == .N_SIMPLE_SELECTOR);

        var sequence = selector.SelectorSequence.init(allocator);
        try sequence.selectors.append(simple_sym.data.simple_selector);

        return Symbol{
            .symbol_type = .N_SELECTOR_SEQUENCE,
            .data = .{ .selector_sequence = sequence },
        };
    }

    fn reduceSelectorSequenceAppend(_: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // selector_sequence -> selector_sequence simple_selector
        std.debug.assert(symbols.len == 2);
        const sequence_sym = symbols[0];
        const simple_sym = symbols[1];

        std.debug.assert(sequence_sym.symbol_type == .N_SELECTOR_SEQUENCE);
        std.debug.assert(simple_sym.symbol_type == .N_SIMPLE_SELECTOR);

        var sequence = sequence_sym.data.selector_sequence;
        try sequence.selectors.append(simple_sym.data.simple_selector);

        return Symbol{
            .symbol_type = .N_SELECTOR_SEQUENCE,
            .data = .{ .selector_sequence = sequence },
        };
    }

    fn reduceSimpleSelectorType(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // simple_selector -> T_IDENT (type selector)
        std.debug.assert(symbols.len == 1);
        const ident_sym = symbols[0];
        std.debug.assert(ident_sym.symbol_type == .T_IDENT);

        const simple_sel = selector.SimpleSelector{
            .selector_type = .type,
            .value = try allocator.dupe(u8, ident_sym.data.ident),
            .allocator = allocator,
        };

        return Symbol{
            .symbol_type = .N_SIMPLE_SELECTOR,
            .data = .{ .simple_selector = simple_sel },
        };
    }

    fn reduceSimpleSelectorId(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // simple_selector -> T_HASH (id selector)
        std.debug.assert(symbols.len == 1);
        const hash_sym = symbols[0];
        std.debug.assert(hash_sym.symbol_type == .T_HASH);

        const simple_sel = selector.SimpleSelector{
            .selector_type = .id,
            .value = try allocator.dupe(u8, hash_sym.data.hash),
            .allocator = allocator,
        };

        return Symbol{
            .symbol_type = .N_SIMPLE_SELECTOR,
            .data = .{ .simple_selector = simple_sel },
        };
    }

    fn reduceCombinatorDescendant(_: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // combinator -> T_WHITESPACE (descendant)
        std.debug.assert(symbols.len == 1);
        std.debug.assert(symbols[0].symbol_type == .T_WHITESPACE);

        return Symbol{
            .symbol_type = .N_COMBINATOR,
            .data = .{ .combinator = .descendant },
        };
    }

    fn reduceCombinatorChild(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // combinator -> '>'
        _ = allocator;
        std.debug.assert(symbols.len == 1);
        const delim_sym = symbols[0];
        std.debug.assert(delim_sym.symbol_type == .T_DELIM);
        std.debug.assert(delim_sym.data.delim == '>');

        return Symbol{
            .symbol_type = .N_COMBINATOR,
            .data = .{ .combinator = .child },
        };
    }

    fn reduceDeclarationList(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // declaration_list -> declaration
        std.debug.assert(symbols.len == 1);
        const decl_sym = symbols[0];
        std.debug.assert(decl_sym.symbol_type == .N_DECLARATION);

        var decl_list = std.ArrayList(parser.Declaration).init(allocator);
        try decl_list.append(decl_sym.data.declaration);

        return Symbol{
            .symbol_type = .N_DECLARATION_LIST,
            .data = .{ .declaration_list = decl_list },
        };
    }

    fn reduceDeclarationListAppend(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // declaration_list -> declaration_list ';' declaration
        _ = allocator;
        std.debug.assert(symbols.len == 3);
        const decl_list_sym = symbols[0];
        const delim = symbols[1]; // ';'
        const decl_sym = symbols[2];

        _ = delim;

        std.debug.assert(decl_list_sym.symbol_type == .N_DECLARATION_LIST);
        std.debug.assert(decl_sym.symbol_type == .N_DECLARATION);

        var decl_list = decl_list_sym.data.declaration_list;
        try decl_list.append(decl_sym.data.declaration);

        return Symbol{
            .symbol_type = .N_DECLARATION_LIST,
            .data = .{ .declaration_list = decl_list },
        };
    }

    fn reduceDeclaration(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // declaration -> property ':' value
        std.debug.assert(symbols.len == 3);
        const prop_sym = symbols[0];
        const delim = symbols[1]; // ':'
        const value_sym = symbols[2];

        _ = delim;

        std.debug.assert(prop_sym.symbol_type == .N_PROPERTY);
        std.debug.assert(value_sym.symbol_type == .N_VALUE);

        const name = prop_sym.data.property;
        const value = value_sym.data.value;
        const decl = try parser.Declaration.init(allocator, name, value, false);

        return Symbol{
            .symbol_type = .N_DECLARATION,
            .data = .{ .declaration = decl },
        };
    }

    fn reduceProperty(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // property -> T_IDENT
        std.debug.assert(symbols.len == 1);
        const ident_sym = symbols[0];
        std.debug.assert(ident_sym.symbol_type == .T_IDENT);

        const name = try allocator.dupe(u8, ident_sym.data.ident);

        return Symbol{
            .symbol_type = .N_PROPERTY,
            .data = .{ .property = name },
        };
    }

    fn reduceValueKeyword(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // value -> T_IDENT (keyword)
        std.debug.assert(symbols.len == 1);
        const ident_sym = symbols[0];
        std.debug.assert(ident_sym.symbol_type == .T_IDENT);

        const keyword = try allocator.dupe(u8, ident_sym.data.ident);
        const value = parser.Value{ .keyword = keyword };

        return Symbol{
            .symbol_type = .N_VALUE,
            .data = .{ .value = value },
        };
    }

    fn reduceValueNumber(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // value -> T_NUMBER
        _ = allocator;
        std.debug.assert(symbols.len == 1);
        const number_sym = symbols[0];
        std.debug.assert(number_sym.symbol_type == .T_NUMBER);

        const value = parser.Value{ .number = number_sym.data.number };

        return Symbol{
            .symbol_type = .N_VALUE,
            .data = .{ .value = value },
        };
    }

    fn reduceValueString(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // value -> T_STRING
        std.debug.assert(symbols.len == 1);
        const string_sym = symbols[0];
        std.debug.assert(string_sym.symbol_type == .T_STRING);

        const str = try allocator.dupe(u8, string_sym.data.string);
        const value = parser.Value{ .string = str };

        return Symbol{
            .symbol_type = .N_VALUE,
            .data = .{ .value = value },
        };
    }

    fn reduceValueColor(allocator: std.mem.Allocator, symbols: []const Symbol) anyerror!Symbol {
        // value -> T_HASH (color)
        std.debug.assert(symbols.len == 1);
        const hash_sym = symbols[0];
        std.debug.assert(hash_sym.symbol_type == .T_HASH);

        // 解析颜色（简化实现，只支持 #RGB 和 #RRGGBB）
        const hash = hash_sym.data.hash;
        const color = try parseColor(allocator, hash);
        const value = parser.Value{ .color = color };

        return Symbol{
            .symbol_type = .N_VALUE,
            .data = .{ .value = value },
        };
    }

    /// 解析颜色值
    fn parseColor(allocator: std.mem.Allocator, hash: []const u8) !parser.Color {
        _ = allocator;
        // 简化实现：只支持 #RGB 和 #RRGGBB
        if (hash.len == 3) {
            // #RGB
            const r = try std.fmt.parseInt(u8, &[_]u8{ hash[0], hash[0] }, 16);
            const g = try std.fmt.parseInt(u8, &[_]u8{ hash[1], hash[1] }, 16);
            const b = try std.fmt.parseInt(u8, &[_]u8{ hash[2], hash[2] }, 16);
            return parser.Color{ .r = r, .g = g, .b = b };
        } else if (hash.len == 6) {
            // #RRGGBB
            const r = try std.fmt.parseInt(u8, hash[0..2], 16);
            const g = try std.fmt.parseInt(u8, hash[2..4], 16);
            const b = try std.fmt.parseInt(u8, hash[4..6], 16);
            return parser.Color{ .r = r, .g = g, .b = b };
        } else {
            return error.InvalidColor;
        }
    }

    /// 初始化解析器
    pub fn init(input: []const u8, allocator: std.mem.Allocator) Self {
        return .{
            .tokenizer = tokenizer.Tokenizer.init(input, allocator),
            .allocator = allocator,
            .state_stack = std.ArrayList(usize).init(allocator),
            .symbol_stack = std.ArrayList(Symbol).init(allocator),
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        self.state_stack.deinit();
        // 释放符号栈中的资源
        for (self.symbol_stack.items) |*sym| {
            self.freeSymbol(sym);
        }
        self.symbol_stack.deinit();
        if (self.current_token) |token| {
            token.deinit();
        }
    }

    /// 释放符号
    fn freeSymbol(self: *Self, sym: *Symbol) void {
        switch (sym.symbol_type) {
            .T_IDENT => self.allocator.free(sym.data.ident),
            .T_STRING => self.allocator.free(sym.data.string),
            .T_DIMENSION => sym.data.dimension.deinit(self.allocator),
            .T_HASH => self.allocator.free(sym.data.hash),
            .T_FUNCTION => self.allocator.free(sym.data.function),
            .T_AT_KEYWORD => self.allocator.free(sym.data.at_keyword),
            .T_COMMENT => self.allocator.free(sym.data.comment),
            .N_STYLESHEET => sym.data.stylesheet.deinit(),
            .N_RULE => sym.data.rule.deinit(self.allocator),
            .N_SELECTOR_LIST => {
                for (sym.data.selector_list.items) |*sel| {
                    sel.deinit();
                }
                sym.data.selector_list.deinit();
            },
            .N_SELECTOR => sym.data.selector.deinit(),
            .N_SELECTOR_SEQUENCE => sym.data.selector_sequence.deinit(),
            .N_DECLARATION_LIST => {
                for (sym.data.declaration_list.items) |*decl| {
                    decl.deinit(self.allocator);
                }
                sym.data.declaration_list.deinit();
            },
            .N_DECLARATION => sym.data.declaration.deinit(self.allocator),
            .N_PROPERTY => self.allocator.free(sym.data.property),
            .N_VALUE => sym.data.value.deinit(self.allocator),
            else => {},
        }
    }

    /// 将 token 转换为符号
    /// 注意：需要复制所有需要分配内存的数据，因为 token 会被释放
    fn tokenToSymbol(self: *Self, token: tokenizer.Token) !Symbol {
        const symbol_type: SymbolType = switch (token.token_type) {
            .ident => .T_IDENT,
            .string => .T_STRING,
            .number => .T_NUMBER,
            .percentage => .T_PERCENTAGE,
            .dimension => .T_DIMENSION,
            .hash => .T_HASH,
            .function => .T_FUNCTION,
            .at_keyword => .T_AT_KEYWORD,
            .delim => .T_DELIM,
            .whitespace => .T_WHITESPACE,
            .comment => .T_COMMENT,
            .eof => .T_EOF,
            .url => return error.InvalidToken, // URL 暂不支持
        };

        const data: Symbol.Data = switch (token.token_type) {
            .ident => .{ .ident = try self.allocator.dupe(u8, token.data.ident) },
            .string => .{ .string = try self.allocator.dupe(u8, token.data.string) },
            .number => .{ .number = token.data.number },
            .percentage => .{ .percentage = token.data.percentage },
            .dimension => blk: {
                const unit_dup = try self.allocator.dupe(u8, token.data.dimension.unit);
                break :blk .{
                    .dimension = .{
                        .value = token.data.dimension.value,
                        .unit = unit_dup,
                    },
                };
            },
            .hash => .{ .hash = try self.allocator.dupe(u8, token.data.hash) },
            .function => .{ .function = try self.allocator.dupe(u8, token.data.function) },
            .at_keyword => .{ .at_keyword = try self.allocator.dupe(u8, token.data.at_keyword) },
            .delim => .{ .delim = token.data.delim },
            .whitespace => .{ .whitespace = {} },
            .comment => .{ .comment = try self.allocator.dupe(u8, token.data.comment) },
            .eof => .{ .eof = {} },
            .url => return error.InvalidToken, // URL 暂不支持
        };

        return Symbol{
            .symbol_type = symbol_type,
            .data = data,
        };
    }

    /// 获取下一个 token
    fn next(self: *Self) !?tokenizer.Token {
        if (self.current_token) |token| {
            self.current_token = null;
            return token;
        }
        return try self.tokenizer.next();
    }

    /// 查看下一个 token 但不消耗（peek）
    fn peek(self: *Self) !?tokenizer.Token {
        if (self.current_token) |token| {
            return token;
        }
        const token = try self.tokenizer.next();
        if (token) |t| {
            self.current_token = t;
        }
        return token;
    }

    /// 将 token 类型转换为符号类型
    fn tokenTypeToSymbolType(token_type: tokenizer.TokenType) ?SymbolType {
        return switch (token_type) {
            .ident => .T_IDENT,
            .string => .T_STRING,
            .number => .T_NUMBER,
            .percentage => .T_PERCENTAGE,
            .dimension => .T_DIMENSION,
            .hash => .T_HASH,
            .function => .T_FUNCTION,
            .at_keyword => .T_AT_KEYWORD,
            .delim => .T_DELIM,
            .whitespace => .T_WHITESPACE,
            .comment => .T_COMMENT,
            .eof => .T_EOF,
            .url => null, // URL 暂不支持
        };
    }

    /// LR 解析表常量定义
    const MAX_STATES = 30;
    const MAX_TERMINALS = 12; // 终结符数量
    const MAX_NON_TERMINALS = 11; // 非终结符数量

    /// LR 项目（Item）
    /// 表示语法规则的一个位置，例如 A -> α·β 表示已识别 α，期望 β
    const Item = struct {
        production_index: usize, // 规则编号
        dot_position: usize, // 点的位置（0 表示点在开头）

        /// 检查项目是否相等
        fn eql(self: Item, other: Item) bool {
            return self.production_index == other.production_index and
                self.dot_position == other.dot_position;
        }

        /// 获取点后的下一个符号
        fn nextSymbol(self: Item, prods: []const Production) ?SymbolType {
            const prod = prods[self.production_index];
            if (self.dot_position < prod.rhs.len) {
                return prod.rhs[self.dot_position];
            }
            return null; // 点在末尾
        }

        /// 检查是否可归约（点在末尾）
        fn isReducible(self: Item, prods: []const Production) bool {
            const prod = prods[self.production_index];
            return self.dot_position >= prod.rhs.len;
        }
    };

    /// LR 项目集（Item Set）
    /// 使用固定大小数组存储，避免动态分配
    const ItemSet = struct {
        items: [100]Item = undefined, // 最多 100 个项目
        count: usize = 0, // 实际项目数量

        /// 添加项目（如果不存在）
        fn addItem(self: *ItemSet, item: Item) bool {
            // 检查是否已存在
            for (self.items[0..self.count]) |existing| {
                if (existing.eql(item)) {
                    return false; // 已存在
                }
            }
            // 添加新项目
            if (self.count < self.items.len) {
                self.items[self.count] = item;
                self.count += 1;
                return true;
            }
            return false; // 数组已满
        }

        /// 计算闭包（Closure）
        /// CLOSURE(I) = I ∪ {B -> ·γ | A -> α·Bβ ∈ I, B -> γ 是规则}
        fn closure(self: *ItemSet, prods: []const Production) void {
            var changed = true;
            while (changed) {
                changed = false;
                var i: usize = 0;
                while (i < self.count) : (i += 1) {
                    const item = self.items[i];
                    if (item.nextSymbol(prods)) |next_sym| {
                        // 如果下一个符号是非终结符，添加所有以该非终结符为左部的规则
                        switch (next_sym) {
                            .N_STYLESHEET, .N_RULE, .N_SELECTOR_LIST, .N_SELECTOR, .N_SELECTOR_SEQUENCE, .N_SIMPLE_SELECTOR, .N_COMBINATOR, .N_DECLARATION_LIST, .N_DECLARATION, .N_PROPERTY, .N_VALUE => {
                                // 非终结符，添加所有相关规则
                                for (prods, 0..) |prod, prod_idx| {
                                    if (prod.lhs == next_sym) {
                                        const new_item = Item{
                                            .production_index = prod_idx,
                                            .dot_position = 0, // 点在开头
                                        };
                                        if (self.addItem(new_item)) {
                                            changed = true;
                                        }
                                    }
                                }
                            },
                            // 终结符，不需要添加
                            .T_IDENT, .T_STRING, .T_NUMBER, .T_PERCENTAGE, .T_DIMENSION, .T_HASH, .T_FUNCTION, .T_AT_KEYWORD, .T_DELIM, .T_WHITESPACE, .T_COMMENT, .T_EOF => {},
                        }
                    }
                }
            }
        }

        /// 计算 GOTO
        /// GOTO(I, X) = CLOSURE({A -> αX·β | A -> α·Xβ ∈ I})
        fn goto(self: *const ItemSet, symbol: SymbolType, prods: []const Production) ?ItemSet {
            var new_set = ItemSet{};

            // 对于 I 中的每个项目 A -> α·Xβ，如果 X == symbol，添加 A -> αX·β
            for (self.items[0..self.count]) |item| {
                if (item.nextSymbol(prods)) |next_sym| {
                    if (next_sym == symbol) {
                        const new_item = Item{
                            .production_index = item.production_index,
                            .dot_position = item.dot_position + 1,
                        };
                        _ = new_set.addItem(new_item);
                    }
                }
            }

            // 如果新集合为空，返回 null
            if (new_set.count == 0) {
                return null;
            }

            // 计算闭包
            new_set.closure(prods);

            return new_set;
        }

        /// 检查两个项目集是否相等
        fn eql(self: *const ItemSet, other: *const ItemSet) bool {
            if (self.count != other.count) {
                return false;
            }
            // 检查每个项目是否都在另一个集合中
            for (self.items[0..self.count]) |item| {
                var found = false;
                for (other.items[0..other.count]) |other_item| {
                    if (item.eql(other_item)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    return false;
                }
            }
            return true;
        }
    };

    /// 使用 comptime 生成 LR 解析表
    /// 返回：ACTION 表和 GOTO 表
    fn generateParseTables(prods: []const Production) struct {
        action_table: [MAX_STATES][MAX_TERMINALS]?ParseAction,
        goto_table: [MAX_STATES][MAX_NON_TERMINALS]?usize,
        num_states: usize,
    } {
        // 增加 comptime 分支配额（LR 算法需要大量分支）
        @setEvalBranchQuota(100000);
        // 初始化解析表
        var action_table: [MAX_STATES][MAX_TERMINALS]?ParseAction = undefined;
        var goto_table: [MAX_STATES][MAX_NON_TERMINALS]?usize = undefined;

        // 初始化所有表项为 null
        for (&action_table) |*row| {
            for (&row.*) |*cell| {
                cell.* = null;
            }
        }
        for (&goto_table) |*row| {
            for (&row.*) |*cell| {
                cell.* = null;
            }
        }

        // 实现 LR(0) 自动机构建算法（简化版本）
        // 注意：这是 LR(0) 算法，不是完整的 LR(1)，但对于大多数 CSS 语法足够

        // 1. 构建初始项目集
        // 假设第一个规则是开始规则（stylesheet -> rule）
        var initial_set = ItemSet{};
        if (prods.len > 0) {
            const start_item = Item{
                .production_index = 0, // stylesheet -> rule
                .dot_position = 0, // 点在开头
            };
            _ = initial_set.addItem(start_item);
            initial_set.closure(prods);
        }

        // 2. 状态集合
        var states: [MAX_STATES]ItemSet = undefined;
        var state_count: usize = 0;
        states[state_count] = initial_set;
        state_count += 1;

        // 3. 构建状态转换
        var state_idx: usize = 0;
        while (state_idx < state_count and state_idx < MAX_STATES) : (state_idx += 1) {
            const current_state = &states[state_idx];

            // 对于每个可能的符号（终结符和非终结符），计算 GOTO
            const all_symbols = [_]SymbolType{
                // 终结符
                .T_IDENT,            .T_STRING,      .T_NUMBER,        .T_HASH,     .T_DELIM,             .T_WHITESPACE,      .T_EOF,
                // 非终结符
                .N_STYLESHEET,       .N_RULE,        .N_SELECTOR_LIST, .N_SELECTOR, .N_SELECTOR_SEQUENCE, .N_SIMPLE_SELECTOR, .N_COMBINATOR,
                .N_DECLARATION_LIST, .N_DECLARATION, .N_PROPERTY,      .N_VALUE,
            };

            for (all_symbols) |sym| {
                if (current_state.goto(sym, prods)) |new_set| {
                    // 检查新状态是否已存在
                    var found = false;
                    var existing_state_idx: usize = 0;
                    for (states[0..state_count], 0..) |existing_state, idx| {
                        if (new_set.eql(&existing_state)) {
                            found = true;
                            existing_state_idx = idx;
                            break;
                        }
                    }

                    if (!found) {
                        // 新状态，添加到状态集合
                        if (state_count < MAX_STATES) {
                            states[state_count] = new_set;
                            existing_state_idx = state_count;
                            state_count += 1;
                        } else {
                            // 状态数量超过限制，跳过
                            continue;
                        }
                    }

                    // 填充 ACTION 或 GOTO 表
                    switch (sym) {
                        // 终结符 -> ACTION 表
                        .T_IDENT, .T_STRING, .T_NUMBER, .T_PERCENTAGE, .T_DIMENSION, .T_HASH, .T_FUNCTION, .T_AT_KEYWORD, .T_DELIM, .T_WHITESPACE, .T_COMMENT, .T_EOF => {
                            if (terminalIndex(sym)) |term_idx| {
                                if (term_idx < MAX_TERMINALS) {
                                    action_table[state_idx][term_idx] = ParseAction{ .shift = existing_state_idx };
                                }
                            }
                        },
                        // 非终结符 -> GOTO 表
                        .N_STYLESHEET, .N_RULE, .N_SELECTOR_LIST, .N_SELECTOR, .N_SELECTOR_SEQUENCE, .N_SIMPLE_SELECTOR, .N_COMBINATOR, .N_DECLARATION_LIST, .N_DECLARATION, .N_PROPERTY, .N_VALUE => {
                            if (nonTerminalIndex(sym)) |nt_idx| {
                                if (nt_idx < MAX_NON_TERMINALS) {
                                    goto_table[state_idx][nt_idx] = existing_state_idx;
                                }
                            }
                        },
                    }
                }
            }

            // 4. 填充归约动作（对于可归约的项目）
            for (current_state.items[0..current_state.count]) |item| {
                if (item.isReducible(prods)) {
                    // 对于所有终结符，添加归约动作
                    // 注意：这是 LR(0) 的简化处理，LR(1) 需要使用 FOLLOW 集
                    for (all_symbols) |sym| {
                        switch (sym) {
                            .T_IDENT, .T_STRING, .T_NUMBER, .T_PERCENTAGE, .T_DIMENSION, .T_HASH, .T_FUNCTION, .T_AT_KEYWORD, .T_DELIM, .T_WHITESPACE, .T_COMMENT, .T_EOF => {
                                if (terminalIndex(sym)) |term_idx| {
                                    if (term_idx < MAX_TERMINALS) {
                                        // 检查是否已有动作（避免覆盖 shift）
                                        if (action_table[state_idx][term_idx] == null) {
                                            action_table[state_idx][term_idx] = ParseAction{ .reduce = item.production_index };
                                        }
                                    }
                                }
                            },
                            // 非终结符不需要归约动作
                            .N_STYLESHEET, .N_RULE, .N_SELECTOR_LIST, .N_SELECTOR, .N_SELECTOR_SEQUENCE, .N_SIMPLE_SELECTOR, .N_COMBINATOR, .N_DECLARATION_LIST, .N_DECLARATION, .N_PROPERTY, .N_VALUE => {},
                        }
                    }
                }
            }
        }

        return .{
            .action_table = action_table,
            .goto_table = goto_table,
            .num_states = state_count,
        };
    }

    /// Comptime 生成的解析表
    const parse_tables = generateParseTables(&productions);

    /// 将符号类型转换为终结符索引
    fn terminalIndex(symbol_type: SymbolType) ?usize {
        return switch (symbol_type) {
            .T_IDENT => 0,
            .T_STRING => 1,
            .T_NUMBER => 2,
            .T_HASH => 3,
            .T_DELIM => 4,
            .T_WHITESPACE => 5,
            .T_EOF => 6,
            // 其他终结符暂不支持
            else => null,
        };
    }

    /// 将符号类型转换为非终结符索引
    fn nonTerminalIndex(symbol_type: SymbolType) ?usize {
        return switch (symbol_type) {
            .N_STYLESHEET => 0,
            .N_RULE => 1,
            .N_SELECTOR_LIST => 2,
            .N_SELECTOR => 3,
            .N_SELECTOR_SEQUENCE => 4,
            .N_SIMPLE_SELECTOR => 5,
            .N_COMBINATOR => 6,
            .N_DECLARATION_LIST => 7,
            .N_DECLARATION => 8,
            .N_PROPERTY => 9,
            .N_VALUE => 10,
            else => null,
        };
    }

    /// 检查 delimiter 字符（需要从 token 中获取）
    fn isDelimChar(token: tokenizer.Token, ch: u8) bool {
        return token.token_type == .delim and token.data.delim == ch;
    }

    /// 获取 ACTION 表（使用 comptime 生成的解析表）
    /// 返回：shift(状态) | reduce(规则编号) | accept | error
    fn getAction(self: *Self, state: usize, symbol_type: SymbolType, token: ?tokenizer.Token) ParseAction {
        _ = self;

        // 使用 comptime 生成的解析表
        if (state < parse_tables.num_states) {
            if (terminalIndex(symbol_type)) |term_idx| {
                if (term_idx < MAX_TERMINALS) {
                    if (parse_tables.action_table[state][term_idx]) |action| {
                        // 对于 T_DELIM，需要检查具体的字符
                        if (symbol_type == .T_DELIM) {
                            // 特殊处理 delimiter，需要根据字符决定动作
                            // 暂时回退到递归下降
                            _ = token; // 暂时未使用，后续实现时会使用
                            return ParseAction{ .parse_error = {} };
                        }
                        return action;
                    }
                }
            }
        }

        // 如果解析表中没有找到，返回错误，使用递归下降作为后备
        return ParseAction{ .parse_error = {} };

        // 以下是解析表的框架，待完善后启用
        // return switch (state) {
        //     0 => switch (symbol_type) {
        //         .T_IDENT, .T_HASH => ParseAction{ .shift = 8 }, // 开始解析 simple_selector
        //         .T_EOF => ParseAction{ .accept = {} },
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     1 => switch (symbol_type) {
        //         .T_DELIM => blk: {
        //             if (token) |t| {
        //                 if (isDelimChar(t, '{')) {
        //                     break :blk ParseAction{ .shift = 2 };
        //                 }
        //             }
        //             break :blk ParseAction{ .parse_error = {} };
        //         },
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     2 => switch (symbol_type) {
        //         .T_IDENT => ParseAction{ .shift = 9 }, // 开始解析 property
        //         .T_DELIM => blk: {
        //             if (token) |t| {
        //                 if (isDelimChar(t, '}')) {
        //                     // 空声明列表，先归约空的 declaration_list，再归约 rule
        //                     // 这里需要特殊处理：先归约空的 declaration_list (规则 12 需要至少一个 declaration)
        //                     // 暂时返回错误，让递归下降处理
        //                     break :blk ParseAction{ .parse_error = {} };
        //                 }
        //             }
        //             break :blk ParseAction{ .parse_error = {} };
        //         },
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     3 => switch (symbol_type) {
        //         .T_DELIM => blk: {
        //             if (token) |t| {
        //                 if (isDelimChar(t, ';')) {
        //                     break :blk ParseAction{ .shift = 4 };
        //                 } else if (isDelimChar(t, '}')) {
        //                     break :blk ParseAction{ .reduce = 1 }; // rule -> selector_list '{' declaration_list '}'
        //                 }
        //             }
        //             break :blk ParseAction{ .parse_error = {} };
        //         },
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     4 => switch (symbol_type) {
        //         .T_IDENT => ParseAction{ .shift = 9 }, // 开始解析 property
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     5 => switch (symbol_type) {
        //         .T_WHITESPACE => ParseAction{ .shift = 6 }, // combinator
        //         .T_DELIM => blk: {
        //             if (token) |t| {
        //                 if (isDelimChar(t, '>')) {
        //                     break :blk ParseAction{ .shift = 6 }; // combinator
        //                 } else if (isDelimChar(t, ',')) {
        //                     break :blk ParseAction{ .shift = 12 }; // selector_list -> selector_list ',' selector
        //                 } else if (isDelimChar(t, '{')) {
        //                     break :blk ParseAction{ .shift = 1 }; // 完成 selector_list
        //                 }
        //             }
        //             break :blk ParseAction{ .parse_error = {} };
        //         },
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     6 => switch (symbol_type) {
        //         .T_IDENT, .T_HASH => ParseAction{ .shift = 8 }, // 开始解析 simple_selector
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     7 => switch (symbol_type) {
        //         .T_IDENT, .T_HASH => ParseAction{ .shift = 8 }, // 继续解析 simple_selector
        //         .T_WHITESPACE => ParseAction{ .shift = 6 }, // combinator
        //         .T_DELIM => blk: {
        //             if (token) |t| {
        //                 if (isDelimChar(t, '>')) {
        //                     break :blk ParseAction{ .shift = 6 }; // combinator
        //                 } else if (isDelimChar(t, ',')) {
        //                     break :blk ParseAction{ .shift = 12 };
        //                 } else if (isDelimChar(t, '{')) {
        //                     break :blk ParseAction{ .shift = 1 };
        //                 }
        //             }
        //             break :blk ParseAction{ .parse_error = {} };
        //         },
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     8 => switch (symbol_type) {
        //         .T_IDENT, .T_HASH => ParseAction{ .shift = 8 }, // 继续解析 simple_selector
        //         .T_WHITESPACE => ParseAction{ .shift = 6 }, // combinator
        //         .T_DELIM => blk: {
        //             if (token) |t| {
        //                 if (isDelimChar(t, '>')) {
        //                     break :blk ParseAction{ .shift = 6 };
        //                 } else if (isDelimChar(t, ',')) {
        //                     break :blk ParseAction{ .shift = 12 };
        //                 } else if (isDelimChar(t, '{')) {
        //                     break :blk ParseAction{ .shift = 1 };
        //                 }
        //             }
        //             break :blk ParseAction{ .parse_error = {} };
        //         },
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     9 => switch (symbol_type) {
        //         .T_DELIM => blk: {
        //             if (token) |t| {
        //                 if (isDelimChar(t, ':')) {
        //                     break :blk ParseAction{ .shift = 10 };
        //                 }
        //             }
        //             break :blk ParseAction{ .parse_error = {} };
        //         },
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     10 => switch (symbol_type) {
        //         .T_IDENT => ParseAction{ .shift = 11 }, // value (keyword)
        //         .T_NUMBER => ParseAction{ .shift = 11 }, // value (number)
        //         .T_STRING => ParseAction{ .shift = 11 }, // value (string)
        //         .T_HASH => ParseAction{ .shift = 11 }, // value (color)
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     11 => switch (symbol_type) {
        //         .T_DELIM => blk: {
        //             if (token) |t| {
        //                 if (isDelimChar(t, ';')) {
        //                     break :blk ParseAction{ .shift = 4 };
        //                 } else if (isDelimChar(t, '}')) {
        //                     break :blk ParseAction{ .reduce = 1 }; // rule -> selector_list '{' declaration_list '}'
        //                 }
        //             }
        //             break :blk ParseAction{ .parse_error = {} };
        //         },
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     12 => switch (symbol_type) {
        //         .T_IDENT, .T_HASH => ParseAction{ .shift = 8 }, // 开始解析下一个 selector
        //         else => ParseAction{ .parse_error = {} },
        //     },
        //     else => ParseAction{ .parse_error = {} },
        // };
    }

    /// 获取 GOTO 表（使用 comptime 生成的解析表）
    /// 返回：新状态 | null（错误）
    fn getGoto(self: *Self, state: usize, non_terminal: SymbolType) ?usize {
        _ = self;

        // 使用 comptime 生成的解析表
        if (state < parse_tables.num_states) {
            if (nonTerminalIndex(non_terminal)) |nt_idx| {
                if (nt_idx < MAX_NON_TERMINALS) {
                    if (parse_tables.goto_table[state][nt_idx]) |new_state| {
                        return new_state;
                    }
                }
            }
        }

        // 如果解析表中没有找到，返回 null，使用递归下降作为后备
        return null;

        // 以下是 GOTO 表的框架，待完善后启用
        // return switch (state) {
        //     0 => switch (non_terminal) {
        //         .N_SELECTOR_LIST => 5,
        //         .N_SELECTOR => 5,
        //         .N_SELECTOR_SEQUENCE => 7,
        //         .N_SIMPLE_SELECTOR => 8,
        //         else => null,
        //     },
        //     1 => switch (non_terminal) {
        //         .N_RULE => 13, // 完成 rule
        //         else => null,
        //     },
        //     2 => switch (non_terminal) {
        //         .N_DECLARATION_LIST => 3,
        //         .N_DECLARATION => 3,
        //         else => null,
        //     },
        //     3 => switch (non_terminal) {
        //         .N_DECLARATION_LIST => 3, // 继续添加声明
        //         else => null,
        //     },
        //     4 => switch (non_terminal) {
        //         .N_DECLARATION => 3,
        //         else => null,
        //     },
        //     5 => switch (non_terminal) {
        //         .N_SELECTOR_LIST => 5, // 继续添加选择器
        //         .N_SELECTOR => 5,
        //         .N_SELECTOR_SEQUENCE => 7,
        //         .N_SIMPLE_SELECTOR => 8,
        //         else => null,
        //     },
        //     6 => switch (non_terminal) {
        //         .N_SELECTOR_SEQUENCE => 7,
        //         .N_SIMPLE_SELECTOR => 8,
        //         else => null,
        //     },
        //     7 => switch (non_terminal) {
        //         .N_SELECTOR => 5,
        //         .N_SELECTOR_SEQUENCE => 7, // 继续添加 simple_selector
        //         else => null,
        //     },
        //     8 => switch (non_terminal) {
        //         .N_SELECTOR_SEQUENCE => 7,
        //         .N_SIMPLE_SELECTOR => 8, // 继续添加 simple_selector
        //         else => null,
        //     },
        //     9 => switch (non_terminal) {
        //         .N_PROPERTY => 9,
        //         else => null,
        //     },
        //     10 => switch (non_terminal) {
        //         .N_VALUE => 11,
        //         else => null,
        //     },
        //     11 => switch (non_terminal) {
        //         .N_DECLARATION => 3,
        //         else => null,
        //     },
        //     12 => switch (non_terminal) {
        //         .N_SELECTOR => 5,
        //         .N_SELECTOR_SEQUENCE => 7,
        //         .N_SIMPLE_SELECTOR => 8,
        //         else => null,
        //     },
        //     else => null,
        // };
    }

    /// 解析样式表（真正的 LR 解析算法）
    pub fn parse(self: *Self) !parser.Stylesheet {
        // 初始化状态栈和符号栈
        try self.state_stack.append(0); // 初始状态 0

        var stylesheet = parser.Stylesheet.init(self.allocator);
        errdefer stylesheet.deinit();

        // LR 解析主循环
        const max_iterations: usize = 10000;
        var iteration_count: usize = 0;

        while (iteration_count < max_iterations) {
            iteration_count += 1;

            // 获取当前状态
            const current_state = self.state_stack.items[self.state_stack.items.len - 1];

            // 跳过空白和注释
            var token = try self.peek();
            while (token) |t| {
                switch (t.token_type) {
                    .whitespace, .comment => {
                        _ = try self.next();
                        t.deinit();
                        token = try self.peek();
                        continue;
                    },
                    else => break,
                }
            }

            // 获取当前 token
            token = try self.peek();
            if (token == null) {
                // EOF，尝试归约到 stylesheet
                if (self.symbol_stack.items.len == 1 and
                    self.symbol_stack.items[0].symbol_type == .N_STYLESHEET)
                {
                    const stylesheet_sym = self.symbol_stack.items[0];
                    return stylesheet_sym.data.stylesheet;
                }
                break;
            }

            const t = token.?;
            const symbol_type = tokenTypeToSymbolType(t.token_type) orelse {
                t.deinit();
                return error.InvalidToken;
            };

            // 查找 ACTION 表
            const action = self.getAction(current_state, symbol_type, token);

            switch (action) {
                .shift => |new_state| {
                    // Shift 操作：将 token 转换为符号，压入符号栈和状态栈
                    const sym = try self.tokenToSymbol(t);
                    _ = try self.next(); // 消耗 token
                    t.deinit();

                    try self.symbol_stack.append(sym);
                    try self.state_stack.append(new_state);
                },
                .reduce => |prod_index| {
                    // Reduce 操作：根据规则归约
                    if (prod_index >= productions.len) {
                        return error.InvalidProduction;
                    }

                    // 弹出右部符号（需要先获取规则信息）
                    const rhs_len: usize = switch (prod_index) {
                        0 => 1, // stylesheet -> rule
                        1 => 4, // rule -> selector_list '{' declaration_list '}'
                        2 => 1, // selector_list -> selector
                        3 => 3, // selector_list -> selector_list ',' selector
                        4 => 1, // selector -> selector_sequence
                        5 => 3, // selector -> selector combinator selector_sequence
                        6 => 1, // selector_sequence -> simple_selector
                        7 => 2, // selector_sequence -> selector_sequence simple_selector
                        8 => 1, // simple_selector -> T_IDENT
                        9 => 1, // simple_selector -> T_HASH
                        10 => 1, // combinator -> T_WHITESPACE
                        11 => 1, // combinator -> '>'
                        12 => 1, // declaration_list -> declaration
                        13 => 3, // declaration_list -> declaration_list ';' declaration
                        14 => 3, // declaration -> property ':' value
                        15 => 1, // property -> T_IDENT
                        16 => 1, // value -> T_IDENT
                        17 => 1, // value -> T_NUMBER
                        18 => 1, // value -> T_STRING
                        19 => 1, // value -> T_HASH
                        else => return error.InvalidProduction,
                    };

                    if (self.symbol_stack.items.len < rhs_len) {
                        return error.InvalidReduce;
                    }

                    // 获取要归约的符号（先复制，因为归约后会被释放）
                    const start_idx = self.symbol_stack.items.len - rhs_len;
                    var symbols_to_reduce = std.ArrayList(Symbol).init(self.allocator);
                    defer symbols_to_reduce.deinit();
                    for (self.symbol_stack.items[start_idx..]) |sym| {
                        try symbols_to_reduce.append(sym);
                    }

                    // 执行归约动作（使用 switch 避免运行时索引）
                    const new_symbol = switch (prod_index) {
                        0 => try reduceStylesheet(self.allocator, symbols_to_reduce.items),
                        1 => try reduceRule(self.allocator, symbols_to_reduce.items),
                        2 => try reduceSelectorList(self.allocator, symbols_to_reduce.items),
                        3 => try reduceSelectorListAppend(self.allocator, symbols_to_reduce.items),
                        4 => try reduceSelector(self.allocator, symbols_to_reduce.items),
                        5 => try reduceSelectorWithCombinator(self.allocator, symbols_to_reduce.items),
                        6 => try reduceSelectorSequence(self.allocator, symbols_to_reduce.items),
                        7 => try reduceSelectorSequenceAppend(self.allocator, symbols_to_reduce.items),
                        8 => try reduceSimpleSelectorType(self.allocator, symbols_to_reduce.items),
                        9 => try reduceSimpleSelectorId(self.allocator, symbols_to_reduce.items),
                        10 => try reduceCombinatorDescendant(self.allocator, symbols_to_reduce.items),
                        11 => try reduceCombinatorChild(self.allocator, symbols_to_reduce.items),
                        12 => try reduceDeclarationList(self.allocator, symbols_to_reduce.items),
                        13 => try reduceDeclarationListAppend(self.allocator, symbols_to_reduce.items),
                        14 => try reduceDeclaration(self.allocator, symbols_to_reduce.items),
                        15 => try reduceProperty(self.allocator, symbols_to_reduce.items),
                        16 => try reduceValueKeyword(self.allocator, symbols_to_reduce.items),
                        17 => try reduceValueNumber(self.allocator, symbols_to_reduce.items),
                        18 => try reduceValueString(self.allocator, symbols_to_reduce.items),
                        19 => try reduceValueColor(self.allocator, symbols_to_reduce.items),
                        else => return error.InvalidProduction,
                    };

                    // 弹出符号和状态（在归约完成后释放）
                    var i: usize = 0;
                    while (i < rhs_len) : (i += 1) {
                        // 从栈顶移除符号（使用 orderedRemove 而不是 pop）
                        if (self.symbol_stack.items.len == 0) {
                            return error.InvalidReduce;
                        }
                        const sym = self.symbol_stack.orderedRemove(self.symbol_stack.items.len - 1);
                        sym.deinit(self.allocator);
                        if (self.state_stack.items.len == 0) {
                            return error.InvalidReduce;
                        }
                        _ = self.state_stack.pop();
                    }

                    // 查找 GOTO 表
                    if (self.state_stack.items.len == 0) {
                        return error.InvalidReduce;
                    }
                    const new_state = self.state_stack.items[self.state_stack.items.len - 1];
                    const lhs: SymbolType = switch (prod_index) {
                        0 => .N_STYLESHEET,
                        1 => .N_RULE,
                        2, 3 => .N_SELECTOR_LIST,
                        4, 5 => .N_SELECTOR,
                        6, 7 => .N_SELECTOR_SEQUENCE,
                        8, 9 => .N_SIMPLE_SELECTOR,
                        10, 11 => .N_COMBINATOR,
                        12, 13 => .N_DECLARATION_LIST,
                        14 => .N_DECLARATION,
                        15 => .N_PROPERTY,
                        16, 17, 18, 19 => .N_VALUE,
                        else => return error.InvalidProduction,
                    };
                    const goto_state = self.getGoto(new_state, lhs);

                    if (goto_state) |gs| {
                        // 压入新符号和新状态
                        try self.symbol_stack.append(new_symbol);
                        try self.state_stack.append(gs);
                    } else {
                        // GOTO 失败，使用递归下降作为后备
                        // 清理并切换到递归下降
                        for (self.symbol_stack.items) |*sym| {
                            self.freeSymbol(sym);
                        }
                        self.symbol_stack.clearRetainingCapacity();
                        self.state_stack.clearRetainingCapacity();

                        // 使用递归下降解析
                        return try self.parseRecursiveFallback();
                    }
                },
                .accept => {
                    // 接受：解析成功
                    if (self.symbol_stack.items.len == 1) {
                        const stylesheet_sym = self.symbol_stack.items[0];
                        if (stylesheet_sym.symbol_type == .N_STYLESHEET) {
                            return stylesheet_sym.data.stylesheet;
                        }
                    }
                    return error.InvalidAccept;
                },
                .parse_error => {
                    // 解析错误，使用递归下降作为后备
                    // 清理并切换到递归下降
                    for (self.symbol_stack.items) |*sym| {
                        self.freeSymbol(sym);
                    }
                    self.symbol_stack.clearRetainingCapacity();
                    self.state_stack.clearRetainingCapacity();

                    // 使用递归下降解析
                    return try self.parseRecursiveFallback();
                },
            }
        }

        if (iteration_count >= max_iterations) {
            return error.ParseTimeout;
        }

        // 如果符号栈中有 stylesheet，返回它
        if (self.symbol_stack.items.len == 1) {
            const stylesheet_sym = self.symbol_stack.items[0];
            if (stylesheet_sym.symbol_type == .N_STYLESHEET) {
                return stylesheet_sym.data.stylesheet;
            }
        }

        return error.UnexpectedEOF;
    }

    /// 递归下降后备解析（当 LR 解析表不可用时使用）
    fn parseRecursiveFallback(self: *Self) !parser.Stylesheet {
        var stylesheet = parser.Stylesheet.init(self.allocator);
        errdefer stylesheet.deinit();

        // 跳过空白和注释
        while (true) {
            const token = try self.peek();
            if (token) |t| {
                switch (t.token_type) {
                    .whitespace, .comment => {
                        _ = try self.next();
                        t.deinit();
                        continue;
                    },
                    .eof => break,
                    else => break,
                }
            } else {
                break;
            }
        }

        // 解析规则（使用递归下降）
        while (true) {
            const token = try self.peek();
            if (token) |t| {
                switch (t.token_type) {
                    .whitespace, .comment => {
                        _ = try self.next();
                        t.deinit();
                        continue;
                    },
                    .eof => break,
                    .at_keyword => {
                        // 跳过 @ 规则
                        _ = try self.next();
                        t.deinit();
                        continue;
                    },
                    else => {
                        // 解析规则
                        if (try self.parseRuleRecursive()) |rule| {
                            try stylesheet.rules.append(rule);
                        } else {
                            break;
                        }
                    },
                }
            } else {
                break;
            }
        }

        return stylesheet;
    }

    /// 递归下降解析规则（临时实现，后续改为 LR 解析）
    fn parseRuleRecursive(self: *Self) !?parser.Rule {
        // 解析选择器列表
        const selector_list = try self.parseSelectorListRecursive();
        defer selector_list.deinit();

        // 跳过空白
        while (true) {
            const token = try self.peek();
            if (token) |t| {
                if (t.token_type == .whitespace) {
                    _ = try self.next();
                    t.deinit();
                    continue;
                }
                break;
            } else {
                break;
            }
        }

        // 期望 '{'
        const open_token = (try self.next()) orelse return null;
        defer open_token.deinit();
        if (open_token.token_type != .delim or open_token.data.delim != '{') {
            return null;
        }

        // 解析声明列表
        const declaration_list = try self.parseDeclarationListRecursive();
        defer declaration_list.deinit();

        // 期望 '}'
        const close_token = try self.next();
        if (close_token) |t| {
            defer t.deinit();
            if (t.token_type != .delim or t.data.delim != '}') {
                return null;
            }
        } else {
            return null;
        }

        // 创建规则
        var rule = parser.Rule.init(self.allocator);
        for (selector_list.items) |sel| {
            try rule.selectors.append(sel);
        }
        for (declaration_list.items) |decl| {
            try rule.declarations.append(decl);
        }

        return rule;
    }

    /// 递归下降解析选择器列表
    fn parseSelectorListRecursive(self: *Self) !std.ArrayList(selector.Selector) {
        var selector_list = std.ArrayList(selector.Selector).init(self.allocator);

        // 解析第一个选择器
        const sel = try self.parseSelectorRecursive();
        try selector_list.append(sel);

        // 解析更多选择器（用逗号分隔）
        while (true) {
            // 跳过空白
            while (true) {
                const token = try self.peek();
                if (token) |t| {
                    if (t.token_type == .whitespace) {
                        _ = try self.next();
                        t.deinit();
                        continue;
                    }
                    break;
                } else {
                    break;
                }
            }

            const token = try self.peek();
            if (token) |t| {
                if (t.token_type == .delim and t.data.delim == ',') {
                    _ = try self.next(); // 消耗 ','
                    t.deinit();

                    // 解析下一个选择器
                    const sel2 = try self.parseSelectorRecursive();
                    try selector_list.append(sel2);
                } else {
                    break;
                }
            } else {
                break;
            }
        }

        return selector_list;
    }

    /// 递归下降解析选择器
    fn parseSelectorRecursive(self: *Self) !selector.Selector {
        var sel = selector.Selector.init(self.allocator);

        // 解析第一个选择器序列
        const sequence = try self.parseSelectorSequenceRecursive();
        try sel.sequences.append(sequence);

        // 解析组合器和后续序列
        while (true) {
            // 跳过空白
            var has_whitespace = false;
            while (true) {
                const token = try self.peek();
                if (token) |t| {
                    if (t.token_type == .whitespace) {
                        has_whitespace = true;
                        _ = try self.next();
                        t.deinit();
                        continue;
                    }
                    break;
                } else {
                    break;
                }
            }

            const token = try self.peek();
            if (token) |t| {
                var combinator: ?selector.Combinator = null;

                if (has_whitespace) {
                    // 空白表示后代组合器
                    combinator = .descendant;
                } else if (t.token_type == .delim) {
                    const ch = t.data.delim;
                    if (ch == '>') {
                        _ = try self.next();
                        t.deinit();
                        combinator = .child;
                    } else if (ch == '+') {
                        _ = try self.next();
                        t.deinit();
                        combinator = .adjacent;
                    } else if (ch == '~') {
                        _ = try self.next();
                        t.deinit();
                        combinator = .sibling;
                    } else {
                        break;
                    }
                } else {
                    break;
                }

                if (combinator) |comb| {
                    // 解析下一个序列
                    var next_sequence = try self.parseSelectorSequenceRecursive();
                    defer next_sequence.deinit();

                    // 将组合器和序列添加到当前选择器
                    if (sel.sequences.items.len > 0) {
                        const last_seq = &sel.sequences.items[sel.sequences.items.len - 1];
                        try last_seq.combinators.append(comb);
                        // 将新序列的选择器添加到当前序列
                        for (next_sequence.selectors.items) |*simple_sel| {
                            const simple_sel_copy = selector.SimpleSelector{
                                .selector_type = simple_sel.selector_type,
                                .value = try self.allocator.dupe(u8, simple_sel.value),
                                .attribute_name = if (simple_sel.attribute_name) |name|
                                    try self.allocator.dupe(u8, name)
                                else
                                    null,
                                .attribute_value = if (simple_sel.attribute_value) |val|
                                    try self.allocator.dupe(u8, val)
                                else
                                    null,
                                .attribute_match = simple_sel.attribute_match,
                                .allocator = self.allocator,
                            };
                            try last_seq.selectors.append(simple_sel_copy);
                        }
                    }
                }
            } else {
                break;
            }
        }

        return sel;
    }

    /// 递归下降解析选择器序列
    fn parseSelectorSequenceRecursive(self: *Self) !selector.SelectorSequence {
        var sequence = selector.SelectorSequence.init(self.allocator);

        // 解析第一个简单选择器
        const simple_sel = try self.parseSimpleSelectorRecursive();
        try sequence.selectors.append(simple_sel);

        // 解析更多简单选择器（无组合器）
        while (true) {
            // 跳过空白
            while (true) {
                const token = try self.peek();
                if (token) |t| {
                    if (t.token_type == .whitespace) {
                        _ = try self.next();
                        t.deinit();
                        continue;
                    }
                    break;
                } else {
                    break;
                }
            }

            const token = try self.peek();
            if (token) |t| {
                // 检查是否是简单选择器的开始
                if (t.token_type == .ident or t.token_type == .hash or
                    (t.token_type == .delim and (t.data.delim == '.' or t.data.delim == '[' or t.data.delim == '*')))
                {
                    const simple_sel2 = try self.parseSimpleSelectorRecursive();
                    try sequence.selectors.append(simple_sel2);
                } else {
                    break;
                }
            } else {
                break;
            }
        }

        return sequence;
    }

    /// 递归下降解析简单选择器
    fn parseSimpleSelectorRecursive(self: *Self) !selector.SimpleSelector {
        const token = (try self.next()) orelse return error.UnexpectedEOF;
        defer token.deinit();

        switch (token.token_type) {
            .ident => {
                // 类型选择器
                return selector.SimpleSelector{
                    .selector_type = .type,
                    .value = try self.allocator.dupe(u8, token.data.ident),
                    .allocator = self.allocator,
                };
            },
            .hash => {
                // ID 选择器
                return selector.SimpleSelector{
                    .selector_type = .id,
                    .value = try self.allocator.dupe(u8, token.data.hash),
                    .allocator = self.allocator,
                };
            },
            .delim => {
                const ch = token.data.delim;
                if (ch == '.') {
                    // 类选择器
                    const class_token = (try self.next()) orelse return error.UnexpectedEOF;
                    defer class_token.deinit();
                    if (class_token.token_type != .ident) {
                        return error.InvalidClassSelector;
                    }
                    return selector.SimpleSelector{
                        .selector_type = .class,
                        .value = try self.allocator.dupe(u8, class_token.data.ident),
                        .allocator = self.allocator,
                    };
                } else if (ch == '*') {
                    // 通配符选择器
                    return selector.SimpleSelector{
                        .selector_type = .universal,
                        .value = try self.allocator.dupe(u8, "*"),
                        .allocator = self.allocator,
                    };
                } else {
                    return error.InvalidSelector;
                }
            },
            else => return error.InvalidSelector,
        }
    }

    /// 递归下降解析声明列表
    fn parseDeclarationListRecursive(self: *Self) !std.ArrayList(parser.Declaration) {
        var declaration_list = std.ArrayList(parser.Declaration).init(self.allocator);

        // 跳过空白
        while (true) {
            const token = try self.peek();
            if (token) |t| {
                switch (t.token_type) {
                    .whitespace, .comment => {
                        _ = try self.next();
                        t.deinit();
                        continue;
                    },
                    .delim => {
                        if (t.data.delim == '}') {
                            return declaration_list; // 声明列表结束
                        }
                        if (t.data.delim == ';') {
                            _ = try self.next();
                            t.deinit();
                            continue;
                        }
                    },
                    else => {},
                }
                break;
            } else {
                break;
            }
        }

        // 解析第一个声明
        if (try self.parseDeclarationRecursive()) |decl| {
            try declaration_list.append(decl);
        }

        // 解析更多声明
        while (true) {
            // 跳过空白和分号
            while (true) {
                const token = try self.peek();
                if (token) |t| {
                    switch (t.token_type) {
                        .whitespace, .comment => {
                            _ = try self.next();
                            t.deinit();
                            continue;
                        },
                        .delim => {
                            if (t.data.delim == ';') {
                                _ = try self.next();
                                t.deinit();
                                continue;
                            }
                            if (t.data.delim == '}') {
                                return declaration_list; // 声明列表结束
                            }
                        },
                        else => {},
                    }
                    break;
                } else {
                    break;
                }
            }

            if (try self.parseDeclarationRecursive()) |decl| {
                try declaration_list.append(decl);
            } else {
                break;
            }
        }

        return declaration_list;
    }

    /// 递归下降解析声明
    fn parseDeclarationRecursive(self: *Self) !?parser.Declaration {
        // 跳过空白
        while (true) {
            const token = try self.peek();
            if (token) |t| {
                if (t.token_type == .whitespace) {
                    _ = try self.next();
                    t.deinit();
                    continue;
                }
                break;
            } else {
                break;
            }
        }

        // 解析属性名
        const prop_token = (try self.next()) orelse return null;
        defer prop_token.deinit();
        if (prop_token.token_type != .ident) {
            return null;
        }
        const name = try self.allocator.dupe(u8, prop_token.data.ident);

        // 跳过空白
        while (true) {
            const token = try self.peek();
            if (token) |t| {
                if (t.token_type == .whitespace) {
                    _ = try self.next();
                    t.deinit();
                    continue;
                }
                break;
            } else {
                break;
            }
        }

        // 期望 ':'
        const colon_token = (try self.next()) orelse return null;
        defer colon_token.deinit();
        if (colon_token.token_type != .delim or colon_token.data.delim != ':') {
            return null;
        }

        // 解析值
        const value = try self.parseValueRecursive();

        // 检查 !important
        var important = false;
        while (true) {
            const token = try self.peek();
            if (token) |t| {
                if (t.token_type == .whitespace) {
                    _ = try self.next();
                    t.deinit();
                    continue;
                }
                if (t.token_type == .delim and t.data.delim == '!') {
                    _ = try self.next();
                    t.deinit();
                    const important_token = (try self.next()) orelse break;
                    defer important_token.deinit();
                    if (important_token.token_type == .ident) {
                        if (std.mem.eql(u8, important_token.data.ident, "important")) {
                            important = true;
                        }
                    }
                }
                break;
            } else {
                break;
            }
        }

        return try parser.Declaration.init(self.allocator, name, value, important);
    }

    /// 递归下降解析值
    fn parseValueRecursive(self: *Self) !parser.Value {
        // 跳过空白
        while (true) {
            const token = try self.peek();
            if (token) |t| {
                if (t.token_type == .whitespace) {
                    _ = try self.next();
                    t.deinit();
                    continue;
                }
                break;
            } else {
                break;
            }
        }

        const token = (try self.next()) orelse return error.UnexpectedEOF;
        defer token.deinit();

        return switch (token.token_type) {
            .ident => blk: {
                const keyword = try self.allocator.dupe(u8, token.data.ident);
                break :blk parser.Value{ .keyword = keyword };
            },
            .string => blk: {
                const str = try self.allocator.dupe(u8, token.data.string);
                break :blk parser.Value{ .string = str };
            },
            .number => parser.Value{ .number = token.data.number },
            .percentage => parser.Value{ .percentage = token.data.percentage },
            .dimension => blk: {
                const unit = try self.allocator.dupe(u8, token.data.dimension.unit);
                break :blk parser.Value{
                    .length = .{
                        .value = token.data.dimension.value,
                        .unit = unit,
                    },
                };
            },
            .hash => blk: {
                const color = try parseColor(self.allocator, token.data.hash);
                break :blk parser.Value{ .color = color };
            },
            else => error.InvalidValue,
        };
    }
};
