const std = @import("std");
const testing = std.testing;
const ttf = @import("ttf");

// 创建一个最小的有效TTF文件数据用于测试
// 包含SFNT头部、表目录和基本的head表
fn createMinimalTTF(allocator: std.mem.Allocator, units_per_em: u16) ![]u8 {
    // SFNT头部：12字节
    // head表：54字节
    // 表目录：16字节（一个表记录）
    const total_size = 12 + 16 + 54;
    var data = try allocator.alloc(u8, total_size);
    errdefer allocator.free(data);

    var offset: usize = 0;

    // SFNT头部
    std.mem.writeInt(u32, data[offset..][0..4], 0x00010000, .big); // sfnt_version
    offset += 4;
    std.mem.writeInt(u16, data[offset..][0..2], 1, .big); // num_tables
    offset += 2;
    std.mem.writeInt(u16, data[offset..][0..2], 16, .big); // search_range
    offset += 2;
    std.mem.writeInt(u16, data[offset..][0..2], 0, .big); // entry_selector
    offset += 2;
    std.mem.writeInt(u16, data[offset..][0..2], 0, .big); // range_shift
    offset += 2;

    // 表记录（head表）
    @memcpy(data[offset..][0..4], "head"); // tag
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 0, .big); // checksum
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 28, .big); // offset (12 + 16)
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 54, .big); // length
    offset += 4;

    // head表数据
    std.mem.writeInt(u32, data[offset..][0..4], 0x00010000, .big); // version
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 0, .big); // fontRevision
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 0, .big); // checkSumAdjustment
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 0x5F0F3CF5, .big); // magicNumber
    offset += 4;
    std.mem.writeInt(u16, data[offset..][0..2], 0, .big); // flags
    offset += 2;
    std.mem.writeInt(u16, data[offset..][0..2], units_per_em, .big); // unitsPerEm
    offset += 2;
    // 创建时间和修改时间（各8字节）
    @memset(data[offset..][0..16], 0);
    offset += 16;
    // xMin, yMin, xMax, yMax（各2字节）
    std.mem.writeInt(i16, data[offset..][0..2], 0, .big); // xMin
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], 0, .big); // yMin
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], 1000, .big); // xMax
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], 1000, .big); // yMax
    offset += 2;
    std.mem.writeInt(u16, data[offset..][0..2], 0, .big); // macStyle
    offset += 2;
    std.mem.writeInt(u16, data[offset..][0..2], 0, .big); // lowestRecPPEM
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], 0, .big); // fontDirectionHint
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], 0, .big); // indexToLocFormat
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], 0, .big); // glyphDataFormat
    offset += 2;

    return data;
}

// 测试TTF解析器初始化
test "TtfParser init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ttf_data = try createMinimalTTF(allocator, 1000);
    defer allocator.free(ttf_data);

    var parser = try ttf.TtfParser.init(allocator, ttf_data);
    defer parser.deinit(allocator);

    // 测试：解析器应该可以正常初始化和清理
    try testing.expect(parser.table_directory.num_tables == 1);
}

// 测试TTF解析器 - 空数据
test "TtfParser boundary - empty data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const empty_data = &[_]u8{};

    // 测试：空数据应该返回错误
    const result = ttf.TtfParser.init(allocator, empty_data);
    try testing.expectError(error.InvalidFormat, result);
}

// 测试TTF解析器 - 无效格式
test "TtfParser boundary - invalid format" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const invalid_data = "This is not a TTF file";

    // 测试：无效格式应该返回错误
    const result = ttf.TtfParser.init(allocator, invalid_data);
    try testing.expectError(error.InvalidFormat, result);
}

// 测试getFontMetrics - 正常情况
test "TtfParser getFontMetrics - normal case" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ttf_data = try createMinimalTTF(allocator, 2048);
    defer allocator.free(ttf_data);

    var parser = try ttf.TtfParser.init(allocator, ttf_data);
    defer parser.deinit(allocator);

    const metrics = try parser.getFontMetrics();

    // 测试：应该返回正确的units_per_em
    try testing.expect(metrics.units_per_em == 2048);
}

// 测试getFontMetrics - 边界情况：没有head表
test "TtfParser getFontMetrics boundary - no head table" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建一个没有head表的TTF数据
    var data = try allocator.alloc(u8, 12);
    defer allocator.free(data);

    std.mem.writeInt(u32, data[0..4], 0x00010000, .big);
    std.mem.writeInt(u16, data[4..6], 0, .big); // num_tables = 0
    @memset(data[6..], 0);

    var parser = try ttf.TtfParser.init(allocator, data);
    defer parser.deinit(allocator);

    // 测试：没有head表时应该返回默认值或错误
    const metrics = try parser.getFontMetrics();
    // 当前实现返回默认值，这是合理的
    try testing.expect(metrics.units_per_em > 0);
}

