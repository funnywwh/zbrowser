const std = @import("std");
const tokenizer = @import("tokenizer");

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
    selectors: std.ArrayList([]const u8), // 简化的选择器（暂时用字符串）
    declarations: std.ArrayList(Declaration),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Rule {
        return .{
            .selectors = std.ArrayList([]const u8).init(allocator),
            .declarations = std.ArrayList(Declaration).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Rule, allocator: std.mem.Allocator) void {
        for (self.selectors.items) |selector| {
            allocator.free(selector);
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

    /// 解析样式表
    pub fn parse(self: *Self) !Stylesheet {
        var stylesheet = Stylesheet.init(self.allocator);
        errdefer stylesheet.deinit();

        while (true) {
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
        var rule = Rule.init(self.allocator);
        errdefer rule.deinit(self.allocator);

        // 解析选择器列表
        while (try self.next()) |token| {
            defer token.deinit();

            switch (token.token_type) {
                .whitespace => continue,
                .delim => {
                    const ch = token.data.delim;
                    if (ch == '{') {
                        break;
                    }
                    if (ch == ',') {
                        continue;
                    }
                },
                .ident => {
                    const ident = token.data.ident;
                    const selector = try self.allocator.dupe(u8, ident);
                    try rule.selectors.append(selector);
                },
                else => {
                    // 复杂选择器，暂时简化为字符串
                    const selector_str = try self.parseSelectorString();
                    const selector = try self.allocator.dupe(u8, selector_str);
                    try rule.selectors.append(selector);
                },
            }
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

        return rule;
    }

    /// 解析选择器字符串（简化实现）
    fn parseSelectorString(self: *Self) ![]const u8 {
        // TODO: 实现完整的选择器解析
        const token = (try self.next()) orelse return "";
        defer token.deinit();
        return switch (token.token_type) {
            .ident => token.data.ident,
            .hash => token.data.hash,
            else => "",
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
        const token = (try self.next()) orelse {
            return error.UnexpectedEOF;
        };
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
