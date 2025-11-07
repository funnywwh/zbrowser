const std = @import("std");

/// 字符串工具函数
/// 检查字符串是否以指定前缀开始
pub fn startsWith(haystack: []const u8, needle: []const u8) bool {
    return std.mem.startsWith(u8, haystack, needle);
}

/// 检查字符串是否以指定后缀结束
pub fn endsWith(haystack: []const u8, needle: []const u8) bool {
    return std.mem.endsWith(u8, haystack, needle);
}

/// 去除字符串两端的空白字符
pub fn trim(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, &std.ascii.whitespace);
}

/// 将字符串转换为小写（原地修改）
pub fn toLowerInPlace(str: []u8) void {
    for (str) |*c| {
        c.* = std.ascii.toLower(c.*);
    }
}

/// 检查字符是否为空白字符
pub fn isWhitespace(c: u8) bool {
    return std.ascii.isWhitespace(c);
}

/// 检查字符是否为字母
pub fn isAlpha(c: u8) bool {
    return std.ascii.isAlphabetic(c);
}

/// 检查字符是否为数字
pub fn isDigit(c: u8) bool {
    return std.ascii.isDigit(c);
}

/// 检查字符是否为字母或数字
pub fn isAlnum(c: u8) bool {
    return std.ascii.isAlphanumeric(c);
}

/// HTML实体解码
pub fn decodeHtmlEntity(allocator: std.mem.Allocator, entity: []const u8) ![]const u8 {
    if (entity.len < 3 or entity[0] != '&') {
        return try allocator.dupe(u8, entity);
    }

    // 处理命名实体
    const named_entities = std.ComptimeStringMap([]const u8, .{
        .{ "&lt;", "<" },
        .{ "&gt;", ">" },
        .{ "&amp;", "&" },
        .{ "&quot;", "\"" },
        .{ "&apos;", "'" },
        .{ "&nbsp;", " " },
    });

    if (named_entities.get(entity)) |decoded| {
        return try allocator.dupe(u8, decoded);
    }

    // 处理数字实体 &#123; 或 &#x1F;
    if (entity.len > 3 and entity[1] == '#') {
        const is_hex = entity[2] == 'x' or entity[2] == 'X';
        const start_idx: usize = if (is_hex) 3 else 2;
        const end_idx = std.mem.indexOfScalar(u8, entity[start_idx..], ';') orelse entity.len;

        if (end_idx < entity.len) {
            const num_str = entity[start_idx..end_idx];
            const num = if (is_hex) try std.fmt.parseInt(u21, num_str, 16) else try std.fmt.parseInt(u21, num_str, 10);

            // 转换为UTF-8
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(num, &buf) catch return try allocator.dupe(u8, entity);
            return try allocator.dupe(u8, buf[0..len]);
        }
    }

    return try allocator.dupe(u8, entity);
}
