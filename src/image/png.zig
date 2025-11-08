const std = @import("std");
const deflate = @import("deflate");

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

    /// PNG滤波器类型
    const FilterType = enum(u8) {
        none = 0,
        sub = 1,
        up = 2,
        average = 3,
        paeth = 4,
    };

    /// 写入IDAT chunk（图像数据）
    fn writeIDATChunk(self: PngEncoder, output: *std.ArrayList(u8), pixels: []const u8, width: u32, height: u32) !void {
        const bpp: u32 = 4; // RGBA = 4 bytes per pixel
        const row_size = width * bpp;

        // 准备图像数据：每行前面加一个滤波器字节
        var image_data = std.ArrayList(u8){};
        defer image_data.deinit(self.allocator);

        // 存储前一行（用于Up、Average、Paeth滤波器）
        const prior_row = try self.allocator.alloc(u8, row_size);
        defer self.allocator.free(prior_row);
        @memset(prior_row, 0); // 第一行之前都是0

        var y: u32 = 0;
        while (y < height) : (y += 1) {
            const row_start = y * row_size;
            const row_end = row_start + row_size;
            const current_row = pixels[row_start..row_end];

            // 选择最优滤波器
            const best_filter = self.selectBestFilter(current_row, prior_row, bpp);
            const filtered_row = try self.applyFilter(current_row, prior_row, best_filter, bpp);
            defer self.allocator.free(filtered_row);

            // 写入滤波器类型字节
            try image_data.append(self.allocator, @intFromEnum(best_filter));
            // 写入滤波后的行数据
            try image_data.appendSlice(self.allocator, filtered_row);

            // 更新prior_row为当前行（未滤波的原始数据，用于下一行的滤波器）
            @memcpy(prior_row, current_row);
        }

        // 使用DEFLATE压缩图像数据
        const compressed = try self.deflateCompress(image_data.items);
        defer self.allocator.free(compressed);

        try self.writeChunk(output, "IDAT", compressed);
    }

    /// 选择最优滤波器
    /// 尝试所有滤波器，选择压缩后最小的
    fn selectBestFilter(self: PngEncoder, current_row: []const u8, prior_row: []const u8, bpp: u32) FilterType {
        var best_filter: FilterType = .none;
        var best_size: usize = std.math.maxInt(usize);

        // 尝试所有滤波器类型
        const filter_types = [_]FilterType{ .none, .sub, .up, .average, .paeth };
        for (filter_types) |filter_type| {
            // 应用滤波器
            const filtered_row = self.applyFilter(current_row, prior_row, filter_type, bpp) catch continue;
            defer self.allocator.free(filtered_row);

            // 压缩滤波后的数据（简化：只压缩这一行数据来估算）
            // 注意：实际压缩效果可能因为上下文而不同，但这是一个合理的近似
            const test_data = self.allocator.alloc(u8, 1 + filtered_row.len) catch continue;
            defer self.allocator.free(test_data);
            test_data[0] = @intFromEnum(filter_type);
            @memcpy(test_data[1..], filtered_row);

            // 压缩测试数据
            const compressed = self.deflateCompress(test_data) catch continue;
            defer self.allocator.free(compressed);

            // 选择压缩后最小的
            if (compressed.len < best_size) {
                best_size = compressed.len;
                best_filter = filter_type;
            }
        }

        return best_filter;
    }

    /// 应用PNG滤波器
    fn applyFilter(self: PngEncoder, current_row: []const u8, prior_row: []const u8, filter_type: FilterType, bpp: u32) ![]u8 {
        const filtered = try self.allocator.alloc(u8, current_row.len);
        errdefer self.allocator.free(filtered);

        switch (filter_type) {
            .none => {
                // None滤波器：直接复制
                @memcpy(filtered, current_row);
            },
            .sub => {
                // Sub滤波器：filtered[x] = original[x] - original[x-bpp]
                var i: usize = 0;
                while (i < current_row.len) : (i += 1) {
                    if (i < bpp) {
                        filtered[i] = current_row[i];
                    } else {
                        filtered[i] = current_row[i] -% current_row[i - bpp];
                    }
                }
            },
            .up => {
                // Up滤波器：filtered[x] = original[x] - prior[x]
                var i: usize = 0;
                while (i < current_row.len) : (i += 1) {
                    filtered[i] = current_row[i] -% prior_row[i];
                }
            },
            .average => {
                // Average滤波器：filtered[x] = original[x] - floor((original[x-bpp] + prior[x]) / 2)
                var i: usize = 0;
                while (i < current_row.len) : (i += 1) {
                    const left = if (i >= bpp) current_row[i - bpp] else 0;
                    const up = prior_row[i];
                    filtered[i] = current_row[i] -% @as(u8, @intCast((@as(u16, left) + @as(u16, up)) / 2));
                }
            },
            .paeth => {
                // Paeth滤波器：filtered[x] = original[x] - paethPredictor(original[x-bpp], prior[x], prior[x-bpp])
                var i: usize = 0;
                while (i < current_row.len) : (i += 1) {
                    const left = if (i >= bpp) current_row[i - bpp] else 0;
                    const up = prior_row[i];
                    const up_left = if (i >= bpp) prior_row[i - bpp] else 0;
                    const predictor = self.paethPredictor(left, up, up_left);
                    filtered[i] = current_row[i] -% predictor;
                }
            },
        }

        return filtered;
    }

    /// Paeth预测器
    fn paethPredictor(self: PngEncoder, a: u8, b: u8, c: u8) u8 {
        _ = self;
        const a_i16 = @as(i16, @intCast(a));
        const b_i16 = @as(i16, @intCast(b));
        const c_i16 = @as(i16, @intCast(c));

        const p = a_i16 + b_i16 - c_i16;
        const pa = if (p > a_i16) p - a_i16 else a_i16 - p;
        const pb = if (p > b_i16) p - b_i16 else b_i16 - p;
        const pc = if (p > c_i16) p - c_i16 else c_i16 - p;

        if (pa <= pb and pa <= pc) {
            return a;
        } else if (pb <= pc) {
            return b;
        } else {
            return c;
        }
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
    /// 使用DEFLATE压缩算法（zlib格式）
    /// 参考：RFC 1950 (zlib), RFC 1951 (DEFLATE)
    ///
    /// PNG使用zlib格式的DEFLATE压缩，包含：
    /// 1. zlib头部（2字节）
    /// 2. DEFLATE压缩数据
    /// 3. ADLER32校验（4字节）
    pub fn deflateCompress(self: PngEncoder, data: []const u8) ![]u8 {
        // 使用DEFLATE压缩器压缩数据
        var compressor = deflate.DeflateCompressor.init(self.allocator);
        const deflate_data = try compressor.compress(data);
        defer self.allocator.free(deflate_data);

        // zlib头部：CMF (1字节) + FLG (1字节)
        // CMF: 0x78 = deflate方法，32K窗口
        // FLG: 0x9C = FCHECK + FDICT + FLEVEL
        const zlib_header = [_]u8{ 0x78, 0x9C };

        // 计算ADLER32校验（基于原始数据）
        const adler32 = self.calculateAdler32(data);

        // 构建结果：zlib头部 + DEFLATE压缩数据 + ADLER32
        const result_len = zlib_header.len + deflate_data.len + 4;
        const result = try self.allocator.alloc(u8, result_len);
        errdefer self.allocator.free(result);

        var offset: usize = 0;
        @memcpy(result[offset..][0..zlib_header.len], &zlib_header);
        offset += zlib_header.len;

        @memcpy(result[offset..][0..deflate_data.len], deflate_data);
        offset += deflate_data.len;

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