// 创建包含head和hhea表的TTF数据
fn createTTFWithHhea(allocator: std.mem.Allocator, units_per_em: u16, ascent: i16, descent: i16, line_gap: i16) ![]u8 {
    // SFNT头部：12字节
    // head表：54字节
    // hhea表：36字节
    // 表目录：32字节（两个表记录）
    const total_size = 12 + 32 + 54 + 36;
    var data = try allocator.alloc(u8, total_size);
    errdefer allocator.free(data);

    var offset: usize = 0;

    // SFNT头部
    std.mem.writeInt(u32, data[offset..][0..4], 0x00010000, .big); // sfnt_version
    offset += 4;
    std.mem.writeInt(u16, data[offset..][0..2], 2, .big); // num_tables
    offset += 2;
    std.mem.writeInt(u16, data[offset..][0..2], 32, .big); // search_range
    offset += 2;
    std.mem.writeInt(u16, data[offset..][0..2], 1, .big); // entry_selector
    offset += 2;
    std.mem.writeInt(u16, data[offset..][0..2], 0, .big); // range_shift
    offset += 2;

    // 表记录1（head表）
    @memcpy(data[offset..][0..4], "head"); // tag
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 0, .big); // checksum
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 44, .big); // offset (12 + 32)
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 54, .big); // length
    offset += 4;

    // 表记录2（hhea表）
    @memcpy(data[offset..][0..4], "hhea"); // tag
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 0, .big); // checksum
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 98, .big); // offset (12 + 32 + 54)
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 36, .big); // length
    offset += 4;

    // head表数据
    std.mem.writeInt(u32, data[offset..][0..4], 0x00010000, .big); // version
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 0, .big); // fontRevision
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 0, .big); // checkSumAdjustment
    offset += 4;
    std.mem.writeInt(u32, data[offset..][0..4], 0x5F0F3CF5, .big); // magicNumber
    offset += 4;
    std.mem.writeInt(u16, data[offset..][0..2], 0, .big); // flags
    offset += 2;
    std.mem.writeInt(u16, data[offset..][0..2], units_per_em, .big); // unitsPerEm
    offset += 2;
    // 创建时间和修改时间（各8字节）
    @memset(data[offset..][0..16], 0);
    offset += 16;
    // xMin, yMin, xMax, yMax（各2字节）
    std.mem.writeInt(i16, data[offset..][0..2], 0, .big); // xMin
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], 0, .big); // yMin
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], 1000, .big); // xMax
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], 1000, .big); // yMax
    offset += 2;
    std.mem.writeInt(u16, data[offset..][0..2], 0, .big); // macStyle
    offset += 2;
    std.mem.writeInt(u16, data[offset..][0..2], 0, .big); // lowestRecPPEM
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], 0, .big); // fontDirectionHint
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], 0, .big); // indexToLocFormat
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], 0, .big); // glyphDataFormat
    offset += 2;

    // hhea表数据
    std.mem.writeInt(u32, data[offset..][0..4], 0x00010000, .big); // version
    offset += 4;
    std.mem.writeInt(i16, data[offset..][0..2], ascent, .big); // ascent
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], descent, .big); // descent
    offset += 2;
    std.mem.writeInt(i16, data[offset..][0..2], line_gap, .big); // lineGap
    offset += 2;
    // 其他字段（advanceWidthMax, minLeftSideBearing, minRightSideBearing, xMaxExtent等）
    @memset(data[offset..][0..26], 0);
    offset += 26;

    return data;
}

// 测试getFontMetrics - 包含hhea表
test "TtfParser getFontMetrics - with hhea table" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ttf_data = try createTTFWithHhea(allocator, 2048, 1900, -500, 100);
    defer allocator.free(ttf_data);

    var parser = try ttf.TtfParser.init(allocator, ttf_data);
    defer parser.deinit(allocator);

    const metrics = try parser.getFontMetrics();

    // 测试：应该返回正确的值
    try testing.expect(metrics.units_per_em == 2048);
    try testing.expect(metrics.ascent == 1900);
    try testing.expect(metrics.descent == -500);
    try testing.expect(metrics.line_gap == 100);
}

// 测试getFontMetrics - 边界情况：head表太短
test "TtfParser getFontMetrics boundary - head table too short" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建一个head表太短的TTF数据
    var data = try allocator.alloc(u8, 12 + 16 + 10); // head表只有10字节
    defer allocator.free(data);

    var offset: usize = 0;
    std.mem.writeInt(u32, data[offset..][0..4], 0x00010000, .big);
    offset += 4;
    std.mem.writeInt(u16, data[offset..][0..2], 1, .big);
    offset += 2;
    @memset(data[offset..], 0);
    offset = 12;

    @memcpy(data[offset..][0..4], "head");
    offset += 4;
    @memset(data[offset..], 0);
    offset = 28;
    @memset(data[offset..], 0);

    var parser = try ttf.TtfParser.init(allocator, data);
    defer parser.deinit(allocator);

    // 测试：应该返回错误或默认值
    const result = parser.getFontMetrics();
    // 当前实现返回错误，这是合理的
    try testing.expectError(error.InvalidFormat, result);
}

