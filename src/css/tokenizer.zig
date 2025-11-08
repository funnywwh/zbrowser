const std = @import("std");
const string = @import("string");

/// CSS Token类型
pub const TokenType = enum {
    ident,
    string,
    number,
    percentage,
    dimension,
    hash,
    url,
    function,
    at_keyword,
    delim,
    whitespace,
    comment,
    cdo,
    cdc,
    eof,
};

/// CSS Token
pub const Token = struct {
    token_type: TokenType,
    data: Data,

    pub const Data = union(TokenType) {
        ident: []const u8,
        string: []const u8,
        number: f64,
        percentage: f64,
        dimension: Dimension,
        hash: []const u8,
        url: []const u8,
        function: []const u8,
        at_keyword: []const u8,
        delim: u8,
        whitespace: void,
        comment: []const u8,
        cdo: void,
        cdc: void,
        eof: void,
    };

    pub const Dimension = struct {
        value: f64,
        unit: []const u8,
    };

    /// 释放token占用的内存
    pub fn deinit(self: *Token, allocator: std.mem.Allocator) void {
        switch (self.token_type) {
            .ident => allocator.free(self.data.ident),
            .string => allocator.free(self.data.string),
            .dimension => {
                allocator.free(self.data.dimension.unit);
            },
            .hash => allocator.free(self.data.hash),
            .url => allocator.free(self.data.url),
            .function => allocator.free(self.data.function),
            .at_keyword => allocator.free(self.data.at_keyword),
            .comment => allocator.free(self.data.comment),
            else => {},
        }
    }
};

