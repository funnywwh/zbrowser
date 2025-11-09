const std = @import("std");
const ttf = @import("ttf");

/// 字体管理器
/// 负责加载、缓存和管理字体
pub const FontManager = struct {
    allocator: std.mem.Allocator,
    /// 字体缓存：字体名称 -> 字体数据
    font_cache: std.StringHashMap(*FontFace),

    const Self = @This();

    /// 初始化字体管理器
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .font_cache = std.StringHashMap(*FontFace).init(allocator),
        };
    }

    /// 清理字体管理器
    pub fn deinit(self: *Self) void {
        // 释放所有缓存的字体
        var it = self.font_cache.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.font_cache.deinit();
    }

    /// 加载字体文件
    /// 参数：
    /// - font_path: 字体文件路径
    /// - font_name: 字体名称（用于缓存）
    /// 返回：字体面（FontFace）
    pub fn loadFont(self: *Self, font_path: []const u8, font_name: []const u8) !*FontFace {
        // 检查缓存
        if (self.font_cache.get(font_name)) |cached_font| {
            return cached_font;
        }

        // 读取字体文件
        const file = try std.fs.cwd().openFile(font_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const font_data = try self.allocator.alloc(u8, file_size);
        errdefer self.allocator.free(font_data);

        _ = try file.readAll(font_data);

        // 解析字体
        const font_face = try FontFace.init(self.allocator, font_data);
        errdefer font_face.deinit(self.allocator);

        // 缓存字体
        const font_name_dup = try self.allocator.dupe(u8, font_name);
        errdefer self.allocator.free(font_name_dup);

        try self.font_cache.put(font_name_dup, font_face);

        return font_face;
    }

    /// 根据字体名称查找字体
    /// 参数：
    /// - font_name: 字体名称（如 "Arial", "Times New Roman"）
    /// 返回：字体面（如果找到）
    pub fn getFont(self: *Self, font_name: []const u8) ?*FontFace {
        return self.font_cache.get(font_name);
    }
};

/// 字体面（Font Face）
/// 表示一个已加载的字体文件
pub const FontFace = struct {
    allocator: std.mem.Allocator,
    /// 字体数据（原始字节）
    font_data: []const u8,
    /// TTF字体解析器
    ttf_parser: ttf.TtfParser,

    const Self = @This();

    /// 初始化字体面
    pub fn init(allocator: std.mem.Allocator, font_data: []const u8) !Self {
        const ttf_parser = try ttf.TtfParser.init(allocator, font_data);
        errdefer ttf_parser.deinit(allocator);

        return .{
            .allocator = allocator,
            .font_data = font_data,
            .ttf_parser = ttf_parser,
        };
    }

    /// 清理字体面
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.ttf_parser.deinit(self.allocator);
        // 注意：font_data 由调用者管理，这里不释放
    }

    /// 获取字符的字形索引
    /// 参数：
    /// - codepoint: Unicode字符码点
    /// 返回：字形索引（如果找到）
    pub fn getGlyphIndex(self: *Self, codepoint: u21) !?u16 {
        return try self.ttf_parser.getGlyphIndex(codepoint);
    }

    /// 获取字形数据
    /// 参数：
    /// - glyph_index: 字形索引
    /// 返回：字形数据
    pub fn getGlyph(self: *Self, glyph_index: u16) !ttf.TtfParser.Glyph {
        return try self.ttf_parser.getGlyph(glyph_index);
    }

    /// 获取字形的水平度量（宽度、左边界等）
    /// 参数：
    /// - glyph_index: 字形索引
    /// 返回：水平度量
    pub fn getHorizontalMetrics(self: *Self, glyph_index: u16) !ttf.TtfParser.HorizontalMetrics {
        return try self.ttf_parser.getHorizontalMetrics(glyph_index);
    }

    /// 获取字体度量信息
    pub fn getFontMetrics(self: *Self) !ttf.TtfParser.FontMetrics {
        return try self.ttf_parser.getFontMetrics();
    }
};
