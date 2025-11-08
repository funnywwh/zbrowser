const std = @import("std");
const string = @import("string");

test "startsWith" {
    std.debug.assert(string.startsWith("hello world", "hello"));
    std.debug.assert(!string.startsWith("hello world", "world"));
    std.debug.assert(string.startsWith("test", "test"));
    std.debug.assert(string.startsWith("prefix", "pre"));
}

test "endsWith" {
    std.debug.assert(string.endsWith("hello world", "world"));
    std.debug.assert(!string.endsWith("hello world", "hello"));
    std.debug.assert(string.endsWith("test", "test"));
    std.debug.assert(string.endsWith("suffix", "fix"));
}

test "trim" {
    std.debug.assert(std.mem.eql(u8, string.trim("  hello  "), "hello"));
    std.debug.assert(std.mem.eql(u8, string.trim("  test"), "test"));
    std.debug.assert(std.mem.eql(u8, string.trim("test  "), "test"));
    std.debug.assert(std.mem.eql(u8, string.trim("test"), "test"));
    std.debug.assert(std.mem.eql(u8, string.trim("   "), ""));
}

test "toLowerInPlace" {
    var buf = [_]u8{ 'H', 'E', 'L', 'L', 'O' };
    string.toLowerInPlace(&buf);
    std.debug.assert(std.mem.eql(u8, &buf, "hello"));

    var buf2 = [_]u8{ 'T', 'E', 'S', 'T' };
    string.toLowerInPlace(&buf2);
    std.debug.assert(std.mem.eql(u8, &buf2, "test"));
}

test "isWhitespace" {
    std.debug.assert(string.isWhitespace(' '));
    std.debug.assert(string.isWhitespace('\t'));
    std.debug.assert(string.isWhitespace('\n'));
    std.debug.assert(string.isWhitespace('\r'));
    std.debug.assert(!string.isWhitespace('a'));
    std.debug.assert(!string.isWhitespace('1'));
}

test "isAlpha" {
    std.debug.assert(string.isAlpha('a'));
    std.debug.assert(string.isAlpha('Z'));
    std.debug.assert(string.isAlpha('M'));
    std.debug.assert(!string.isAlpha('1'));
    std.debug.assert(!string.isAlpha(' '));
    std.debug.assert(!string.isAlpha('@'));
}

test "isDigit" {
    std.debug.assert(string.isDigit('0'));
    std.debug.assert(string.isDigit('5'));
    std.debug.assert(string.isDigit('9'));
    std.debug.assert(!string.isDigit('a'));
    std.debug.assert(!string.isDigit(' '));
    std.debug.assert(!string.isDigit('@'));
}

test "isAlnum" {
    std.debug.assert(string.isAlnum('a'));
    std.debug.assert(string.isAlnum('Z'));
    std.debug.assert(string.isAlnum('0'));
    std.debug.assert(string.isAlnum('9'));
    std.debug.assert(!string.isAlnum(' '));
    std.debug.assert(!string.isAlnum('@'));
    std.debug.assert(!string.isAlnum('-'));
}

test "decodeHtmlEntity named entities" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const lt = try string.decodeHtmlEntity(allocator, "&lt;");
    defer allocator.free(lt);
    std.debug.assert(std.mem.eql(u8, lt, "<"));

    const gt = try string.decodeHtmlEntity(allocator, "&gt;");
    defer allocator.free(gt);
    std.debug.assert(std.mem.eql(u8, gt, ">"));

    const amp = try string.decodeHtmlEntity(allocator, "&amp;");
    defer allocator.free(amp);
    std.debug.assert(std.mem.eql(u8, amp, "&"));

    const quot = try string.decodeHtmlEntity(allocator, "&quot;");
    defer allocator.free(quot);
    std.debug.assert(std.mem.eql(u8, quot, "\""));

    const apos = try string.decodeHtmlEntity(allocator, "&apos;");
    defer allocator.free(apos);
    std.debug.assert(std.mem.eql(u8, apos, "'"));

    const nbsp = try string.decodeHtmlEntity(allocator, "&nbsp;");
    defer allocator.free(nbsp);
    std.debug.assert(std.mem.eql(u8, nbsp, " "));
}

test "decodeHtmlEntity decimal entity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const entity = try string.decodeHtmlEntity(allocator, "&#65;");
    defer allocator.free(entity);
    std.debug.assert(std.mem.eql(u8, entity, "A"));

    const entity2 = try string.decodeHtmlEntity(allocator, "&#97;");
    defer allocator.free(entity2);
    std.debug.assert(std.mem.eql(u8, entity2, "a"));
}

test "decodeHtmlEntity hex entity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const entity = try string.decodeHtmlEntity(allocator, "&#x41;");
    defer allocator.free(entity);
    std.debug.assert(std.mem.eql(u8, entity, "A"));

    const entity2 = try string.decodeHtmlEntity(allocator, "&#x61;");
    defer allocator.free(entity2);
    std.debug.assert(std.mem.eql(u8, entity2, "a"));
}

test "decodeHtmlEntity invalid entity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const entity = try string.decodeHtmlEntity(allocator, "not an entity");
    defer allocator.free(entity);
    std.debug.assert(std.mem.eql(u8, entity, "not an entity"));
}

test "decodeHtmlEntity short entity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const entity = try string.decodeHtmlEntity(allocator, "&");
    defer allocator.free(entity);
    std.debug.assert(std.mem.eql(u8, entity, "&"));
}