/// CSS词法分析器
pub const Tokenizer = struct {
    input: []const u8,
    pos: usize = 0,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(input: []const u8, allocator: std.mem.Allocator) Self {
        return .{
            .input = input,
            .pos = 0,
            .allocator = allocator,
        };
    }

    /// 获取下一个token
    pub fn next(self: *Self) !Token {
        if (self.pos >= self.input.len) {
            return Token{
                .token_type = .eof,
                .data = .{ .eof = {} },
            };
        }

        // 跳过空白字符
        self.skipWhitespace();

        if (self.pos >= self.input.len) {
            return Token{
                .token_type = .eof,
                .data = .{ .eof = {} },
            };
        }

        const c = self.input[self.pos];

        // 检查注释
        if (c == '/' and self.pos + 1 < self.input.len and self.input[self.pos + 1] == '*') {
            return try self.parseComment();
        }

        // 检查CDO (<!--)
        if (c == '<' and self.pos + 3 < self.input.len) {
            if (std.mem.eql(u8, self.input[self.pos..][0..4], "<!--")) {
                self.pos += 4;
                return Token{
                    .token_type = .cdo,
                    .data = .{ .cdo = {} },
                };
            }
        }

        // 检查CDC (-->)
        if (c == '-' and self.pos + 2 < self.input.len) {
            if (std.mem.eql(u8, self.input[self.pos..][0..3], "-->")) {
                self.pos += 3;
                return Token{
                    .token_type = .cdc,
                    .data = .{ .cdc = {} },
                };
            }
        }

        // 检查字符串
        if (c == '"' or c == '\'') {
            return try self.parseString(c);
        }

        // 检查数字
        if (string.isDigit(c) or (c == '.' and self.pos + 1 < self.input.len and string.isDigit(self.input[self.pos + 1]))) {
            return try self.parseNumber();
        }

        // 检查URL（在标识符之前检查）
        if (c == 'u' or c == 'U') {
            const remaining = self.input[self.pos..];
            if (remaining.len >= 4 and std.ascii.eqlIgnoreCase(remaining[0..3], "url")) {
                const next_char = remaining[3];
                if (next_char == '(') {
                    return try self.parseUrl();
                }
            }
        }

        // 检查标识符或函数（以字母或_或-开头）
        if (string.isAlpha(c) or c == '_' or c == '-' or c == '\\') {
            const ident_token = try self.parseIdent();
            // 检查是否是函数（标识符后跟'('）
            if (self.pos < self.input.len and self.input[self.pos] == '(') {
                self.pos += 1;
                return Token{
                    .token_type = .function,
                    .data = .{ .function = ident_token.data.ident },
                };
            }
            // 不是函数，返回标识符
            return ident_token;
        }

        // 检查HASH (#)
        if (c == '#') {
            return try self.parseHash();
        }

        // 检查@关键字
        if (c == '@') {
            return try self.parseAtKeyword();
        }

        // 分隔符
        self.pos += 1;
        return Token{
            .token_type = .delim,
            .data = .{ .delim = c },
        };
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.input.len and string.isWhitespace(self.input[self.pos])) {
            self.pos += 1;
        }
    }

    fn parseComment(self: *Self) !Token {
        std.debug.assert(self.input[self.pos] == '/' and self.input[self.pos + 1] == '*');
        self.pos += 2;

        const start = self.pos;
        while (self.pos + 1 < self.input.len) {
            if (self.input[self.pos] == '*' and self.input[self.pos + 1] == '/') {
                const comment = try self.allocator.dupe(u8, self.input[start..self.pos]);
                self.pos += 2;
                return Token{
                    .token_type = .comment,
                    .data = .{ .comment = comment },
                };
            }
            self.pos += 1;
        }

        // 未闭合的注释
        const comment = try self.allocator.dupe(u8, self.input[start..]);
        return Token{
            .token_type = .comment,
            .data = .{ .comment = comment },
        };
    }

    fn parseString(self: *Self, quote: u8) !Token {
        std.debug.assert(self.input[self.pos] == quote);
        self.pos += 1;

        const start = self.pos;
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c == quote) {
                const str = try self.allocator.dupe(u8, self.input[start..self.pos]);
                self.pos += 1;
                return Token{
                    .token_type = .string,
                    .data = .{ .string = str },
                };
            }
            if (c == '\\') {
                self.pos += 1;
                if (self.pos < self.input.len) {
                    self.pos += 1;
                }
            } else {
                self.pos += 1;
            }
        }

        // 未闭合的字符串
        const str = try self.allocator.dupe(u8, self.input[start..]);
        return Token{
            .token_type = .string,
            .data = .{ .string = str },
        };
    }

    fn parseNumber(self: *Self) !Token {
        const start = self.pos;
        var has_dot = false;

        // 可选的正负号
        if (self.input[self.pos] == '+' or self.input[self.pos] == '-') {
            self.pos += 1;
        }

        // 整数部分
        while (self.pos < self.input.len and string.isDigit(self.input[self.pos])) {
            self.pos += 1;
        }

        // 小数点
        if (self.pos < self.input.len and self.input[self.pos] == '.') {
            has_dot = true;
            self.pos += 1;
            while (self.pos < self.input.len and string.isDigit(self.input[self.pos])) {
                self.pos += 1;
            }
        }

        // 科学计数法
        if (self.pos < self.input.len and (self.input[self.pos] == 'e' or self.input[self.pos] == 'E')) {
            self.pos += 1;
            if (self.pos < self.input.len and (self.input[self.pos] == '+' or self.input[self.pos] == '-')) {
                self.pos += 1;
            }
            while (self.pos < self.input.len and string.isDigit(self.input[self.pos])) {
                self.pos += 1;
            }
        }

        const num_str = self.input[start..self.pos];
        const num = try std.fmt.parseFloat(f64, num_str);

        // 检查是否是百分比
        if (self.pos < self.input.len and self.input[self.pos] == '%') {
            self.pos += 1;
            return Token{
                .token_type = .percentage,
                .data = .{ .percentage = num },
            };
        }

        // 检查是否是维度（带单位）
        if (self.pos < self.input.len) {
            const unit_start = self.pos;
            // 解析单位（字母、-、_等）
            while (self.pos < self.input.len) {
                const c = self.input[self.pos];
                if (string.isAlpha(c) or c == '_' or c == '-' or c == '\\') {
                    self.pos += 1;
                } else {
                    break;
                }
            }

            if (self.pos > unit_start) {
                const unit = try self.allocator.dupe(u8, self.input[unit_start..self.pos]);
                return Token{
                    .token_type = .dimension,
                    .data = .{
                        .dimension = .{
                            .value = num,
                            .unit = unit,
                        },
                    },
                };
            }
        }

        return Token{
            .token_type = .number,
            .data = .{ .number = num },
        };
    }

    fn parseIdent(self: *Self) !Token {
        const start = self.pos;

        // 处理转义字符
        if (self.input[self.pos] == '\\') {
            self.pos += 1;
            if (self.pos < self.input.len) {
                self.pos += 1;
            }
        } else {
            self.pos += 1;
        }

        // 继续解析标识符
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (string.isAlnum(c) or c == '_' or c == '-' or c == '\\') {
                if (c == '\\') {
                    self.pos += 1;
                    if (self.pos < self.input.len) {
                        self.pos += 1;
                    }
                } else {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }

        const ident = try self.allocator.dupe(u8, self.input[start..self.pos]);
        return Token{
            .token_type = .ident,
            .data = .{ .ident = ident },
        };
    }

    fn parseHash(self: *Self) !Token {
        std.debug.assert(self.input[self.pos] == '#');
        self.pos += 1;

        const start = self.pos;
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (string.isAlnum(c) or c == '_' or c == '-' or c == '\\') {
                if (c == '\\') {
                    self.pos += 1;
                    if (self.pos < self.input.len) {
                        self.pos += 1;
                    }
                } else {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }

        const hash = try self.allocator.dupe(u8, self.input[start..self.pos]);
        return Token{
            .token_type = .hash,
            .data = .{ .hash = hash },
        };
    }

    fn parseAtKeyword(self: *Self) !Token {
        std.debug.assert(self.input[self.pos] == '@');
        self.pos += 1;

        const start = self.pos;
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (string.isAlnum(c) or c == '_' or c == '-' or c == '\\') {
                if (c == '\\') {
                    self.pos += 1;
                    if (self.pos < self.input.len) {
                        self.pos += 1;
                    }
                } else {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }

        const at_keyword = try self.allocator.dupe(u8, self.input[start..self.pos]);
        return Token{
            .token_type = .at_keyword,
            .data = .{ .at_keyword = at_keyword },
        };
    }

    fn parseUrl(self: *Self) !Token {
        // 跳过 "url("
        while (self.pos < self.input.len and self.input[self.pos] != '(') {
            self.pos += 1;
        }
        if (self.pos < self.input.len) {
            self.pos += 1; // 跳过 '('
        }

        // 跳过空白
        while (self.pos < self.input.len and string.isWhitespace(self.input[self.pos])) {
            self.pos += 1;
        }

        const start = self.pos;
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c == ')') {
                break;
            }
            if (c == '\\') {
                self.pos += 1;
                if (self.pos < self.input.len) {
                    self.pos += 1;
                }
            } else {
                self.pos += 1;
            }
        }

        var url_str = self.input[start..self.pos];
        // 去除引号
        if (url_str.len > 0 and (url_str[0] == '"' or url_str[0] == '\'')) {
            url_str = url_str[1..];
        }
        if (url_str.len > 0 and (url_str[url_str.len - 1] == '"' or url_str[url_str.len - 1] == '\'')) {
            url_str = url_str[0 .. url_str.len - 1];
        }

        const url = try self.allocator.dupe(u8, url_str);
        if (self.pos < self.input.len and self.input[self.pos] == ')') {
            self.pos += 1;
        }

        return Token{
            .token_type = .url,
            .data = .{ .url = url },
        };
    }
};
