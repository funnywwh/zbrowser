const std = @import("std");
const string = @import("string");

/// CSS Token类型
pub const TokenType = enum {
    ident, // 标识符（如：div, class, color）
    string, // 字符串（如："hello"）
    number, // 数字（如：100）
    percentage, // 百分比（如：50%）
    dimension, // 带单位的数字（如：10px, 1.5em）
    hash, // #颜色或ID（如：#fff, #myId）
    url, // url()函数
    function, // 函数（如：calc(), rgba()）
    at_keyword, // @规则（如：@media, @keyframes）
    delim, // 分隔符（如：{, }, :, ;, ,, (, ), [, ]）
    whitespace, // 空白字符
    comment, // 注释（/* ... */）
    eof, // 文件结束
};

/// CSS Token
pub const Token = struct {
    token_type: TokenType,
    data: Data,
    allocator: ?std.mem.Allocator = null,

    pub const Data = union(TokenType) {
        ident: []const u8,
        string: []const u8,
        number: f32,
        percentage: f32,
        dimension: DimensionData,
        hash: []const u8,
        url: []const u8,
        function: []const u8,
        at_keyword: []const u8,
        delim: u8,
        whitespace: void,
        comment: []const u8,
        eof: void,
    };

    pub const DimensionData = struct {
        value: f32,
        unit: []const u8,

        pub fn deinit(self: *const DimensionData, allocator: std.mem.Allocator) void {
            allocator.free(self.unit);
        }
    };

    /// 释放token占用的内存
    pub fn deinit(self: *const Token) void {
        if (self.allocator) |allocator| {
            switch (self.token_type) {
                .ident => allocator.free(self.data.ident),
                .string => allocator.free(self.data.string),
                .dimension => {
                    self.data.dimension.deinit(allocator);
                },
                .hash => allocator.free(self.data.hash),
                .url => allocator.free(self.data.url),
                .function => allocator.free(self.data.function),
                .at_keyword => allocator.free(self.data.at_keyword),
                .comment => allocator.free(self.data.comment),
                else => {},
            }
        }
    }
};

