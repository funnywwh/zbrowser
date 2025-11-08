const std = @import("std");

/// PNG编码器
/// 将RGBA像素数据编码为PNG格式
pub const PngEncoder = struct {
    allocator: std.mem.Allocator,

    /// PNG文件签名（8字节）
    const PNG_SIGNATURE = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };

    /// CRC32查找表（预计算）
    const CRC32_TABLE = initCRC32Table();

    /// 初始化CRC32查找表
    fn initCRC32Table() [256]u32 {
        @setEvalBranchQuota(10000);
        var table: [256]u32 = undefined;
        const polynomial: u32 = 0xEDB88320; // PNG使用的CRC32多项式

        var i: u32 = 0;
        while (i < 256) : (i += 1) {
            var crc: u32 = i;
            var j: u32 = 0;
            while (j < 8) : (j += 1) {
                if (crc & 1 != 0) {
                    crc = (crc >> 1) ^ polynomial;
                } else {
                    crc >>= 1;
                }
            }
            table[i] = crc;
        }
        return table;
    }

    /// 初始化PNG编码器
    pub fn init(allocator: std.mem.Allocator) PngEncoder {
        return .{ .allocator = allocator };
    }

    /// 编码RGBA像素数据为PNG格式
    /// 参数：
    /// - pixels: RGBA格式的像素数据（每像素4字节：R, G, B, A）
    /// - width: 图像宽度
    /// - height: 图像高度
    /// 返回：PNG格式的字节数据
    pub fn encode(self: PngEncoder, pixels: []const u8, width: u32, height: u32) ![]u8 {
        var output = std.ArrayList(u8){};
        errdefer output.deinit(self.allocator);

        // 1. 写入PNG文件签名
        try output.appendSlice(self.allocator, &PNG_SIGNATURE);

        // 2. 写入IHDR chunk
        try self.writeIHDRChunk(&output, width, height);

        // 3. 写入IDAT chunk（压缩的图像数据）
        try self.writeIDATChunk(&output, pixels, width, height);

        // 4. 写入IEND chunk
        try self.writeIENDChunk(&output);

        return try output.toOwnedSlice(self.allocator);
    }

    /// 写入IHDR chunk（图像头部信息）
    fn writeIHDRChunk(self: PngEncoder, output: *std.ArrayList(u8), width: u32, height: u32) !void {
        // IHDR数据：宽度(4) + 高度(4) + 位深度(1) + 颜色类型(1) + 压缩方法(1) + 滤波器方法(1) + 交错方法(1)
        var ihdr_data = std.ArrayList(u8){};
        defer ihdr_data.deinit(self.allocator);

        // 写入宽度（big-endian）
        try ihdr_data.writer(self.allocator).writeInt(u32, width, .big);
        // 写入高度（big-endian）
        try ihdr_data.writer(self.allocator).writeInt(u32, height, .big);
        // 位深度：8位
        try ihdr_data.append(self.allocator, 8);
        // 颜色类型：6 = RGBA（带alpha通道）
        try ihdr_data.append(self.allocator, 6);
        // 压缩方法：0 = DEFLATE
        try ihdr_data.append(self.allocator, 0);
        // 滤波器方法：0 = 无滤波器
        try ihdr_data.append(self.allocator, 0);
        // 交错方法：0 = 无交错
        try ihdr_data.append(self.allocator, 0);

        try self.writeChunk(output, "IHDR", ihdr_data.items);
    }

    /// 写入IDAT chunk（图像数据）
    fn writeIDATChunk(self: PngEncoder, output: *std.ArrayList(u8), pixels: []const u8, width: u32, height: u32) !void {
        // 准备图像数据：每行前面加一个滤波器字节（0 = 无滤波器）
        var image_data = std.ArrayList(u8){};
        defer image_data.deinit(self.allocator);

        var y: u32 = 0;
        while (y < height) : (y += 1) {
            // 每行前面加滤波器字节（0 = None）
            try image_data.append(self.allocator, 0);
            // 写入该行的像素数据
            const row_start = y * width * 4;
            const row_end = row_start + width * 4;
            try image_data.appendSlice(self.allocator, pixels[row_start..row_end]);
        }

        // 使用DEFLATE压缩图像数据
        const compressed = try self.deflateCompress(image_data.items);
        defer self.allocator.free(compressed);

        try self.writeChunk(output, "IDAT", compressed);
    }

    /// 写入IEND chunk（文件结束标记）
    fn writeIENDChunk(self: PngEncoder, output: *std.ArrayList(u8)) !void {
        // IEND chunk没有数据
        try self.writeChunk(output, "IEND", &[_]u8{});
    }

    /// 写入PNG chunk
    /// chunk格式：长度(4字节, big-endian) + 类型(4字节) + 数据 + CRC(4字节, big-endian)
    fn writeChunk(self: PngEncoder, output: *std.ArrayList(u8), chunk_type: []const u8, data: []const u8) !void {
        // 写入长度（big-endian）
        try output.writer(self.allocator).writeInt(u32, @as(u32, @intCast(data.len)), .big);

        // 写入chunk类型
        try output.appendSlice(self.allocator, chunk_type);

        // 写入数据
        try output.appendSlice(self.allocator, data);

        // 计算并写入CRC（chunk类型 + 数据）
        var crc_data = std.ArrayList(u8){};
        defer crc_data.deinit(self.allocator);
        try crc_data.appendSlice(self.allocator, chunk_type);
        try crc_data.appendSlice(self.allocator, data);
        const crc = self.calculateCRC(crc_data.items);
        try output.writer(self.allocator).writeInt(u32, crc, .big);
    }

    /// 计算CRC32校验码
    /// 使用IEEE 802.3标准的CRC32算法，多项式为0xEDB88320
    /// 这是PNG规范要求的CRC32实现
    pub fn calculateCRC(self: PngEncoder, data: []const u8) u32 {
        _ = self;
        var crc: u32 = 0xFFFFFFFF;

        for (data) |byte| {
            const index = @as(u8, @truncate(crc ^ @as(u32, byte)));
            crc = (crc >> 8) ^ CRC32_TABLE[index];
        }

        return crc ^ 0xFFFFFFFF;
    }

    /// DEFLATE压缩
    /// TODO: 简化实现 - 当前返回未压缩的数据（加上zlib头部和ADLER32校验）
    /// 完整实现需要使用DEFLATE压缩算法（zlib格式）
    /// 参考：RFC 1950 (zlib), RFC 1951 (DEFLATE)
    ///
    /// PNG使用zlib格式的DEFLATE压缩，包含：
    /// 1. zlib头部（2字节）
    /// 2. DEFLATE压缩数据
    /// 3. ADLER32校验（4字节）
    ///
    /// 当前实现只添加zlib头部和ADLER32，数据未压缩
    pub fn deflateCompress(self: PngEncoder, data: []const u8) ![]u8 {
        // TODO: 实现完整的DEFLATE压缩算法
        // 当前实现：添加zlib头部和ADLER32校验，但数据未压缩

        // zlib头部：CMF (1字节) + FLG (1字节)
        // CMF: 0x78 = deflate方法，32K窗口
        // FLG: 0x9C = FCHECK + FDICT + FLEVEL
        const zlib_header = [_]u8{ 0x78, 0x9C };

        // 计算ADLER32校验
        const adler32 = self.calculateAdler32(data);

        // 构建结果：zlib头部 + 原始数据 + ADLER32
        const result_len = zlib_header.len + data.len + 4;
        const result = try self.allocator.alloc(u8, result_len);
        errdefer self.allocator.free(result);

        var offset: usize = 0;
        @memcpy(result[offset..][0..zlib_header.len], &zlib_header);
        offset += zlib_header.len;

        @memcpy(result[offset..][0..data.len], data);
        offset += data.len;

        // 写入ADLER32（big-endian）
        result[offset] = @as(u8, @truncate(adler32 >> 24));
        result[offset + 1] = @as(u8, @truncate(adler32 >> 16));
        result[offset + 2] = @as(u8, @truncate(adler32 >> 8));
        result[offset + 3] = @as(u8, @truncate(adler32));

        return result;
    }

    /// 计算ADLER32校验（用于zlib）
    fn calculateAdler32(self: PngEncoder, data: []const u8) u32 {
        _ = self;
        var a: u32 = 1;
        var b: u32 = 0;
        const adler32_mod: u32 = 65521; // ADLER32模数

        for (data) |byte| {
            a = (a + @as(u32, byte)) % adler32_mod;
            b = (b + a) % adler32_mod;
        }

        return (b << 16) | a;
    }
};
