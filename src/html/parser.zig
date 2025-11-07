const std = @import("std");
const dom = @import("dom");
const tokenizer = @import("tokenizer");
const string = @import("string");

/// HTML5解析器
pub const Parser = struct {
    tokenizer: tokenizer.Tokenizer,
    document: *dom.Document,
    allocator: std.mem.Allocator,
    open_elements: std.ArrayList(*dom.Node),
    open_elements_allocator: std.mem.Allocator,
    insertion_mode: InsertionMode = .initial,

    const Self = @This();

    /// 插入模式（HTML5规范）
    const InsertionMode = enum {
        initial,
        before_html,
        before_head,
        in_head,
        in_head_noscript,
        after_head,
        in_body,
        text,
        in_table,
        in_table_text,
        in_caption,
        in_column_group,
        in_table_body,
        in_row,
        in_cell,
        in_select,
        in_template,
        after_body,
        in_frameset,
        after_frameset,
        after_after_body,
        after_after_frameset,
    };

    pub fn init(input: []const u8, document: *dom.Document, allocator: std.mem.Allocator) Self {
        return .{
            .tokenizer = tokenizer.Tokenizer.init(input, allocator),
            .document = document,
            .allocator = allocator,
            .open_elements = std.ArrayList(*dom.Node).init(allocator),
            .open_elements_allocator = allocator,
        };
    }

    /// 解析HTML文档
    pub fn parse(self: *Self) !void {
        while (true) {
            const token_opt = try self.tokenizer.next();
            var token = token_opt orelse break;
            defer token.deinit();

            if (token.token_type == .eof) {
                break;
            }

            try self.processToken(token);
        }
    }

    fn processToken(self: *Self, tok: tokenizer.Token) !void {
        switch (self.insertion_mode) {
            .initial => try self.handleInitial(tok),
            .before_html => try self.handleBeforeHtml(tok),
            .before_head => try self.handleBeforeHead(tok),
            .in_head => try self.handleInHead(tok),
            .after_head => try self.handleAfterHead(tok),
            .in_body => try self.handleInBody(tok),
            .text => try self.handleText(tok),
            .after_body => try self.handleAfterBody(tok),
            else => {
                // 简化处理：其他模式暂时使用in_body逻辑
                try self.handleInBody(tok);
            },
        }
    }

    fn handleInitial(self: *Self, tok: tokenizer.Token) !void {
        switch (tok.token_type) {
            .doctype => {
                // 处理DOCTYPE，进入before_html模式
                self.insertion_mode = .before_html;
            },
            .comment => {
                // DOCTYPE前的注释，添加到document
                const comment_node = try self.createCommentNode(tok.data.comment);
                try self.document.node.appendChild(comment_node, self.allocator);
            },
            else => {
                // 没有DOCTYPE，进入quirks模式，但仍继续解析
                self.insertion_mode = .before_html;
                try self.handleBeforeHtml(tok);
            },
        }
    }

    fn handleBeforeHtml(self: *Self, tok: tokenizer.Token) !void {
        switch (tok.token_type) {
            .doctype, .comment => {
                // 忽略
            },
            .start_tag => {
                if (std.mem.eql(u8, tok.data.start_tag.name, "html")) {
                    const html_node = try self.createElementNode(tok.data.start_tag);
                    try self.document.node.appendChild(html_node, self.allocator);
                    try self.open_elements.append(html_node);
                    self.insertion_mode = .before_head;
                } else {
                    // 隐式创建html元素
                    const html_node = try self.createElement("html");
                    try self.document.node.appendChild(html_node, self.allocator);
                    try self.open_elements.append(html_node);
                    self.insertion_mode = .before_head;
                    try self.handleBeforeHead(tok);
                }
            },
            else => {
                // 隐式创建html元素
                const html_node = try self.createElement("html");
                try self.document.node.appendChild(html_node, self.allocator);
                try self.open_elements.append(html_node);
                self.insertion_mode = .before_head;
                try self.handleBeforeHead(tok);
            },
        }
    }

    fn handleBeforeHead(self: *Self, tok: tokenizer.Token) !void {
        switch (tok.token_type) {
            .comment => {
                const comment_node = try self.createCommentNode(tok.data.comment);
                try self.currentNode().appendChild(comment_node, self.allocator);
            },
            .start_tag => {
                if (std.mem.eql(u8, tok.data.start_tag.name, "head")) {
                    const head_node = try self.createElementNode(tok.data.start_tag);
                    try self.currentNode().appendChild(head_node, self.allocator);
                    try self.open_elements.append(head_node);
                    self.insertion_mode = .in_head;
                } else {
                    // 隐式创建head元素
                    const head_node = try self.createElement("head");
                    try self.currentNode().appendChild(head_node, self.allocator);
                    try self.open_elements.append(head_node);
                    self.insertion_mode = .in_head;
                    try self.handleInHead(tok);
                }
            },
            .end_tag => {
                if (std.mem.eql(u8, tok.data.end_tag.name, "head") or
                    std.mem.eql(u8, tok.data.end_tag.name, "body") or
                    std.mem.eql(u8, tok.data.end_tag.name, "html") or
                    std.mem.eql(u8, tok.data.end_tag.name, "br"))
                {
                    // 隐式创建head元素
                    const head_node = try self.createElement("head");
                    try self.currentNode().appendChild(head_node, self.allocator);
                    try self.open_elements.append(head_node);
                    self.insertion_mode = .in_head;
                    try self.handleInHead(tok);
                }
            },
            else => {
                // 隐式创建head元素
                const head_node = try self.createElement("head");
                try self.currentNode().appendChild(head_node, self.allocator);
                try self.open_elements.append(head_node);
                self.insertion_mode = .in_head;
                try self.handleInHead(tok);
            },
        }
    }

    fn handleInHead(self: *Self, tok: tokenizer.Token) !void {
        switch (tok.token_type) {
            .comment => {
                const comment_node = try self.createCommentNode(tok.data.comment);
                try self.currentNode().appendChild(comment_node, self.allocator);
            },
            .start_tag => {
                if (std.mem.eql(u8, tok.data.start_tag.name, "head")) {
                    // 错误：嵌套head标签
                } else if (std.mem.eql(u8, tok.data.start_tag.name, "title") or
                    std.mem.eql(u8, tok.data.start_tag.name, "style") or
                    std.mem.eql(u8, tok.data.start_tag.name, "script") or
                    std.mem.eql(u8, tok.data.start_tag.name, "meta") or
                    std.mem.eql(u8, tok.data.start_tag.name, "link") or
                    std.mem.eql(u8, tok.data.start_tag.name, "base"))
                {
                    const node = try self.createElementNode(tok.data.start_tag);
                    try self.currentNode().appendChild(node, self.allocator);
                    if (std.mem.eql(u8, tok.data.start_tag.name, "style") or
                        std.mem.eql(u8, tok.data.start_tag.name, "script") or
                        std.mem.eql(u8, tok.data.start_tag.name, "title"))
                    {
                        try self.open_elements.append(node);
                        self.insertion_mode = .text;
                    }
                } else {
                    // 其他标签，关闭head，进入after_head
                    try self.closeHead();
                    try self.handleAfterHead(tok);
                }
            },
            .end_tag => {
                if (std.mem.eql(u8, tok.data.end_tag.name, "head")) {
                    _ = self.open_elements.pop();
                    self.insertion_mode = .after_head;
                } else {
                    // 其他结束标签，关闭head
                    try self.closeHead();
                    try self.handleAfterHead(tok);
                }
            },
            else => {
                // 关闭head，进入after_head
                try self.closeHead();
                try self.handleAfterHead(tok);
            },
        }
    }

    fn handleAfterHead(self: *Self, tok: tokenizer.Token) !void {
        switch (tok.token_type) {
            .comment => {
                const comment_node = try self.createCommentNode(tok.data.comment);
                try self.currentNode().appendChild(comment_node, self.allocator);
            },
            .start_tag => {
                if (std.mem.eql(u8, tok.data.start_tag.name, "body")) {
                    const body_node = try self.createElementNode(tok.data.start_tag);
                    try self.currentNode().appendChild(body_node, self.allocator);
                    try self.open_elements.append(body_node);
                    self.insertion_mode = .in_body;
                } else if (std.mem.eql(u8, tok.data.start_tag.name, "html")) {
                    // 错误：嵌套html标签
                } else {
                    // 隐式创建body元素
                    const body_node = try self.createElement("body");
                    try self.currentNode().appendChild(body_node, self.allocator);
                    try self.open_elements.append(body_node);
                    self.insertion_mode = .in_body;
                    try self.handleInBody(tok);
                }
            },
            .end_tag => {
                if (std.mem.eql(u8, tok.data.end_tag.name, "body") or
                    std.mem.eql(u8, tok.data.end_tag.name, "html") or
                    std.mem.eql(u8, tok.data.end_tag.name, "br"))
                {
                    // 隐式创建body元素
                    const body_node = try self.createElement("body");
                    try self.currentNode().appendChild(body_node, self.allocator);
                    try self.open_elements.append(body_node);
                    self.insertion_mode = .in_body;
                    try self.handleInBody(tok);
                }
            },
            else => {
                // 隐式创建body元素
                const body_node = try self.createElement("body");
                try self.currentNode().appendChild(body_node, self.allocator);
                try self.open_elements.append(body_node);
                self.insertion_mode = .in_body;
                try self.handleInBody(tok);
            },
        }
    }

    fn handleInBody(self: *Self, tok: tokenizer.Token) !void {
        switch (tok.token_type) {
            .text => {
                const text_node = try self.createTextNode(tok.data.text);
                try self.currentNode().appendChild(text_node, self.allocator);
            },
            .comment => {
                const comment_node = try self.createCommentNode(tok.data.comment);
                try self.currentNode().appendChild(comment_node, self.allocator);
            },
            .start_tag => {
                const tag_name = tok.data.start_tag.name;

                // 特殊标签处理
                if (std.mem.eql(u8, tag_name, "script")) {
                    const script_node = try self.createElementNode(tok.data.start_tag);
                    try self.currentNode().appendChild(script_node, self.allocator);
                    try self.open_elements.append(script_node);
                    self.insertion_mode = .text;
                } else if (std.mem.eql(u8, tag_name, "style")) {
                    const style_node = try self.createElementNode(tok.data.start_tag);
                    try self.currentNode().appendChild(style_node, self.allocator);
                    try self.open_elements.append(style_node);
                    self.insertion_mode = .text;
                } else if (isVoidElement(tag_name)) {
                    // 自闭合元素
                    const node = try self.createElementNode(tok.data.start_tag);
                    try self.currentNode().appendChild(node, self.allocator);
                } else {
                    const node = try self.createElementNode(tok.data.start_tag);
                    try self.currentNode().appendChild(node, self.allocator);
                    try self.open_elements.append(node);
                }
            },
            .end_tag => {
                const tag_name = tok.data.end_tag.name;

                // 查找匹配的开始标签
                var i = self.open_elements.items.len;
                while (i > 0) {
                    i -= 1;
                    const node = self.open_elements.items[i];
                    if (node.asElement()) |elem| {
                        if (std.mem.eql(u8, elem.tag_name, tag_name)) {
                            // 关闭所有中间的元素
                            while (self.open_elements.items.len > i + 1) {
                                _ = self.open_elements.pop();
                            }
                            _ = self.open_elements.pop();
                            break;
                        }
                    }
                }
            },
            .self_closing_tag => {
                const node = try self.createElementNode(tok.data.self_closing_tag);
                try self.currentNode().appendChild(node, self.allocator);
            },
            else => {},
        }
    }

    fn handleText(self: *Self, tok: tokenizer.Token) !void {
        switch (tok.token_type) {
            .text => {
                const text_node = try self.createTextNode(tok.data.text);
                try self.currentNode().appendChild(text_node, self.allocator);
            },
            .end_tag => {
                _ = self.open_elements.pop();
                self.insertion_mode = .in_body;
            },
            else => {
                self.insertion_mode = .in_body;
                try self.handleInBody(tok);
            },
        }
    }

    fn handleAfterBody(self: *Self, tok: tokenizer.Token) !void {
        switch (tok.token_type) {
            .end_tag => {
                if (std.mem.eql(u8, tok.data.end_tag.name, "html")) {
                    // 进入after_after_body模式
                }
            },
            .eof => {},
            else => {
                // 错误恢复：回到in_body模式
                self.insertion_mode = .in_body;
                try self.handleInBody(tok);
            },
        }
    }

    fn currentNode(self: *Self) *dom.Node {
        if (self.open_elements.items.len > 0) {
            return self.open_elements.items[self.open_elements.items.len - 1];
        }
        return &self.document.node;
    }

    fn createElement(self: *Self, tag_name: []const u8) !*dom.Node {
        const tag_owned = try self.allocator.dupe(u8, tag_name);
        const node = try self.allocator.create(dom.Node);
        node.* = .{
            .node_type = .element,
            .data = .{
                .element = dom.ElementData.init(self.allocator, tag_owned),
            },
        };
        return node;
    }

    fn createElementNode(self: *Self, tag_data: tokenizer.Token.TagData) !*dom.Node {
        const tag_owned = try self.allocator.dupe(u8, tag_data.name);
        const node = try self.allocator.create(dom.Node);
        node.* = .{
            .node_type = .element,
            .data = .{
                .element = dom.ElementData.init(self.allocator, tag_owned),
            },
        };

        // 复制属性
        var it = tag_data.attributes.iterator();
        while (it.next()) |entry| {
            try node.data.element.setAttribute(entry.key_ptr.*, entry.value_ptr.*, self.allocator);
        }

        return node;
    }

    fn createTextNode(self: *Self, text: []const u8) !*dom.Node {
        const text_owned = try self.allocator.dupe(u8, text);
        const node = try self.allocator.create(dom.Node);
        node.* = .{
            .node_type = .text,
            .data = .{ .text = text_owned },
        };
        return node;
    }

    fn createCommentNode(self: *Self, comment: []const u8) !*dom.Node {
        const comment_owned = try self.allocator.dupe(u8, comment);
        const node = try self.allocator.create(dom.Node);
        node.* = .{
            .node_type = .comment,
            .data = .{ .comment = comment_owned },
        };
        return node;
    }

    fn closeHead(self: *Self) !void {
        // 查找并关闭head元素
        var i = self.open_elements.items.len;
        while (i > 0) {
            i -= 1;
            const node = self.open_elements.items[i];
            if (node.asElement()) |elem| {
                if (std.mem.eql(u8, elem.tag_name, "head")) {
                    while (self.open_elements.items.len > i + 1) {
                        _ = self.open_elements.pop();
                    }
                    _ = self.open_elements.pop();
                    break;
                }
            }
        }
    }

    fn isVoidElement(tag_name: []const u8) bool {
        const void_elements = [_][]const u8{
            "area",  "base", "br",   "col",   "embed",  "hr",    "img",
            "input", "link", "meta", "param", "source", "track", "wbr",
        };
        for (void_elements) |void_tag| {
            if (std.mem.eql(u8, tag_name, void_tag)) {
                return true;
            }
        }
        return false;
    }

    pub fn deinit(self: *Self) void {
        self.open_elements.deinit();
    }
};
