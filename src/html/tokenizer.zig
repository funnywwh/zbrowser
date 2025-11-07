const std = @import("std");
const string = @import("string");

/// HTML Token类型
pub const TokenType = enum {
    doctype,
    start_tag,
    end_tag,
    self_closing_tag,
    text,
    comment,
    cdata,
    eof,
};

/// HTML Token
pub const Token = struct {
    token_type: TokenType,
    data: Data,
    allocator: ?std.mem.Allocator = null, // 用于释放内存

    pub const Data = union(TokenType) {
        doctype: DoctypeData,
        start_tag: TagData,
        end_tag: TagData,
        self_closing_tag: TagData,
        text: []const u8,
        comment: []const u8,
        cdata: []const u8,
        eof: void,
    };

    pub const TagData = struct {
        name: []const u8,
        attributes: std.StringHashMap([]const u8),
    };

    pub const DoctypeData = struct {
        name: ?[]const u8,
        public_id: ?[]const u8,
        system_id: ?[]const u8,
        force_quirks: bool,
    };

    /// 释放token占用的内存
    pub fn deinit(self: *Token) void {
        if (self.allocator) |alloc| {
            switch (self.token_type) {
                .start_tag, .end_tag, .self_closing_tag => {
                    const tag_data = switch (self.token_type) {
                        .start_tag => &self.data.start_tag,
                        .end_tag => &self.data.end_tag,
                        .self_closing_tag => &self.data.self_closing_tag,
                        else => unreachable,
                    };
                    alloc.free(tag_data.name);
                    var it = tag_data.attributes.iterator();
                    while (it.next()) |entry| {
                        alloc.free(entry.key_ptr.*);
                        alloc.free(entry.value_ptr.*);
                    }
                    tag_data.attributes.deinit();
                },
                .text, .comment, .cdata => {
                    const text_data = switch (self.token_type) {
                        .text => self.data.text,
                        .comment => self.data.comment,
                        .cdata => self.data.cdata,
                        else => unreachable,
                    };
                    alloc.free(text_data);
                },
                .doctype => {
                    if (self.data.doctype.name) |name| {
                        alloc.free(name);
                    }
                    if (self.data.doctype.public_id) |id| {
                        alloc.free(id);
                    }
                    if (self.data.doctype.system_id) |id| {
                        alloc.free(id);
                    }
                },
                .eof => {},
            }
        }
    }
};

