const std = @import("std");
const ttf = @import("ttf");

/// 字体管理器
/// 负责加载、缓存和管理字体
pub const FontManager = struct {
    allocator: std.mem.Allocator,
    /// 字体缓存：字体名称 -> 字体数据
    font_cache: std.StringHashMap(*FontFace),
    /// 字体数据缓存：字体名称 -> 字体数据（需要单独管理生命周期）
    font_data_cache: std.StringHashMap([]u8),

    const Self = @This();

    /// 初始化字体管理器
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .font_cache = std.StringHashMap(*FontFace).init(allocator),
            .font_data_cache = std.StringHashMap([]u8).init(allocator),
        };
    }

    /// 清理字体管理器
    pub fn deinit(self: *Self) void {
        // 先保存所有需要释放的资源
        var entries = std.ArrayList(struct { name: []const u8, face: *FontFace }){};
        defer entries.deinit(self.allocator);
        
        var it = self.font_cache.iterator();
        while (it.next()) |entry| {
            entries.append(self.allocator, .{
                .name = entry.key_ptr.*,
                .face = entry.value_ptr.*,
            }) catch break;
        }
        
        // 释放字体面
        for (entries.items) |entry| {
            entry.face.deinit(self.allocator);
            self.allocator.destroy(entry.face);
        }
        
        // 释放字体数据
        var it2 = self.font_data_cache.iterator();
        while (it2.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        
        // 释放字体名称（需要转换为可变切片）
        for (entries.items) |entry| {
            // 字体名称是通过 dupe 分配的，需要释放
            // 但 entry.name 是 const，我们需要从 font_cache 中获取
            // 实际上，font_cache 的 key 就是字体名称，我们需要释放它
            // 但我们已经保存了指针，可以直接释放
            const name_mutable = @constCast(entry.name);
            self.allocator.free(name_mutable);
        }
        
        self.font_cache.deinit();
        self.font_data_cache.deinit();
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
        var font_face_value = try FontFace.init(self.allocator, font_data);
        errdefer font_face_value.deinit(self.allocator);

        // 分配 FontFace 指针
        const font_face = try self.allocator.create(FontFace);
        errdefer self.allocator.destroy(font_face);
        font_face.* = font_face_value;

        // 缓存字体
        const font_name_dup = try self.allocator.dupe(u8, font_name);
        errdefer self.allocator.free(font_name_dup);

        // 缓存字体数据（需要单独管理生命周期）
        try self.font_data_cache.put(font_name_dup, font_data);

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
        // 注意：font_data 由 FontManager 管理，这里不释放
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
        std.log.warn("[FontFace] getGlyph: calling ttf_parser.getGlyph for glyph_index={d}", .{glyph_index});
        const result = try self.ttf_parser.getGlyph(glyph_index);
        std.log.warn("[FontFace] getGlyph: result points.len={d}", .{result.points.items.len});
        return result;
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
    
    /// 获取fpgm表（Font Program）
    pub fn getFpgm(self: *Self) ?[]const u8 {
        return self.ttf_parser.getFpgm();
    }
    
    /// 获取prep表（Control Value Program）
    pub fn getPrep(self: *Self) ?[]const u8 {
        return self.ttf_parser.getPrep();
    }
    
    /// 获取cvt表（Control Value Table）
    pub fn getCvt(self: *Self) ?[]const u8 {
        return self.ttf_parser.getCvt();
    }
};
