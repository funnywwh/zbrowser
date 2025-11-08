const std = @import("std");

/// TTF/OTF字体解析器
/// 参考：TrueType规范、OpenType规范
pub const TtfParser = struct {
    allocator: std.mem.Allocator,
    /// 字体数据（原始字节）
    font_data: []const u8,
    /// 字体表目录
    table_directory: TableDirectory,

    const Self = @This();

    /// 字体表目录
    const TableDirectory = struct {
        /// SFNT版本（0x00010000 for TrueType, 0x4F54544F for OpenType）
        sfnt_version: u32,
        /// 表数量
        num_tables: u16,
        /// 搜索范围
        search_range: u16,
        /// 入口选择器
        entry_selector: u16,
        /// 范围移位
        range_shift: u16,
        /// 表记录列表
        table_records: std.ArrayList(TableRecord),

        const TableRecord = struct {
            /// 表标签（4字节ASCII字符串）
            tag: [4]u8,
            /// 校验和
            checksum: u32,
            /// 偏移量
            offset: u32,
            /// 长度
            length: u32,
        };
    };

    /// 字体度量信息
    pub const FontMetrics = struct {
        /// 单位/EM（字体设计单位）
        units_per_em: u16,
        /// 上升高度（ascent）
        ascent: i16,
        /// 下降高度（descent）
        descent: i16,
        /// 行间距（line gap）
        line_gap: i16,
    };

    /// 水平度量信息
    pub const HorizontalMetrics = struct {
        /// 前进宽度（advance width）
        advance_width: u16,
        /// 左边界（left side bearing）
        left_side_bearing: i16,
    };

    /// 字形数据
    pub const Glyph = struct {
        /// 字形索引
        glyph_index: u16,
        /// 轮廓点列表
        points: std.ArrayList(Point),
        /// 轮廓指令列表
        instructions: std.ArrayList(u8),

        pub const Point = struct {
            x: i16,
            y: i16,
            /// 是否为控制点（用于二次贝塞尔曲线）
            is_control: bool,
        };

        pub fn deinit(self: *Glyph, allocator: std.mem.Allocator) void {
            self.points.deinit();
            self.instructions.deinit();
            _ = allocator;
        }
    };

    /// 初始化TTF解析器
    pub fn init(allocator: std.mem.Allocator, font_data: []const u8) !Self {
        if (font_data.len < 12) {
            return error.InvalidFormat;
        }

        // 读取SFNT头部
        const sfnt_version = std.mem.readInt(u32, font_data[0..4], .big);
        const num_tables = std.mem.readInt(u16, font_data[4..6], .big);
        const search_range = std.mem.readInt(u16, font_data[6..8], .big);
        const entry_selector = std.mem.readInt(u16, font_data[8..10], .big);
        const range_shift = std.mem.readInt(u16, font_data[10..12], .big);

        // 验证SFNT版本（支持TrueType和OpenType）
        if (sfnt_version != 0x00010000 and sfnt_version != 0x4F54544F) {
            return error.InvalidFormat;
        }

        // 读取表记录
        var table_records = std.ArrayList(TableDirectory.TableRecord).init(allocator);
        errdefer table_records.deinit();

        var offset: usize = 12;
        var i: u16 = 0;
        while (i < num_tables) : (i += 1) {
            if (offset + 16 > font_data.len) {
                return error.InvalidFormat;
            }

            var tag: [4]u8 = undefined;
            @memcpy(&tag, font_data[offset..][0..4]);
            offset += 4;

            const checksum = std.mem.readInt(u32, font_data[offset..][0..4], .big);
            offset += 4;
            const table_offset = std.mem.readInt(u32, font_data[offset..][0..4], .big);
            offset += 4;
            const length = std.mem.readInt(u32, font_data[offset..][0..4], .big);
            offset += 4;

            try table_records.append(.{
                .tag = tag,
                .checksum = checksum,
                .offset = table_offset,
                .length = length,
            });
        }

        return Self{
            .allocator = allocator,
            .font_data = font_data,
            .table_directory = .{
                .sfnt_version = sfnt_version,
                .num_tables = num_tables,
                .search_range = search_range,
                .entry_selector = entry_selector,
                .range_shift = range_shift,
                .table_records = table_records,
            },
        };
    }

    /// 清理TTF解析器
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.table_directory.table_records.deinit(self.allocator);
    }

    /// 查找字体表
    /// 参数：
    /// - tag: 表标签（如 "cmap", "head", "hhea"）
    /// 返回：表数据（如果找到）
    fn findTable(self: *Self, tag: []const u8) ?[]const u8 {
        if (tag.len != 4) {
            return null;
        }

        for (self.table_directory.table_records.items) |record| {
            if (std.mem.eql(u8, &record.tag, tag[0..4])) {
                if (record.offset + record.length > self.font_data.len) {
                    return null;
                }
                return self.font_data[record.offset..][0..record.length];
            }
        }

        return null;
    }

    /// 获取字符的字形索引
    /// 参数：
    /// - codepoint: Unicode字符码点
    /// 返回：字形索引（如果找到）
    pub fn getGlyphIndex(self: *Self, codepoint: u21) !?u16 {
        // TODO: 简化实现 - 当前只支持基本的cmap表解析
        // 完整实现需要：
        // 1. 解析cmap表（格式4、格式12等）
        // 2. 支持Unicode到字形索引的映射
        // 3. 处理变体选择器、组合字符等
        // 参考：TrueType规范 cmap表章节

        const cmap_table = self.findTable("cmap") orelse return null;

        // 简化实现：返回null（需要实现cmap解析）
        _ = cmap_table;
        _ = codepoint;
        return null;
    }

    /// 获取字形数据
    /// 参数：
    /// - glyph_index: 字形索引
    /// 返回：字形数据
    pub fn getGlyph(self: *Self, glyph_index: u16) !Glyph {
        // TODO: 简化实现 - 当前只返回空字形
        // 完整实现需要：
        // 1. 解析loca表（获取字形偏移量）
        // 2. 解析glyf表（获取字形轮廓数据）
        // 3. 解析TrueType轮廓指令
        // 4. 转换为点列表和指令列表
        // 参考：TrueType规范 glyf表章节

        var points = std.ArrayList(Glyph.Point).init(self.allocator);
        errdefer points.deinit();

        var instructions = std.ArrayList(u8).init(self.allocator);
        errdefer instructions.deinit();

        return Glyph{
            .glyph_index = glyph_index,
            .points = points,
            .instructions = instructions,
        };
    }

    /// 获取字形的水平度量
    /// 参数：
    /// - glyph_index: 字形索引
    /// 返回：水平度量
    pub fn getHorizontalMetrics(self: *Self, glyph_index: u16) !HorizontalMetrics {
        // TODO: 简化实现 - 当前返回默认值
        // 完整实现需要：
        // 1. 解析hmtx表（水平度量表）
        // 2. 根据字形索引查找对应的度量值
        // 3. 处理长格式和短格式hmtx表
        // 参考：TrueType规范 hmtx表章节

        _ = self;
        _ = glyph_index;

        return HorizontalMetrics{
            .advance_width = 500, // 默认宽度
            .left_side_bearing = 0,
        };
    }

    /// 获取字体度量信息
    pub fn getFontMetrics(self: *Self) !FontMetrics {
        // TODO: 简化实现 - 当前返回默认值
        // 完整实现需要：
        // 1. 解析head表（字体头部）
        // 2. 解析hhea表（水平头部）
        // 3. 提取units_per_em、ascent、descent、line_gap等
        // 参考：TrueType规范 head表、hhea表章节

        _ = self;
        return FontMetrics{
            .units_per_em = 1000, // 默认1000单位/EM
            .ascent = 800,
            .descent = -200,
            .line_gap = 0,
        };
    }
};
