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
            .open_elements = std.ArrayList(*dom.Node){},
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
                    try self.open_elements.append(self.allocator, html_node);
                    self.insertion_mode = .before_head;
                } else {
                    // 隐式创建html元素
                    const html_node = try self.createElement("html");
                    try self.document.node.appendChild(html_node, self.allocator);
                    try self.open_elements.append(self.allocator, html_node);
                    self.insertion_mode = .before_head;
                    try self.handleBeforeHead(tok);
                }
            },
            else => {
                // 隐式创建html元素
                const html_node = try self.createElement("html");
                try self.document.node.appendChild(html_node, self.allocator);
                try self.open_elements.append(self.allocator, html_node);
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
                    try self.open_elements.append(self.allocator, head_node);
                    self.insertion_mode = .in_head;
                } else {
                    // 隐式创建head元素
                    const head_node = try self.createElement("head");
                    try self.currentNode().appendChild(head_node, self.allocator);
                    try self.open_elements.append(self.allocator, head_node);
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
                    try self.open_elements.append(self.allocator, head_node);
                    self.insertion_mode = .in_head;
                    try self.handleInHead(tok);
                }
            },
            else => {
                // 隐式创建head元素
                const head_node = try self.createElement("head");
                try self.currentNode().appendChild(head_node, self.allocator);
                try self.open_elements.append(self.allocator, head_node);
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
                        try self.open_elements.append(self.allocator, node);
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
                    // 查找并移除 head 元素（可能不在栈顶）
                    var i = self.open_elements.items.len;
                    while (i > 0) {
                        i -= 1;
                        const node = self.open_elements.items[i];
                        if (node.asElement()) |elem| {
                            if (std.mem.eql(u8, elem.tag_name, "head")) {
                                // 关闭所有中间的元素
                                while (self.open_elements.items.len > i + 1) {
                                    _ = self.open_elements.pop();
                                }
                                _ = self.open_elements.pop();
                                self.insertion_mode = .after_head;
                                break;
                            }
                        }
                    }
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
                // 确保 head 已经被关闭
                try self.closeHead();
                // 找到 html 元素，将 comment 添加到 html 下
                var html_node: ?*dom.Node = null;
                for (self.open_elements.items) |node| {
                    if (node.asElement()) |elem| {
                        if (std.mem.eql(u8, elem.tag_name, "html")) {
                            html_node = node;
                            break;
                        }
                    }
                }
                const comment_node = try self.createCommentNode(tok.data.comment);
                if (html_node) |html| {
                    try html.appendChild(comment_node, self.allocator);
                } else {
                    // 如果找不到 html，添加到 document
                    try self.document.node.appendChild(comment_node, self.allocator);
                }
            },
            .text => {
                // 跳过空白文本（可能是换行符等）
                const text_content = tok.data.text;
                var is_whitespace_only = true;
                for (text_content) |c| {
                    if (!string.isWhitespace(c)) {
                        is_whitespace_only = false;
                        break;
                    }
                }
                if (is_whitespace_only) {
                    // 忽略空白文本，继续解析下一个token
                    return;
                }
                // 非空白文本，隐式创建body元素
                // 确保 head 已经被关闭
                try self.closeHead();
                // 找到 html 元素，将 body 添加到 html 下
                var html_node: ?*dom.Node = null;
                for (self.open_elements.items) |node| {
                    if (node.asElement()) |elem| {
                        if (std.mem.eql(u8, elem.tag_name, "html")) {
                            html_node = node;
                            break;
                        }
                    }
                }
                const body_node = try self.createElement("body");
                if (html_node) |html| {
                    try html.appendChild(body_node, self.allocator);
                } else {
                    // 如果找不到 html，添加到 document
                    try self.document.node.appendChild(body_node, self.allocator);
                }
                try self.open_elements.append(self.allocator, body_node);
                self.insertion_mode = .in_body;
                try self.handleInBody(tok);
            },
            .start_tag => {
                if (std.mem.eql(u8, tok.data.start_tag.name, "body")) {
                    // 确保 head 已经被关闭（如果还在 open_elements 中，先关闭它）
                    try self.closeHead();
                    // 检查 body 是否已经存在
                    const existing_body = self.document.getBody();
                    if (existing_body) |body| {
                        // body 已经存在，更新属性
                        if (body.asElement()) |elem| {
                            var it = tok.data.start_tag.attributes.iterator();
                            while (it.next()) |entry| {
                                try elem.setAttribute(entry.key_ptr.*, entry.value_ptr.*, self.allocator);
                            }
                        }
                        // 确保 body 在 open_elements 中，并且是栈顶元素（这样后续元素才能正确添加到 body 中）
                        var found_in_open = false;
                        var body_index: ?usize = null;
                        for (self.open_elements.items, 0..) |node, i| {
                            if (node == body) {
                                found_in_open = true;
                                body_index = i;
                                break;
                            }
                        }
                        if (!found_in_open) {
                            // body 不在 open_elements 中，添加到栈顶
                            try self.open_elements.append(self.allocator, body);
                        } else if (body_index) |idx| {
                            // body 在 open_elements 中，但可能不在栈顶
                            // 移除 body 之后的所有元素，然后将 body 移到栈顶
                            while (self.open_elements.items.len > idx + 1) {
                                _ = self.open_elements.pop();
                            }
                            // 如果 body 不在栈顶，将其移到栈顶
                            if (self.open_elements.items.len > 0 and self.open_elements.items[self.open_elements.items.len - 1] != body) {
                                _ = self.open_elements.pop();
                                try self.open_elements.append(self.allocator, body);
                            }
                        }
                        // 设置插入模式为 in_body，但不处理当前 token（body 标签本身不需要处理）
                        self.insertion_mode = .in_body;
                        // 注意：body 标签本身不需要添加到 DOM，因为它已经存在
                        // 后续的 token 会在 in_body 模式下处理
                    } else {
                        // body 不存在，创建新的 body 元素
                        var html_node: ?*dom.Node = null;
                        for (self.open_elements.items) |node| {
                            if (node.asElement()) |elem| {
                                if (std.mem.eql(u8, elem.tag_name, "html")) {
                                    html_node = node;
                                    break;
                                }
                            }
                        }
                        const body_node = try self.createElementNode(tok.data.start_tag);
                        if (html_node) |html| {
                            try html.appendChild(body_node, self.allocator);
                        } else {
                            // 如果找不到 html，添加到 document
                            try self.document.node.appendChild(body_node, self.allocator);
                        }
                        try self.open_elements.append(self.allocator, body_node);
                    }
                    self.insertion_mode = .in_body;
                } else if (std.mem.eql(u8, tok.data.start_tag.name, "html")) {
                    // 错误：嵌套html标签
                } else {
                    // 隐式创建body元素
                    // 确保 head 已经被关闭
                    try self.closeHead();
                    // 找到 html 元素，将 body 添加到 html 下
                    var html_node: ?*dom.Node = null;
                    for (self.open_elements.items) |node| {
                        if (node.asElement()) |elem| {
                            if (std.mem.eql(u8, elem.tag_name, "html")) {
                                html_node = node;
                                break;
                            }
                        }
                    }
                    const body_node = try self.createElement("body");
                    if (html_node) |html| {
                        try html.appendChild(body_node, self.allocator);
                    } else {
                        // 如果找不到 html，添加到 document
                        try self.document.node.appendChild(body_node, self.allocator);
                    }
                    try self.open_elements.append(self.allocator, body_node);
                    self.insertion_mode = .in_body;
                    try self.handleInBody(tok);
                }
            },
            .end_tag => {
                if (std.mem.eql(u8, tok.data.end_tag.name, "head")) {
                    // head 结束标签在 after_head 模式下不应该出现，但为了容错，忽略它
                    // head 应该已经在 in_head 模式下被关闭了
                } else if (std.mem.eql(u8, tok.data.end_tag.name, "body") or
                    std.mem.eql(u8, tok.data.end_tag.name, "html") or
                    std.mem.eql(u8, tok.data.end_tag.name, "br"))
                {
                    // 隐式创建body元素
                    // 确保 head 已经被关闭
                    try self.closeHead();
                    // 找到 html 元素，将 body 添加到 html 下
                    var html_node: ?*dom.Node = null;
                    for (self.open_elements.items) |node| {
                        if (node.asElement()) |elem| {
                            if (std.mem.eql(u8, elem.tag_name, "html")) {
                                html_node = node;
                                break;
                            }
                        }
                    }
                    const body_node = try self.createElement("body");
                    if (html_node) |html| {
                        try html.appendChild(body_node, self.allocator);
                    } else {
                        // 如果找不到 html，添加到 document
                        try self.document.node.appendChild(body_node, self.allocator);
                    }
                    try self.open_elements.append(self.allocator, body_node);
                    self.insertion_mode = .in_body;
                    try self.handleInBody(tok);
                }
            },
            else => {
                // 隐式创建body元素
                // 确保 head 已经被关闭
                try self.closeHead();
                // 找到 html 元素，将 body 添加到 html 下
                var html_node: ?*dom.Node = null;
                for (self.open_elements.items) |node| {
                    if (node.asElement()) |elem| {
                        if (std.mem.eql(u8, elem.tag_name, "html")) {
                            html_node = node;
                            break;
                        }
                    }
                }
                const body_node = try self.createElement("body");
                if (html_node) |html| {
                    try html.appendChild(body_node, self.allocator);
                } else {
                    // 如果找不到 html，添加到 document
                    try self.document.node.appendChild(body_node, self.allocator);
                }
                try self.open_elements.append(self.allocator, body_node);
                self.insertion_mode = .in_body;
                try self.handleInBody(tok);
            },
        }
    }

    fn handleInBody(self: *Self, tok: tokenizer.Token) !void {
        switch (tok.token_type) {
            .text => {
                // 检查文本内容是否只包含空白字符
                const text_content = tok.data.text;
                var is_whitespace_only = true;
                for (text_content) |c| {
                    if (!string.isWhitespace(c)) {
                        is_whitespace_only = false;
                        break;
                    }
                }

                // 如果只包含空白字符，仍然创建文本节点（用于布局）
                // 但可以跳过渲染（在渲染器中处理）
                const text_node = try self.createTextNode(text_content);
                try self.currentNode().appendChild(text_node, self.allocator);
            },
            .comment => {
                const comment_node = try self.createCommentNode(tok.data.comment);
                try self.currentNode().appendChild(comment_node, self.allocator);
            },
            .start_tag => {
                const tag_name = tok.data.start_tag.name;

                // 跳过 DOCTYPE 标签（如果被错误解析为 start_tag）
                // DOCTYPE 应该被 tokenizer 识别为 .doctype token，不应该进入这里
                if (std.mem.eql(u8, tag_name, "!DOCTYPE")) {
                    // 忽略 DOCTYPE start_tag（这不应该发生，但为了容错）
                    return;
                }

                // 特殊处理 html、head 和 body 标签（不应该在 body 内出现）
                if (std.mem.eql(u8, tag_name, "html")) {
                    // html 标签不应该在 body 内出现，这是错误
                    // 忽略它，不创建元素节点
                    return;
                }
                if (std.mem.eql(u8, tag_name, "head")) {
                    // head 标签不应该在 body 内出现，这是错误
                    // 忽略它，不创建元素节点
                    return;
                }
                if (std.mem.eql(u8, tag_name, "body")) {
                    // body 标签在 body 内出现，根据 HTML5 规范，应该更新现有 body 元素的属性
                    const existing_body = self.document.getBody();
                    if (existing_body) |body| {
                        if (body.asElement()) |elem| {
                            // 更新 body 元素的属性
                            var it = tok.data.start_tag.attributes.iterator();
                            while (it.next()) |entry| {
                                try elem.setAttribute(entry.key_ptr.*, entry.value_ptr.*, self.allocator);
                            }
                        }
                    }
                    // 不创建新的 body 元素，也不抛出错误
                    return;
                }

                // 特殊标签处理
                if (std.mem.eql(u8, tag_name, "script")) {
                    const script_node = try self.createElementNode(tok.data.start_tag);
                    try self.currentNode().appendChild(script_node, self.allocator);
                    try self.open_elements.append(self.allocator, script_node);
                    self.insertion_mode = .text;
                } else if (std.mem.eql(u8, tag_name, "style")) {
                    const style_node = try self.createElementNode(tok.data.start_tag);
                    try self.currentNode().appendChild(style_node, self.allocator);
                    try self.open_elements.append(self.allocator, style_node);
                    self.insertion_mode = .text;
                } else if (isVoidElement(tag_name)) {
                    // 自闭合元素（包括 meta、link 等）
                    // 如果 meta 或 link 在 body 内出现，这通常是错误（它们应该在 head 内）
                    // 但为了容错，我们仍然创建元素节点
                    const node = try self.createElementNode(tok.data.start_tag);
                    try self.currentNode().appendChild(node, self.allocator);
                } else {
                    const node = try self.createElementNode(tok.data.start_tag);
                    try self.currentNode().appendChild(node, self.allocator);
                    try self.open_elements.append(self.allocator, node);
                }
            },
            .end_tag => {
                const tag_name = tok.data.end_tag.name;

                // 特殊处理 body 结束标签
                if (std.mem.eql(u8, tag_name, "body")) {
                    // 查找 body 元素并关闭它
                    var i = self.open_elements.items.len;
                    while (i > 0) {
                        i -= 1;
                        const node = self.open_elements.items[i];
                        if (node.asElement()) |elem| {
                            if (std.mem.eql(u8, elem.tag_name, "body")) {
                                // 关闭所有中间的元素
                                while (self.open_elements.items.len > i + 1) {
                                    _ = self.open_elements.pop();
                                }
                                _ = self.open_elements.pop();
                                self.insertion_mode = .after_body;
                                break;
                            }
                        }
                    }
                } else if (std.mem.eql(u8, tag_name, "html")) {
                    // html 结束标签：进入 after_body 模式（如果还在 in_body 模式）
                    // 注意：html 元素不应该被关闭，因为它是最外层的元素
                    // 如果当前在 body 内，应该先关闭 body，然后进入 after_body 模式
                    // 查找 body 元素
                    var found_body = false;
                    var i = self.open_elements.items.len;
                    while (i > 0) {
                        i -= 1;
                        const node = self.open_elements.items[i];
                        if (node.asElement()) |elem| {
                            if (std.mem.eql(u8, elem.tag_name, "body")) {
                                found_body = true;
                                // 关闭 body 及其之后的所有元素
                                while (self.open_elements.items.len > i + 1) {
                                    _ = self.open_elements.pop();
                                }
                                _ = self.open_elements.pop();
                                self.insertion_mode = .after_body;
                                break;
                            }
                        }
                    }
                    // 如果没有找到 body，直接进入 after_body 模式
                    if (!found_body) {
                        self.insertion_mode = .after_body;
                    }
                } else if (std.mem.eql(u8, tag_name, "head")) {
                    // head 结束标签不应该在 body 内出现，这是错误
                    // 但为了容错，我们尝试关闭 head 元素（如果它在 open_elements 中）
                    var i = self.open_elements.items.len;
                    while (i > 0) {
                        i -= 1;
                        const node = self.open_elements.items[i];
                        if (node.asElement()) |elem| {
                            if (std.mem.eql(u8, elem.tag_name, "head")) {
                                // 关闭所有中间的元素
                                while (self.open_elements.items.len > i + 1) {
                                    _ = self.open_elements.pop();
                                }
                                _ = self.open_elements.pop();
                                break;
                            }
                        }
                    }
                } else {
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
                // 检查是否在 head 内（通过检查 open_elements 中是否有 head）
                var in_head = false;
                for (self.open_elements.items) |node| {
                    if (node.asElement()) |elem| {
                        if (std.mem.eql(u8, elem.tag_name, "head")) {
                            in_head = true;
                            break;
                        }
                    }
                }
                if (in_head) {
                    self.insertion_mode = .in_head;
                    // 如果结束标签是 style、script 或 title，并且仍在 head 内，返回到 in_head 模式
                    // 这样后续的 </head> 标签可以被正确处理
                } else {
                    // 如果不在 head 内，检查是否在 after_head 模式（head 已关闭但 body 未开始）
                    // 这种情况下，应该返回到 after_head 模式，而不是 in_body 模式
                    // 但是，如果已经在 body 内，应该返回到 in_body 模式
                    // 为了简化，我们检查 open_elements 中是否有 body
                    var in_body = false;
                    for (self.open_elements.items) |node| {
                        if (node.asElement()) |elem| {
                            if (std.mem.eql(u8, elem.tag_name, "body")) {
                                in_body = true;
                                break;
                            }
                        }
                    }
                    if (in_body) {
                        self.insertion_mode = .in_body;
                    } else {
                        // 既不在 head 内，也不在 body 内，说明在 after_head 模式
                        self.insertion_mode = .after_head;
                    }
                }
            },
            else => {
                // 检查是否在 head 内
                var in_head = false;
                for (self.open_elements.items) |node| {
                    if (node.asElement()) |elem| {
                        if (std.mem.eql(u8, elem.tag_name, "head")) {
                            in_head = true;
                            break;
                        }
                    }
                }
                if (in_head) {
                    self.insertion_mode = .in_head;
                    try self.handleInHead(tok);
                } else {
                    // 如果不在 head 内，检查是否在 body 内
                    var in_body = false;
                    for (self.open_elements.items) |node| {
                        if (node.asElement()) |elem| {
                            if (std.mem.eql(u8, elem.tag_name, "body")) {
                                in_body = true;
                                break;
                            }
                        }
                    }
                    if (in_body) {
                        self.insertion_mode = .in_body;
                        try self.handleInBody(tok);
                    } else {
                        // 既不在 head 内，也不在 body 内，说明在 after_head 模式
                        self.insertion_mode = .after_head;
                        try self.handleAfterHead(tok);
                    }
                }
            },
        }
    }

    fn handleAfterBody(self: *Self, tok: tokenizer.Token) !void {
        switch (tok.token_type) {
            .comment => {
                // 注释添加到 document（body 之后）
                const comment_node = try self.createCommentNode(tok.data.comment);
                try self.document.node.appendChild(comment_node, self.allocator);
            },
            .text => {
                // body 之后的文本：检查是否只包含空白字符
                const text_content = tok.data.text;
                var is_whitespace_only = true;
                for (text_content) |c| {
                    if (!string.isWhitespace(c)) {
                        is_whitespace_only = false;
                        break;
                    }
                }
                if (is_whitespace_only) {
                    // 忽略空白文本
                    return;
                }
                // 非空白文本：错误恢复，回到 in_body 模式
                // 查找 body 元素，如果不存在则创建
                var found_body = false;
                for (self.open_elements.items) |node| {
                    if (node.asElement()) |elem| {
                        if (std.mem.eql(u8, elem.tag_name, "body")) {
                            found_body = true;
                            break;
                        }
                    }
                }
                if (!found_body) {
                    // 隐式创建 body 元素
                    const body_node = try self.createElement("body");
                    // 找到 html 元素，将 body 添加到 html 下
                    for (self.open_elements.items) |node| {
                        if (node.asElement()) |elem| {
                            if (std.mem.eql(u8, elem.tag_name, "html")) {
                                try node.appendChild(body_node, self.allocator);
                                try self.open_elements.append(self.allocator, body_node);
                                self.insertion_mode = .in_body;
                                try self.handleInBody(tok);
                                return;
                            }
                        }
                    }
                    // 如果找不到 html，添加到 document
                    try self.document.node.appendChild(body_node, self.allocator);
                    try self.open_elements.append(self.allocator, body_node);
                }
                self.insertion_mode = .in_body;
                try self.handleInBody(tok);
            },
            .end_tag => {
                if (std.mem.eql(u8, tok.data.end_tag.name, "html")) {
                    // 进入after_after_body模式
                    self.insertion_mode = .after_after_body;
                } else {
                    // 其他结束标签：错误恢复，回到 in_body 模式
                    self.insertion_mode = .in_body;
                    try self.handleInBody(tok);
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
        // ElementData.init 会复制 tag_name，所以直接传入 tag_name
        const node = try self.allocator.create(dom.Node);
        node.* = .{
            .node_type = .element,
            .data = .{
                .element = try dom.ElementData.init(self.allocator, tag_name),
            },
        };
        return node;
    }

    fn createElementNode(self: *Self, tag_data: tokenizer.Token.TagData) !*dom.Node {
        // ElementData.init 会复制 tag_name，所以直接传入 tag_data.name
        const node = try self.allocator.create(dom.Node);
        node.* = .{
            .node_type = .element,
            .data = .{
                .element = try dom.ElementData.init(self.allocator, tag_data.name),
            },
        };

        // 复制属性
        var it = tag_data.attributes.iterator();
        while (it.next()) |entry| {
            try node.data.element.setAttribute(entry.key_ptr.*, entry.value_ptr.*, self.allocator);
        }

        return node;
    }

    /// 解码HTML实体
    /// 支持命名实体（&lt;, &gt;, &amp;, &quot;, &apos;）和数字实体（&#123;, &#x1F;）
    fn decodeHtmlEntities(self: *Self, input: []const u8) ![]u8 {
        var result = std.ArrayList(u8){
            .items = &[_]u8{},
            .capacity = 0,
        };
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < input.len) {
            if (input[i] == '&') {
                // 查找实体结束符 ';'
                var j = i + 1;
                while (j < input.len and input[j] != ';' and input[j] != '&') {
                    j += 1;
                }

                if (j < input.len and input[j] == ';') {
                    // 找到完整的实体
                    const entity = input[i + 1 .. j];

                    // 解析实体
                    if (parseHtmlEntity(entity)) |decoded_char| {
                        try result.append(self.allocator, decoded_char);
                        i = j + 1; // 跳过整个实体包括 ';'
                        continue;
                    } else {
                        // 无法解析的实体，保留整个实体（包括&和;）
                        const full_entity = input[i .. j + 1];
                        for (full_entity) |char| {
                            try result.append(self.allocator, char);
                        }
                        i = j + 1;
                        continue;
                    }
                } else {
                    // 没有找到 ';'，不是有效的实体，保留原样
                    try result.append(self.allocator, '&');
                    i += 1;
                    continue;
                }
            } else {
                try result.append(self.allocator, input[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// 解析HTML实体
    /// 返回解码后的字符，如果无法解析则返回null
    fn parseHtmlEntity(entity: []const u8) ?u8 {
        // 命名实体
        if (std.mem.eql(u8, entity, "lt")) return '<';
        if (std.mem.eql(u8, entity, "gt")) return '>';
        if (std.mem.eql(u8, entity, "amp")) return '&';
        if (std.mem.eql(u8, entity, "quot")) return '"';
        if (std.mem.eql(u8, entity, "apos")) return '\'';

        // 数字实体：&#123; (十进制)
        if (entity.len > 1 and entity[0] == '#') {
            const num_str = entity[1..];
            if (std.fmt.parseInt(u21, num_str, 10)) |code_point| {
                if (code_point <= 0xFF) {
                    return @as(u8, @intCast(code_point));
                }
            } else |_| {
                // 解析失败，尝试十六进制
            }
        }

        // 十六进制实体：&#x1F; 或 &#X1F;
        if (entity.len > 2 and entity[0] == '#' and (entity[1] == 'x' or entity[1] == 'X')) {
            const hex_str = entity[2..];
            if (std.fmt.parseInt(u21, hex_str, 16)) |code_point| {
                if (code_point <= 0xFF) {
                    return @as(u8, @intCast(code_point));
                }
            } else |_| {
                // 解析失败
            }
        }

        return null;
    }

    fn createTextNode(self: *Self, text: []const u8) !*dom.Node {
        // 解码HTML实体
        const decoded_text = try self.decodeHtmlEntities(text);
        defer self.allocator.free(decoded_text);

        const text_owned = try self.allocator.dupe(u8, decoded_text);
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
                    // 设置insertion_mode为after_head
                    self.insertion_mode = .after_head;
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
        self.open_elements.deinit(self.allocator);
    }
};