// 测试getGlyphIndex - 边界情况：没有cmap表
test "TtfParser getGlyphIndex boundary - no cmap table" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ttf_data = try createMinimalTTF(allocator, 1000);
    defer allocator.free(ttf_data);

    var parser = try ttf.TtfParser.init(allocator, ttf_data);
    defer parser.deinit(allocator);

    // 测试：没有cmap表时应该返回null
    const result = try parser.getGlyphIndex('A');
    try testing.expect(result == null);
}

// 测试getGlyphIndex - 边界情况：空字符
test "TtfParser getGlyphIndex boundary - null character" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ttf_data = try createMinimalTTF(allocator, 1000);
    defer allocator.free(ttf_data);

    var parser = try ttf.TtfParser.init(allocator, ttf_data);
    defer parser.deinit(allocator);

    // 测试：空字符应该返回null或字形索引0
    const result = try parser.getGlyphIndex(0);
    // 当前实现返回null（因为没有cmap表），这是合理的
    try testing.expect(result == null);
}

// 测试getGlyphIndex - 边界情况：Unicode最大值
test "TtfParser getGlyphIndex boundary - max unicode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ttf_data = try createMinimalTTF(allocator, 1000);
    defer allocator.free(ttf_data);

    var parser = try ttf.TtfParser.init(allocator, ttf_data);
    defer parser.deinit(allocator);

    // 测试：Unicode最大值（0x10FFFF）
    const result = try parser.getGlyphIndex(0x10FFFF);
    try testing.expect(result == null);
}

// 测试getHorizontalMetrics - 边界情况：没有hmtx表
test "TtfParser getHorizontalMetrics boundary - no hmtx table" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ttf_data = try createMinimalTTF(allocator, 1000);
    defer allocator.free(ttf_data);

    var parser = try ttf.TtfParser.init(allocator, ttf_data);
    defer parser.deinit(allocator);

    // 测试：没有hmtx表时应该返回默认值
    const metrics = try parser.getHorizontalMetrics(0);
    try testing.expect(metrics.advance_width > 0);
    try testing.expect(metrics.advance_width == 500); // 默认值
}

// 测试getHorizontalMetrics - 边界情况：字形索引0
test "TtfParser getHorizontalMetrics boundary - glyph index 0" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ttf_data = try createMinimalTTF(allocator, 1000);
    defer allocator.free(ttf_data);

    var parser = try ttf.TtfParser.init(allocator, ttf_data);
    defer parser.deinit(allocator);

    // 测试：字形索引0应该返回默认值
    const metrics = try parser.getHorizontalMetrics(0);
    try testing.expect(metrics.advance_width > 0);
}

// 测试getGlyph - 边界情况：没有loca表
test "TtfParser getGlyph boundary - no loca table" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ttf_data = try createMinimalTTF(allocator, 1000);
    defer allocator.free(ttf_data);

    var parser = try ttf.TtfParser.init(allocator, ttf_data);
    defer parser.deinit(allocator);

    // 测试：没有loca表时应该返回空字形
    var glyph = try parser.getGlyph(0);
    defer glyph.deinit(allocator);

    try testing.expect(glyph.glyph_index == 0);
    try testing.expect(glyph.points.items.len == 0);
    try testing.expect(glyph.instructions.items.len == 0);
}

// 测试getGlyph - 边界情况：字形索引0
test "TtfParser getGlyph boundary - glyph index 0" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ttf_data = try createMinimalTTF(allocator, 1000);
    defer allocator.free(ttf_data);

    var parser = try ttf.TtfParser.init(allocator, ttf_data);
    defer parser.deinit(allocator);

    // 测试：字形索引0应该返回空字形
    var glyph = try parser.getGlyph(0);
    defer glyph.deinit(allocator);

    try testing.expect(glyph.glyph_index == 0);
}

// 测试TtfParser deinit - 内存管理
test "TtfParser deinit - memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const ttf_data = try createMinimalTTF(allocator, 1000);

    var parser = try ttf.TtfParser.init(allocator, ttf_data);
    parser.deinit(allocator);

    // 释放ttf_data（在gpa.deinit之前手动释放，以便检查内存泄漏）
    allocator.free(ttf_data);

    // 测试：deinit后不应该有内存泄漏
    // 使用GPA检查内存泄漏
    const leak_count = gpa.deinit();
    try testing.expect(leak_count == .ok);
}

// 测试getFontMetrics - 边界情况：hhea表太短
test "TtfParser getFontMetrics boundary - hhea table too short" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ttf_data = try createTTFWithHhea(allocator, 2048, 1900, -500, 100);
    defer allocator.free(ttf_data);

    // 修改hhea表长度为10（太短）
    std.mem.writeInt(u32, ttf_data[12 + 16 + 4 + 4 + 4..][0..4], 10, .big);

    var parser = try ttf.TtfParser.init(allocator, ttf_data);
    defer parser.deinit(allocator);

    // 测试：hhea表太短时应该使用默认值
    const metrics = try parser.getFontMetrics();
    try testing.expect(metrics.units_per_em == 2048); // 从head表获取
    // ascent、descent、line_gap应该使用默认值
}
