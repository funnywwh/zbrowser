const std = @import("std");
const cff = @import("cff");

/// TTF/OTF字体解析器
/// 参考：TrueType规范、OpenType规范
pub const TtfParser = struct {
    allocator: std.mem.Allocator,
    /// 字体数据（原始字节）
    font_data: []const u8,
    /// 字体表目录
    table_directory: TableDirectory,

    const Self = @This();

    /// 表记录
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
        /// 每个轮廓的结束点索引（相对于points数组）
        contour_end_points: std.ArrayList(usize),

        pub const Point = struct {
            x: i16,
            y: i16,
            /// 是否为控制点（用于二次贝塞尔曲线）
            is_control: bool,
        };

        pub fn deinit(self: *Glyph, allocator: std.mem.Allocator) void {
            self.points.deinit(allocator);
            self.instructions.deinit(allocator);
            self.contour_end_points.deinit(allocator);
        }
    };

    /// 创建空字形（用于错误情况或空字形）
    fn createEmptyGlyph(allocator: std.mem.Allocator, glyph_index: u16) !Glyph {
        var points = std.ArrayList(Glyph.Point){};
        errdefer points.deinit(allocator);
        var instructions = std.ArrayList(u8){};
        errdefer instructions.deinit(allocator);
        var contour_end_points = std.ArrayList(usize){};
        errdefer contour_end_points.deinit(allocator);
        return Glyph{
            .glyph_index = glyph_index,
            .points = points,
            .instructions = instructions,
            .contour_end_points = contour_end_points,
        };
    }

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
        var table_records = std.ArrayList(TableRecord){};
        errdefer table_records.deinit(allocator);

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

            try table_records.append(allocator, TableRecord{
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
    pub fn findTable(self: *Self, tag: []const u8) ?[]const u8 {
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
        const cmap_table = self.findTable("cmap") orelse return null;

        if (cmap_table.len < 4) {
            return null;
        }

        // cmap表结构：
        // 0-1: version (u16)
        // 2-3: numTables (u16)
        const version = std.mem.readInt(u16, cmap_table[0..2], .big);
        const num_tables = std.mem.readInt(u16, cmap_table[2..4], .big);

        if (version != 0) {
            return null;
        }

        // 查找Unicode编码表（platformID=3, encodingID=1或10）
        var offset: usize = 4;
        var best_subtable_offset: ?usize = null;
        var best_format: ?u16 = null;

        var i: u16 = 0;
        while (i < num_tables) : (i += 1) {
            if (offset + 8 > cmap_table.len) {
                break;
            }

            const platform_id = std.mem.readInt(u16, cmap_table[offset..][0..2], .big);
            offset += 2;
            const encoding_id = std.mem.readInt(u16, cmap_table[offset..][0..2], .big);
            offset += 2;
            const subtable_offset = std.mem.readInt(u32, cmap_table[offset..][0..4], .big);
            offset += 4;

            // 优先选择Unicode编码表（platformID=3）
            // encodingID=1: Unicode BMP
            // encodingID=10: Unicode full repertoire
            if (platform_id == 3 and (encoding_id == 1 or encoding_id == 10)) {
                const subtable_start = @as(usize, subtable_offset);
                if (subtable_start >= cmap_table.len) {
                    continue;
                }

                const format = std.mem.readInt(u16, cmap_table[subtable_start..][0..2], .big);

                // 优先选择格式12（支持完整Unicode），其次格式4（BMP）
                if (format == 12) {
                    best_subtable_offset = subtable_start;
                    best_format = format;
                    break; // 格式12是最好的，直接使用
                } else if (format == 4 and best_format != 12) {
                    best_subtable_offset = subtable_start;
                    best_format = format;
                }
            }
        }

        const subtable_start = best_subtable_offset orelse return null;
        const format = best_format orelse return null;

        // 解析格式4（最常用的BMP格式）
        if (format == 4) {
            return self.parseCmapFormat4(cmap_table[subtable_start..], codepoint);
        }

        // 解析格式12（完整Unicode支持）
        if (format == 12) {
            return self.parseCmapFormat12(cmap_table[subtable_start..], codepoint);
        }

        return null;
    }

    /// 解析cmap格式4（BMP格式）
    fn parseCmapFormat4(self: *Self, subtable: []const u8, codepoint: u21) !?u16 {
        _ = self;

        if (subtable.len < 14) {
            return null;
        }

        // 格式4结构：
        // 0-1: format (u16) = 4
        // 2-3: length (u16)
        // 4-5: language (u16)
        // 6-7: segCountX2 (u16) - 段数量的2倍
        // 8-9: searchRange (u16)
        // 10-11: entrySelector (u16)
        // 12-13: rangeShift (u16)
        // 之后是endCode、startCode、idDelta、idRangeOffset数组

        const seg_count_x2 = std.mem.readInt(u16, subtable[6..8], .big);
        const seg_count = seg_count_x2 / 2;

        if (seg_count == 0) {
            return null;
        }

        // 计算数组偏移
        const array_start = 14;
        const end_code_offset = array_start;
        const start_code_offset = end_code_offset + seg_count_x2 + 2; // +2 for reservedPad
        const id_delta_offset = start_code_offset + seg_count_x2;
        const id_range_offset_offset = id_delta_offset + seg_count_x2;

        // 查找包含codepoint的段
        var i: u16 = 0;
        while (i < seg_count) : (i += 1) {
            const end_code = std.mem.readInt(u16, subtable[end_code_offset + @as(usize, i) * 2 ..][0..2], .big);
            const start_code = std.mem.readInt(u16, subtable[start_code_offset + @as(usize, i) * 2 ..][0..2], .big);

            if (codepoint >= start_code and codepoint <= end_code) {
                // 找到匹配的段
                const id_delta = std.mem.readInt(i16, subtable[id_delta_offset + @as(usize, i) * 2 ..][0..2], .big);
                const id_range_offset = std.mem.readInt(u16, subtable[id_range_offset_offset + @as(usize, i) * 2 ..][0..2], .big);

                if (id_range_offset == 0) {
                    // 直接计算：glyphID = (codepoint + idDelta) & 0xFFFF
                    const glyph_id = @as(u16, @intCast((@as(i32, codepoint) + id_delta) & 0xFFFF));
                    return glyph_id;
                } else {
                    // 从idRangeOffset指向的位置读取
                    const glyph_index_offset = id_range_offset_offset + @as(usize, i) * 2 + id_range_offset + (codepoint - start_code) * 2;
                    if (glyph_index_offset + 2 > subtable.len) {
                        return null;
                    }
                    const glyph_id = std.mem.readInt(u16, subtable[glyph_index_offset..][0..2], .big);
                    if (glyph_id != 0) {
                        const final_glyph_id = @as(u16, @intCast((@as(i32, glyph_id) + id_delta) & 0xFFFF));
                        return final_glyph_id;
                    }
                    return null;
                }
            }
        }

        return null;
    }

    /// 解析cmap格式12（完整Unicode支持）
    fn parseCmapFormat12(self: *Self, subtable: []const u8, codepoint: u21) !?u16 {
        _ = self;

        if (subtable.len < 16) {
            return null;
        }

        // 格式12结构：
        // 0-1: format (u16) = 12
        // 2-3: reserved (u16)
        // 4-7: length (u32)
        // 8-11: language (u32)
        // 12-15: nGroups (u32)
        // 之后是groups数组，每个group 12字节：
        // - startCharCode (u32)
        // - endCharCode (u32)
        // - glyphID (u32)

        const n_groups = std.mem.readInt(u32, subtable[12..16], .big);

        var offset: usize = 16;
        var i: u32 = 0;
        while (i < n_groups) : (i += 1) {
            if (offset + 12 > subtable.len) {
                break;
            }

            const start_char_code = std.mem.readInt(u32, subtable[offset..][0..4], .big);
            offset += 4;
            const end_char_code = std.mem.readInt(u32, subtable[offset..][0..4], .big);
            offset += 4;
            const start_glyph_id = std.mem.readInt(u32, subtable[offset..][0..4], .big);
            offset += 4;

            if (codepoint >= start_char_code and codepoint <= end_char_code) {
                const glyph_id = @as(u16, @intCast(start_glyph_id + (codepoint - start_char_code)));
                return glyph_id;
            }
        }

        return null;
    }

    /// 获取字形数据
    /// 参数：
    /// - glyph_index: 字形索引
    /// 返回：字形数据
    pub fn getGlyph(self: *Self, glyph_index: u16) !Glyph {
        std.log.warn("[TTF] getGlyph: called for glyph_index={d}", .{glyph_index});

        // 先检查CFF表（OTF字体使用CFF表，不需要loca表）
        const cff_table = self.findTable("CFF ");
        if (cff_table) |cff_data| {
            std.log.warn("[TTF] getGlyph: found CFF table, parsing glyph_index={d}", .{glyph_index});
            // 使用CFF解析器解析PostScript轮廓
            const result = try self.parseCffGlyph(cff_data, glyph_index);
            std.log.warn("[TTF] getGlyph: parseCffGlyph result: points.len={d}", .{result.points.items.len});
            return result;
        }

        // 对于TrueType字体（使用glyf表），需要loca表
        // 解析loca表获取字形偏移量
        const loca_table = self.findTable("loca") orelse {
            std.log.warn("[TTF] getGlyph: no loca table found, returning empty glyph", .{});
            return try Self.createEmptyGlyph(self.allocator, glyph_index);
        };

        // 获取head表以确定loca格式
        const head_table = self.findTable("head") orelse {
            std.log.warn("[TTF] getGlyph: no head table found, returning empty glyph", .{});
            return try Self.createEmptyGlyph(self.allocator, glyph_index);
        };

        if (head_table.len < 52) {
            return try Self.createEmptyGlyph(self.allocator, glyph_index);
        }

        // head表：50-51: indexToLocFormat (i16)
        // 0 = 短格式（u16），1 = 长格式（u32）
        const index_to_loc_format = std.mem.readInt(i16, head_table[50..52], .big);
        const is_long_format = (index_to_loc_format == 1);

        // 获取字形偏移量
        const glyph_offset = if (is_long_format) blk: {
            // 长格式：每个条目4字节
            const offset = @as(usize, glyph_index) * 4;
            if (offset + 4 > loca_table.len) {
                break :blk null;
            }
            break :blk std.mem.readInt(u32, loca_table[offset..][0..4], .big);
        } else blk: {
            // 短格式：每个条目2字节，需要乘以2得到实际偏移
            const offset = @as(usize, glyph_index) * 2;
            if (offset + 2 > loca_table.len) {
                break :blk null;
            }
            const short_offset = std.mem.readInt(u16, loca_table[offset..][0..2], .big);
            break :blk @as(u32, short_offset) * 2;
        };

        const glyph_offset_value = glyph_offset orelse {
            return try Self.createEmptyGlyph(self.allocator, glyph_index);
        };

        // 检查字体轮廓格式
        // OpenType字体可能使用：
        // 1. glyf表（TrueType轮廓，二次贝塞尔曲线）- 已支持
        // 2. CFF表（PostScript轮廓，三次贝塞尔曲线）- 待实现
        // 3. CFF2表（PostScript轮廓v2）- 待实现

        // 使用glyf表（TrueType轮廓）
        const glyf_table = self.findTable("glyf");
        if (glyf_table) |glyf| {
            std.log.warn("[TTF] getGlyph: found glyf table, parsing glyph_index={d}, glyph_offset={d}", .{ glyph_index, glyph_offset_value });
            // 使用TrueType轮廓解析
            const result = try self.parseGlyfGlyph(glyf, glyph_index, glyph_offset_value);
            std.log.warn("[TTF] getGlyph: parseGlyfGlyph result: points.len={d}", .{result.points.items.len});
            return result;
        }

        // 如果都找不到，返回空字形
        std.log.warn("[TTF] getGlyph: no glyf or CFF table found, returning empty glyph for glyph_index={d}", .{glyph_index});
        return try Self.createEmptyGlyph(self.allocator, glyph_index);
    }

    /// 解析glyf表中的字形（TrueType轮廓）
    fn parseGlyfGlyph(self: *Self, glyf_table: []const u8, glyph_index: u16, glyph_offset: u32) !Glyph {
        if (glyph_offset >= glyf_table.len) {
            std.log.warn("[TTF] parseGlyfGlyph: glyph_offset ({d}) >= glyf_table.len ({d}), returning empty glyph", .{ glyph_offset, glyf_table.len });
            return try Self.createEmptyGlyph(self.allocator, glyph_index);
        }
        std.log.warn("[TTF] parseGlyfGlyph: calling parseGlyphOutline with glyph_offset={d}, glyf_table.len={d}", .{ glyph_offset, glyf_table.len });
        const result = try self.parseGlyphOutline(glyf_table[@intCast(glyph_offset)..], glyph_index);
        std.log.warn("[TTF] parseGlyfGlyph: parseGlyphOutline result: points.len={d}", .{result.points.items.len});
        return result;
    }

    /// 解析CFF表中的字形（PostScript轮廓）
    fn parseCffGlyph(self: *Self, cff_data: []const u8, glyph_index: u16) !Glyph {
        std.log.warn("[TTF] parseCffGlyph: parsing glyph_index={d}, cff_data.len={d}", .{ glyph_index, cff_data.len });
        var cff_parser = try cff.CffParser.init(self.allocator, cff_data);
        defer cff_parser.deinit();

        // 获取CharString数据
        const charstring_data = cff_parser.getCharString(glyph_index) catch |err| {
            std.log.warn("[TTF] parseCffGlyph: getCharString failed for glyph_index={d}, error={}", .{ glyph_index, err });
            return try Self.createEmptyGlyph(self.allocator, glyph_index);
        };
        std.log.warn("[TTF] parseCffGlyph: got charstring_data, len={d}", .{charstring_data.len});

        // 解码CharString
        var decoder = cff.CharStringDecoder.init(self.allocator, charstring_data);
        defer decoder.deinit();

        decoder.decode() catch |err| {
            std.log.warn("[TTF] parseCffGlyph: decode failed for glyph_index={d}, error={}", .{ glyph_index, err });
            return try Self.createEmptyGlyph(self.allocator, glyph_index);
        };
        std.log.warn("[TTF] parseCffGlyph: decode succeeded, decoder.points.items.len={d}", .{decoder.points.items.len});

        // 转换PostScript点（f32）到TrueType点（i16）
        // 注意：需要获取units_per_em来正确缩放
        _ = self.findTable("head"); // 检查head表，但当前简化实现不使用units_per_em
        return self.convertCffPointsToGlyph(&decoder, glyph_index);
    }

    /// 将CFF点转换为Glyph格式
    fn convertCffPointsToGlyph(self: *Self, decoder: *cff.CharStringDecoder, glyph_index: u16) !Glyph {
        var points = std.ArrayList(Glyph.Point){};
        errdefer points.deinit(self.allocator);
        var instructions = std.ArrayList(u8){};
        errdefer instructions.deinit(self.allocator);
        var contour_end_points = std.ArrayList(usize){};
        errdefer contour_end_points.deinit(self.allocator);

        // 转换CFF点（f32，三次贝塞尔）到Glyph点（i16，二次贝塞尔）
        // TODO: 简化实现 - 当前将三次贝塞尔曲线近似为二次贝塞尔曲线
        // 完整实现需要：
        // 1. 支持三次贝塞尔曲线的直接渲染
        // 2. 或者将三次贝塞尔曲线转换为多个二次贝塞尔曲线（De Casteljau算法）
        // 参考：贝塞尔曲线转换算法

        var i: usize = 0;
        while (i < decoder.points.items.len) : (i += 1) {
            const cff_point = decoder.points.items[i];

            // 转换坐标（f32 -> i16）
            // 注意：CFF使用字体单位坐标，需要根据units_per_em缩放
            const x = @as(i16, @intFromFloat(cff_point.x));
            const y = @as(i16, @intFromFloat(cff_point.y));

            // 判断点类型
            const is_control = switch (cff_point.point_type) {
                1 => true, // 二次控制点
                2, 3 => true, // 三次控制点（暂时标记为控制点）
                else => false, // 普通点
            };

            try points.append(self.allocator, Glyph.Point{
                .x = x,
                .y = y,
                .is_control = is_control,
            });
        }

        // 转换轮廓结束点索引
        for (decoder.contour_end_indices.items) |end_index| {
            // 确保索引在有效范围内
            if (end_index < points.items.len) {
                try contour_end_points.append(self.allocator, end_index);
            }
        }

        return Glyph{
            .glyph_index = glyph_index,
            .points = points,
            .instructions = instructions,
            .contour_end_points = contour_end_points,
        };
    }

    /// 解析字形轮廓数据（TrueType格式）
    fn parseGlyphOutline(self: *Self, glyph_data: []const u8, glyph_index: u16) !Glyph {
        if (glyph_data.len < 10) {
            return try Self.createEmptyGlyph(self.allocator, glyph_index);
        }

        // glyf表字形结构：
        // 0-1: numberOfContours (i16) - 负数表示复合字形
        // 2-3: xMin (i16)
        // 4-5: yMin (i16)
        // 6-7: xMax (i16)
        // 8-9: yMax (i16)

        const number_of_contours = std.mem.readInt(i16, glyph_data[0..2], .big);

        if (number_of_contours < 0) {
            // TODO: 简化实现 - 复合字形暂不支持
            // 完整实现需要递归解析复合字形的组件
            // 参考：TrueType规范复合字形章节
            return try Self.createEmptyGlyph(self.allocator, glyph_index);
        }

        if (number_of_contours == 0) {
            // 空字形
            return try Self.createEmptyGlyph(self.allocator, glyph_index);
        }

        // 解析简单字形轮廓
        // 完整实现：
        // 1. 解析endPtsOfContours数组
        // 2. 解析flags、xCoordinates、yCoordinates数组
        // 3. 解析TrueType指令
        // 4. 转换为点列表（包括控制点）
        // 参考：TrueType规范简单字形轮廓章节

        var points = std.ArrayList(Glyph.Point){};
        errdefer points.deinit(self.allocator);

        var instructions = std.ArrayList(u8){};
        errdefer instructions.deinit(self.allocator);

        var offset: usize = 10;

        // 读取endPtsOfContours数组
        const num_contours = @as(u16, @intCast(number_of_contours));
        if (offset + @as(usize, num_contours) * 2 > glyph_data.len) {
            var contour_end_points = std.ArrayList(usize){};
            errdefer contour_end_points.deinit(self.allocator);
            return Glyph{
                .glyph_index = glyph_index,
                .points = points,
                .instructions = instructions,
                .contour_end_points = contour_end_points,
            };
        }

        // 计算总点数（最后一个endPtsOfContours + 1）
        const last_end_point = std.mem.readInt(u16, glyph_data[offset + @as(usize, num_contours - 1) * 2 ..][0..2], .big);
        const total_points = @as(usize, last_end_point) + 1;
        offset += @as(usize, num_contours) * 2;

        // 读取instructionLength
        if (offset + 2 > glyph_data.len) {
            var contour_end_points = std.ArrayList(usize){};
            errdefer contour_end_points.deinit(self.allocator);
            return Glyph{
                .glyph_index = glyph_index,
                .points = points,
                .instructions = instructions,
                .contour_end_points = contour_end_points,
            };
        }

        const instruction_length = std.mem.readInt(u16, glyph_data[offset..][0..2], .big);
        offset += 2;

        // 读取instructions
        if (offset + @as(usize, instruction_length) > glyph_data.len) {
            var contour_end_points = std.ArrayList(usize){};
            errdefer contour_end_points.deinit(self.allocator);
            return Glyph{
                .glyph_index = glyph_index,
                .points = points,
                .instructions = instructions,
                .contour_end_points = contour_end_points,
            };
        }

        if (instruction_length > 0) {
            try instructions.appendSlice(self.allocator, glyph_data[offset..][0..instruction_length]);
        }
        offset += @as(usize, instruction_length);

        // 读取flags数组
        var flags = std.ArrayList(u8){};
        defer flags.deinit(self.allocator);

        var i: usize = 0;
        while (i < total_points) {
            if (offset >= glyph_data.len) {
                break;
            }

            const flag = glyph_data[offset];
            offset += 1;
            try flags.append(self.allocator, flag);
            i += 1;

            // 如果REPEAT标志位设置，下一个字节是重复次数
            if ((flag & 0x08) != 0) {
                if (offset >= glyph_data.len) {
                    break;
                }
                const repeat_count = glyph_data[offset];
                offset += 1;

                var j: u8 = 0;
                while (j < repeat_count and i < total_points) : (j += 1) {
                    try flags.append(self.allocator, flag);
                    i += 1;
                }
            }
        }

        // 读取xCoordinates数组
        var x_coords = std.ArrayList(i16){};
        defer x_coords.deinit(self.allocator);

        i = 0;
        var current_x: i16 = 0;
        while (i < total_points) : (i += 1) {
            if (i >= flags.items.len) {
                break;
            }

            const flag = flags.items[i];
            var x_delta: i16 = 0;

            if ((flag & 0x02) != 0) {
                // 短值：1字节
                if (offset >= glyph_data.len) {
                    break;
                }
                const short_val = glyph_data[offset];
                offset += 1;
                x_delta = if ((flag & 0x10) != 0) @as(i16, short_val) else -@as(i16, short_val);
            } else if ((flag & 0x10) == 0) {
                // 长值：2字节
                if (offset + 2 > glyph_data.len) {
                    break;
                }
                x_delta = std.mem.readInt(i16, glyph_data[offset..][0..2], .big);
                offset += 2;
            }
            // 如果flag & 0x10 != 0 且 flag & 0x02 == 0，则x_delta = 0

            current_x += x_delta;
            try x_coords.append(self.allocator, current_x);
        }

        // 读取yCoordinates数组
        var y_coords = std.ArrayList(i16){};
        defer y_coords.deinit(self.allocator);

        i = 0;
        var current_y: i16 = 0;
        while (i < total_points) : (i += 1) {
            if (i >= flags.items.len) {
                break;
            }

            const flag = flags.items[i];
            var y_delta: i16 = 0;

            if ((flag & 0x04) != 0) {
                // 短值：1字节
                if (offset >= glyph_data.len) {
                    break;
                }
                const short_val = glyph_data[offset];
                offset += 1;
                y_delta = if ((flag & 0x20) != 0) @as(i16, short_val) else -@as(i16, short_val);
            } else if ((flag & 0x20) == 0) {
                // 长值：2字节
                if (offset + 2 > glyph_data.len) {
                    break;
                }
                y_delta = std.mem.readInt(i16, glyph_data[offset..][0..2], .big);
                offset += 2;
            }
            // 如果flag & 0x20 != 0 且 flag & 0x04 == 0，则y_delta = 0

            current_y += y_delta;
            try y_coords.append(self.allocator, current_y);
        }

        // 构建点列表
        // 确定每个轮廓的结束点
        var contour_end_points = std.ArrayList(usize){};
        errdefer contour_end_points.deinit(self.allocator);

        var temp_offset: usize = 10;
        var contour_idx: u16 = 0;
        while (contour_idx < num_contours) : (contour_idx += 1) {
            if (temp_offset + 2 > glyph_data.len) {
                break;
            }
            const end_point = std.mem.readInt(u16, glyph_data[temp_offset..][0..2], .big);
            temp_offset += 2;
            try contour_end_points.append(self.allocator, @as(usize, end_point));
        }

        // 创建点列表，标记控制点
        const actual_point_count = @min(x_coords.items.len, @min(y_coords.items.len, flags.items.len));
        try points.ensureTotalCapacity(self.allocator, actual_point_count);

        i = 0;
        contour_idx = 0;
        while (i < actual_point_count) : (i += 1) {
            const flag = if (i < flags.items.len) flags.items[i] else 0;
            const is_on_curve = (flag & 0x01) != 0; // ON_CURVE标志位：1=在曲线上，0=控制点

            // 确定是否是控制点（不在曲线上的点是控制点）
            const is_control_point = !is_on_curve;

            try points.append(self.allocator, Glyph.Point{
                .x = if (i < x_coords.items.len) x_coords.items[i] else 0,
                .y = if (i < y_coords.items.len) y_coords.items[i] else 0,
                .is_control = is_control_point,
            });
        }

        return Glyph{
            .glyph_index = glyph_index,
            .points = points,
            .instructions = instructions,
            .contour_end_points = contour_end_points,
        };
    }

    /// 获取字形的水平度量
    /// 参数：
    /// - glyph_index: 字形索引
    /// 返回：水平度量
    pub fn getHorizontalMetrics(self: *Self, glyph_index: u16) !HorizontalMetrics {
        // 解析hmtx表（水平度量表）
        const hmtx_table = self.findTable("hmtx") orelse {
            // 如果没有hmtx表，返回默认值
            return HorizontalMetrics{
                .advance_width = 500,
                .left_side_bearing = 0,
            };
        };

        // 获取hhea表以确定字形数量
        const hhea_table = self.findTable("hhea") orelse {
            return HorizontalMetrics{
                .advance_width = 500,
                .left_side_bearing = 0,
            };
        };

        if (hhea_table.len < 34) {
            return HorizontalMetrics{
                .advance_width = 500,
                .left_side_bearing = 0,
            };
        }

        // hhea表结构：
        // 34-35: numberOfHMetrics (u16)
        const number_of_h_metrics = std.mem.readInt(u16, hhea_table[34..36], .big);

        if (hmtx_table.len < 4) {
            return HorizontalMetrics{
                .advance_width = 500,
                .left_side_bearing = 0,
            };
        }

        // hmtx表结构：
        // 每个度量记录4字节：
        // - advanceWidth (u16)
        // - leftSideBearing (i16)
        //
        // 如果字形索引 >= numberOfHMetrics，使用最后一个度量记录的advanceWidth
        // 并从hmtx表的第二部分读取leftSideBearing（每个2字节）

        if (glyph_index < number_of_h_metrics) {
            // 在长格式部分
            const offset = @as(usize, glyph_index) * 4;
            if (offset + 4 > hmtx_table.len) {
                return HorizontalMetrics{
                    .advance_width = 500,
                    .left_side_bearing = 0,
                };
            }

            const advance_width = std.mem.readInt(u16, hmtx_table[offset..][0..2], .big);
            const left_side_bearing = std.mem.readInt(i16, hmtx_table[offset + 2 ..][0..2], .big);

            return HorizontalMetrics{
                .advance_width = advance_width,
                .left_side_bearing = left_side_bearing,
            };
        } else {
            // 在短格式部分
            // 使用最后一个度量记录的advanceWidth
            const last_metric_offset = @as(usize, number_of_h_metrics - 1) * 4;
            if (last_metric_offset + 2 > hmtx_table.len) {
                return HorizontalMetrics{
                    .advance_width = 500,
                    .left_side_bearing = 0,
                };
            }

            const advance_width = std.mem.readInt(u16, hmtx_table[last_metric_offset..][0..2], .big);

            // 从短格式部分读取leftSideBearing
            const short_format_offset = @as(usize, number_of_h_metrics) * 4;
            const bearing_index = glyph_index - number_of_h_metrics;
            const bearing_offset = short_format_offset + @as(usize, bearing_index) * 2;

            if (bearing_offset + 2 > hmtx_table.len) {
                return HorizontalMetrics{
                    .advance_width = advance_width,
                    .left_side_bearing = 0,
                };
            }

            const left_side_bearing = std.mem.readInt(i16, hmtx_table[bearing_offset..][0..2], .big);

            return HorizontalMetrics{
                .advance_width = advance_width,
                .left_side_bearing = left_side_bearing,
            };
        }
    }

    /// 获取fpgm表（Font Program）
    /// 返回：fpgm表数据（如果存在）
    pub fn getFpgm(self: *Self) ?[]const u8 {
        return self.findTable("fpgm");
    }

    /// 获取prep表（Control Value Program）
    /// 返回：prep表数据（如果存在）
    pub fn getPrep(self: *Self) ?[]const u8 {
        return self.findTable("prep");
    }

    /// 获取cvt表（Control Value Table）
    /// 返回：cvt表数据（如果存在）
    pub fn getCvt(self: *Self) ?[]const u8 {
        return self.findTable("cvt ");
    }

    /// 获取字体度量信息
    pub fn getFontMetrics(self: *Self) !FontMetrics {
        // 解析head表获取units_per_em
        const head_table = self.findTable("head") orelse {
            // 如果没有head表，返回默认值
            return FontMetrics{
                .units_per_em = 1000,
                .ascent = 800,
                .descent = -200,
                .line_gap = 0,
            };
        };

        if (head_table.len < 54) {
            return error.InvalidFormat;
        }

        // head表结构（54字节）：
        // 0-3: version (u32)
        // 4-7: fontRevision (u32)
        // 8-11: checkSumAdjustment (u32)
        // 12-15: magicNumber (u32)
        // 16-17: flags (u16)
        // 18-19: unitsPerEm (u16) - 这是我们需要的关键字段
        // 20-27: created (8 bytes)
        // 28-35: modified (8 bytes)
        // 36-37: xMin (i16)
        // 38-39: yMin (i16)
        // 40-41: xMax (i16)
        // 42-43: yMax (i16)
        // 44-45: macStyle (u16)
        // 46-47: lowestRecPPEM (u16)
        // 48-49: fontDirectionHint (i16)
        // 50-51: indexToLocFormat (i16)
        // 52-53: glyphDataFormat (i16)

        const units_per_em = std.mem.readInt(u16, head_table[18..20], .big);

        // 解析hhea表获取ascent、descent、lineGap
        const hhea_table = self.findTable("hhea");
        if (hhea_table) |hhea| {
            if (hhea.len >= 36) {
                // hhea表结构：
                // 0-3: version (u32)
                // 4-5: ascent (i16)
                // 6-7: descent (i16)
                // 8-9: lineGap (i16)
                // ... 其他字段

                const ascent = std.mem.readInt(i16, hhea[4..6], .big);
                const descent = std.mem.readInt(i16, hhea[6..8], .big);
                const line_gap = std.mem.readInt(i16, hhea[8..10], .big);

                return FontMetrics{
                    .units_per_em = units_per_em,
                    .ascent = ascent,
                    .descent = descent,
                    .line_gap = line_gap,
                };
            }
        }

        // 如果没有hhea表，使用默认值
        return FontMetrics{
            .units_per_em = units_per_em,
            .ascent = 800,
            .descent = -200,
            .line_gap = 0,
        };
    }
};
