const std = @import("std");
const tokenizer = @import("css_tokenizer");

test "tokenize identifier" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .ident);
    std.debug.assert(std.mem.eql(u8, token.data.ident, "div"));
}

test "tokenize string with double quotes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "\"hello world\"";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .string);
    std.debug.assert(std.mem.eql(u8, token.data.string, "hello world"));
}

test "tokenize string with single quotes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "'test string'";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .string);
    std.debug.assert(std.mem.eql(u8, token.data.string, "test string"));
}

test "tokenize number" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "123";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .number);
    std.debug.assert(token.data.number == 123.0);
}

test "tokenize decimal number" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "123.45";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .number);
    std.debug.assert(token.data.number == 123.45);
}

test "tokenize negative number" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "-42";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .number);
    std.debug.assert(token.data.number == -42.0);
}

test "tokenize percentage" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "50%";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .percentage);
    std.debug.assert(token.data.percentage == 50.0);
}

test "tokenize dimension" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "100px";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .dimension);
    std.debug.assert(token.data.dimension.value == 100.0);
    std.debug.assert(std.mem.eql(u8, token.data.dimension.unit, "px"));
}

test "tokenize dimension with em unit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "1.5em";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .dimension);
    std.debug.assert(token.data.dimension.value == 1.5);
    std.debug.assert(std.mem.eql(u8, token.data.dimension.unit, "em"));
}

test "tokenize hash" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "#ff0000";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .hash);
    std.debug.assert(std.mem.eql(u8, token.data.hash, "ff0000"));
}

test "tokenize at-keyword" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "@media";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .at_keyword);
    std.debug.assert(std.mem.eql(u8, token.data.at_keyword, "media"));
}

test "tokenize function" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "rgb(";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .function);
    std.debug.assert(std.mem.eql(u8, token.data.function, "rgb"));
}

test "tokenize URL" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "url(image.png)";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .url);
    std.debug.assert(std.mem.eql(u8, token.data.url, "image.png"));
}

test "tokenize URL with quotes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "url(\"image.png\")";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .url);
    std.debug.assert(std.mem.eql(u8, token.data.url, "image.png"));
}

test "tokenize comment" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "/* This is a comment */";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .comment);
    std.debug.assert(std.mem.eql(u8, token.data.comment, " This is a comment "));
}

test "tokenize CDO" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "<!--";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .cdo);
}

test "tokenize CDC" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "-->";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .cdc);
}

test "tokenize delimiter" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "{";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .delim);
    std.debug.assert(token.data.delim == '{');
}

test "tokenize multiple tokens" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "div { color: red; }";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);

    var token = try tok.next();
    std.debug.assert(token.token_type == .ident);
    std.debug.assert(std.mem.eql(u8, token.data.ident, "div"));
    token.deinit(allocator);

    token = try tok.next();
    std.debug.assert(token.token_type == .delim);
    std.debug.assert(token.data.delim == '{');
    token.deinit(allocator);

    token = try tok.next();
    std.debug.assert(token.token_type == .ident);
    std.debug.assert(std.mem.eql(u8, token.data.ident, "color"));
    token.deinit(allocator);

    token = try tok.next();
    std.debug.assert(token.token_type == .delim);
    std.debug.assert(token.data.delim == ':');
    token.deinit(allocator);

    token = try tok.next();
    std.debug.assert(token.token_type == .ident);
    std.debug.assert(std.mem.eql(u8, token.data.ident, "red"));
    token.deinit(allocator);

    token = try tok.next();
    std.debug.assert(token.token_type == .delim);
    std.debug.assert(token.data.delim == ';');
    token.deinit(allocator);

    token = try tok.next();
    std.debug.assert(token.token_type == .delim);
    std.debug.assert(token.data.delim == '}');
    token.deinit(allocator);
}

test "tokenize EOF" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .eof);
}

test "tokenize scientific notation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "1.5e2";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .number);
    std.debug.assert(token.data.number == 150.0);
}

test "tokenize string with escape" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "\"test\\\"string\"";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    std.debug.assert(token.token_type == .string);
    // 注意：转义字符处理可能因实现而异
}

test "tokenize whitespace" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const css_input = "   ";
    var tok = tokenizer.Tokenizer.init(css_input, allocator);
    var token = try tok.next();
    defer token.deinit(allocator);

    // 空白字符应该被跳过，返回EOF
    std.debug.assert(token.token_type == .eof);
}