/// HTML词法分析器
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
    pub fn next(self: *Self) !?Token {
        if (self.pos >= self.input.len) {
            return Token{
                .token_type = .eof,
                .data = .{ .eof = {} },
                .allocator = null,
            };
        }

        // 跳过空白字符（在标签外）
        self.skipWhitespace();

        if (self.pos >= self.input.len) {
            return Token{
                .token_type = .eof,
                .data = .{ .eof = {} },
                .allocator = null,
            };
        }

        // 检查是否是标签
        if (self.input[self.pos] == '<') {
            return try self.parseTag();
        }

        // 否则是文本
        return try self.parseText();
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.input.len and string.isWhitespace(self.input[self.pos])) {
            self.pos += 1;
        }
    }

    fn parseTag(self: *Self) !Token {
        self.pos += 1; // 跳过 '<'

        if (self.pos >= self.input.len) {
            return error.UnexpectedEOF;
        }

        // 检查是否是注释
        if (self.pos + 2 < self.input.len and std.mem.eql(u8, self.input[self.pos .. self.pos + 3], "!--")) {
            return try self.parseComment();
        }

        // 检查是否是CDATA
        if (self.pos + 7 < self.input.len and std.mem.eql(u8, self.input[self.pos .. self.pos + 8], "![CDATA[")) {
            return try self.parseCDATA();
        }

        // 检查是否是DOCTYPE
        if (self.pos + 8 < self.input.len and std.mem.eql(u8, self.input[self.pos .. self.pos + 9], "!DOCTYPE")) {
            return try self.parseDoctype();
        }

        // 检查是否是结束标签
        const is_end_tag = self.input[self.pos] == '/';
        if (is_end_tag) {
            self.pos += 1;
        }

        // 解析标签名
        const name_start = self.pos;
        while (self.pos < self.input.len and !string.isWhitespace(self.input[self.pos]) and
            self.input[self.pos] != '>' and self.input[self.pos] != '/')
        {
            self.pos += 1;
        }

        if (self.pos == name_start) {
            return error.InvalidTag;
        }

        const tag_name = try self.allocator.dupe(u8, self.input[name_start..self.pos]);
        errdefer self.allocator.free(tag_name);

        // 解析属性
        var attributes = std.StringHashMap([]const u8).init(self.allocator);
        errdefer {
            var it = attributes.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            attributes.deinit();
        }

        self.skipWhitespace();

        // 检查是否是自闭合标签
        var is_self_closing = false;
        while (self.pos < self.input.len and self.input[self.pos] != '>') {
            if (self.input[self.pos] == '/') {
                is_self_closing = true;
                self.pos += 1;
                if (self.pos < self.input.len and self.input[self.pos] == '>') {
                    break;
                }
                continue;
            }

            // 解析属性
            const attr = try self.parseAttribute();
            const key = try self.allocator.dupe(u8, attr.key);
            const value = try self.allocator.dupe(u8, attr.value);
            try attributes.put(key, value);
            self.skipWhitespace();
        }

        if (self.pos >= self.input.len or self.input[self.pos] != '>') {
            return error.UnexpectedEOF;
        }
        self.pos += 1; // 跳过 '>'

        const tag_data = Token.TagData{
            .name = tag_name,
            .attributes = attributes,
        };

        if (is_end_tag) {
            return Token{
                .token_type = .end_tag,
                .data = .{ .end_tag = tag_data },
                .allocator = self.allocator,
            };
        } else if (is_self_closing) {
            return Token{
                .token_type = .self_closing_tag,
                .data = .{ .self_closing_tag = tag_data },
                .allocator = self.allocator,
            };
        } else {
            return Token{
                .token_type = .start_tag,
                .data = .{ .start_tag = tag_data },
                .allocator = self.allocator,
            };
        }
    }

    fn parseAttribute(self: *Self) !struct { key: []const u8, value: []const u8 } {
        // 解析属性名
        const key_start = self.pos;
        while (self.pos < self.input.len and !string.isWhitespace(self.input[self.pos]) and
            self.input[self.pos] != '=' and self.input[self.pos] != '>' and self.input[self.pos] != '/')
        {
            self.pos += 1;
        }

        const key = self.input[key_start..self.pos];
        self.skipWhitespace();

        // 检查是否有值
        if (self.pos >= self.input.len or self.input[self.pos] != '=') {
            return .{ .key = key, .value = "" };
        }

        self.pos += 1; // 跳过 '='
        self.skipWhitespace();

        // 解析属性值
        const quote = if (self.pos < self.input.len and (self.input[self.pos] == '"' or self.input[self.pos] == '\'')) self.input[self.pos] else 0;
        if (quote != 0) {
            self.pos += 1; // 跳过引号
            const value_start = self.pos;
            while (self.pos < self.input.len and self.input[self.pos] != quote) {
                self.pos += 1;
            }
            const value = self.input[value_start..self.pos];
            if (self.pos < self.input.len) {
                self.pos += 1; // 跳过结束引号
            }
            return .{ .key = key, .value = value };
        } else {
            // 无引号的值
            const value_start = self.pos;
            while (self.pos < self.input.len and !string.isWhitespace(self.input[self.pos]) and
                self.input[self.pos] != '>' and self.input[self.pos] != '/')
            {
                self.pos += 1;
            }
            return .{ .key = key, .value = self.input[value_start..self.pos] };
        }
    }

    fn parseText(self: *Self) !Token {
        const start = self.pos;
        while (self.pos < self.input.len and self.input[self.pos] != '<') {
            self.pos += 1;
        }

        const text = try self.allocator.dupe(u8, self.input[start..self.pos]);
        return Token{
            .token_type = .text,
            .data = .{ .text = text },
            .allocator = self.allocator,
        };
    }

    fn parseComment(self: *Self) !Token {
        self.pos += 3; // 跳过 "!--"
        const start = self.pos;

        // 查找注释结束标记 "--"
        while (self.pos + 1 < self.input.len) {
            if (self.input[self.pos] == '-' and self.input[self.pos + 1] == '-') {
                if (self.pos + 2 < self.input.len and self.input[self.pos + 2] == '>') {
                    const comment = try self.allocator.dupe(u8, self.input[start..self.pos]);
                    self.pos += 3; // 跳过 "-->"
                    return Token{
                        .token_type = .comment,
                        .data = .{ .comment = comment },
                        .allocator = self.allocator,
                    };
                }
            }
            self.pos += 1;
        }

        return error.UnexpectedEOF;
    }

    fn parseCDATA(self: *Self) !Token {
        self.pos += 8; // 跳过 "![CDATA["
        const start = self.pos;

        // 查找CDATA结束标记 "]]>"
        while (self.pos + 2 < self.input.len) {
            if (self.input[self.pos] == ']' and self.input[self.pos + 1] == ']' and self.input[self.pos + 2] == '>') {
                const cdata = try self.allocator.dupe(u8, self.input[start..self.pos]);
                self.pos += 3; // 跳过 "]]>"
                return Token{
                    .token_type = .cdata,
                    .data = .{ .cdata = cdata },
                    .allocator = self.allocator,
                };
            }
            self.pos += 1;
        }

        return error.UnexpectedEOF;
    }

    fn parseDoctype(self: *Self) !Token {
        self.pos += 9; // 跳过 "!DOCTYPE"
        self.skipWhitespace();

        // 解析DOCTYPE名称
        const name_start = self.pos;
        while (self.pos < self.input.len and !string.isWhitespace(self.input[self.pos]) and self.input[self.pos] != '>') {
            self.pos += 1;
        }
        const name = if (self.pos > name_start) try self.allocator.dupe(u8, self.input[name_start..self.pos]) else null;
        errdefer if (name) |n| self.allocator.free(n);

        self.skipWhitespace();

        // 简化处理：不完整解析PUBLIC和SYSTEM ID
        const public_id: ?[]const u8 = null;
        const system_id: ?[]const u8 = null;
        var force_quirks = false;

        // 查找结束标记
        while (self.pos < self.input.len and self.input[self.pos] != '>') {
            self.pos += 1;
        }

        if (self.pos < self.input.len) {
            self.pos += 1; // 跳过 '>'
        } else {
            force_quirks = true;
        }

        return Token{
            .token_type = .doctype,
            .data = .{
                .doctype = .{
                    .name = name,
                    .public_id = public_id,
                    .system_id = system_id,
                    .force_quirks = force_quirks,
                },
            },
            .allocator = self.allocator,
        };
    }
};