/// CSS词法分析器
pub const Tokenizer = struct {
    input: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 初始化tokenizer
    pub fn init(input: []const u8, allocator: std.mem.Allocator) Self {
        return .{
            .input = input,
            .pos = 0,
            .allocator = allocator,
        };
    }

    /// 获取下一个token
    pub fn next(self: *Self) !?Token {
        if (self.pos >= self.input.len) {
            return Token{
                .token_type = .eof,
                .data = .{ .eof = {} },
            };
        }

        const ch = self.input[self.pos];

        // 处理空白字符
        if (string.isWhitespace(ch)) {
            while (self.pos < self.input.len and string.isWhitespace(self.input[self.pos])) {
                self.pos += 1;
            }
            return Token{
                .token_type = .whitespace,
                .data = .{ .whitespace = {} },
            };
        }

        // 处理注释
        if (ch == '/' and self.pos + 1 < self.input.len and self.input[self.pos + 1] == '*') {
            const comment_token = try self.parseComment();
            return comment_token;
        }

        // 处理字符串
        if (ch == '"' or ch == '\'') {
            const str_token = try self.parseString(ch);
            return str_token;
        }

        // 处理数字
        if (string.isDigit(ch) or (ch == '.' and self.pos + 1 < self.input.len and string.isDigit(self.input[self.pos + 1]))) {
            const num_token = try self.parseNumber();
            return num_token;
        }

        // 处理标识符或关键字
        if (string.isAlpha(ch) or ch == '_' or ch == '-') {
            const ident_token = try self.parseIdent();
            return ident_token;
        }

        // 处理#（hash）
        if (ch == '#') {
            self.pos += 1;
            if (self.pos < self.input.len and (string.isAlnum(self.input[self.pos]) or self.input[self.pos] == '-')) {
                const start = self.pos;
                while (self.pos < self.input.len and (string.isAlnum(self.input[self.pos]) or self.input[self.pos] == '-')) {
                    self.pos += 1;
                }
                const value = self.input[start..self.pos];
                const hash = try self.allocator.dupe(u8, value);
                return Token{
                    .token_type = .hash,
                    .data = .{ .hash = hash },
                    .allocator = self.allocator,
                };
            }
            return Token{
                .token_type = .delim,
                .data = .{ .delim = '#' },
            };
        }

        // 处理@规则
        if (ch == '@') {
            self.pos += 1;
            if (self.pos < self.input.len and string.isAlpha(self.input[self.pos])) {
                const start = self.pos;
                while (self.pos < self.input.len and (string.isAlnum(self.input[self.pos]) or self.input[self.pos] == '-')) {
                    self.pos += 1;
                }
                const value = self.input[start..self.pos];
                const keyword = try self.allocator.dupe(u8, value);
                return Token{
                    .token_type = .at_keyword,
                    .data = .{ .at_keyword = keyword },
                    .allocator = self.allocator,
                };
            }
            return Token{
                .token_type = .delim,
                .data = .{ .delim = '@' },
            };
        }

        // 处理分隔符
        self.pos += 1;
        return Token{
            .token_type = .delim,
            .data = .{ .delim = ch },
        };
    }

    fn parseComment(self: *Self) !Token {
        // 跳过 /*
        self.pos += 2;
        const start = self.pos;

        // 查找 */
        while (self.pos + 1 < self.input.len) {
            if (self.input[self.pos] == '*' and self.input[self.pos + 1] == '/') {
                const value = self.input[start..self.pos];
                self.pos += 2; // 跳过 */
                const comment = try self.allocator.dupe(u8, value);
                return Token{
                    .token_type = .comment,
                    .data = .{ .comment = comment },
                    .allocator = self.allocator,
                };
            }
            self.pos += 1;
        }

        // 未找到结束标记，返回剩余内容作为注释
        const value = self.input[start..];
        self.pos = self.input.len;
        const comment = try self.allocator.dupe(u8, value);
        return Token{
            .token_type = .comment,
            .data = .{ .comment = comment },
            .allocator = self.allocator,
        };
    }

    fn parseString(self: *Self, quote: u8) !Token {
        self.pos += 1; // 跳过开始引号
        const start = self.pos;
        var escaped = false;

        while (self.pos < self.input.len) {
            const ch = self.input[self.pos];
            if (escaped) {
                escaped = false;
                self.pos += 1;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                self.pos += 1;
                continue;
            }
            if (ch == quote) {
                const value = self.input[start..self.pos];
                self.pos += 1; // 跳过结束引号
                const str = try self.allocator.dupe(u8, value);
                return Token{
                    .token_type = .string,
                    .data = .{ .string = str },
                    .allocator = self.allocator,
                };
            }
            self.pos += 1;
        }

        // 未找到结束引号，返回剩余内容
        const value = self.input[start..];
        self.pos = self.input.len;
        const str = try self.allocator.dupe(u8, value);
        return Token{
            .token_type = .string,
            .data = .{ .string = str },
            .allocator = self.allocator,
        };
    }

    fn parseNumber(self: *Self) !Token {
        const start = self.pos;
        var has_dot = false;

        // 解析数字部分
        while (self.pos < self.input.len) {
            const ch = self.input[self.pos];
            if (string.isDigit(ch)) {
                self.pos += 1;
            } else if (ch == '.' and !has_dot) {
                has_dot = true;
                self.pos += 1;
            } else {
                break;
            }
        }

        const num_str = self.input[start..self.pos];
        const num = try std.fmt.parseFloat(f32, num_str);

        // 检查是否有单位
        if (self.pos < self.input.len) {
            const ch = self.input[self.pos];
            if (ch == '%') {
                self.pos += 1;
                return Token{
                    .token_type = .percentage,
                    .data = .{ .percentage = num },
                };
            }

            // 检查是否是标识符（单位）
            if (string.isAlpha(ch)) {
                const unit_start = self.pos;
                while (self.pos < self.input.len and string.isAlnum(self.input[self.pos])) {
                    self.pos += 1;
                }
                const unit = self.input[unit_start..self.pos];
                const unit_dup = try self.allocator.dupe(u8, unit);
                return Token{
                    .token_type = .dimension,
                    .data = .{
                        .dimension = .{
                            .value = num,
                            .unit = unit_dup,
                        },
                    },
                    .allocator = self.allocator,
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

        // 解析标识符
        while (self.pos < self.input.len) {
            const ch = self.input[self.pos];
            if (string.isAlnum(ch) or ch == '_' or ch == '-') {
                self.pos += 1;
            } else {
                break;
            }
        }

        const value = self.input[start..self.pos];

        // 检查是否是函数
        if (self.pos < self.input.len and self.input[self.pos] == '(') {
            const func = try self.allocator.dupe(u8, value);
            return Token{
                .token_type = .function,
                .data = .{ .function = func },
                .allocator = self.allocator,
            };
        }

        const ident = try self.allocator.dupe(u8, value);
        return Token{
            .token_type = .ident,
            .data = .{ .ident = ident },
            .allocator = self.allocator,
        };
    }
};
