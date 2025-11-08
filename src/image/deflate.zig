const std = @import("std");

/// DEFLATE压缩算法实现
/// 参考：RFC 1951 (DEFLATE)
pub const DeflateCompressor = struct {
    allocator: std.mem.Allocator,

    /// LZ77窗口大小（32KB）
    const WINDOW_SIZE: usize = 32768;
    /// 最小匹配长度
    const MIN_MATCH: usize = 3;
    /// 最大匹配长度
    const MAX_MATCH: usize = 258;
    /// 最大距离
    const MAX_DISTANCE: usize = 32768;

    /// 固定Huffman编码表（RFC 1951定义）
    ///
    /// 字面量/长度编码（0-285）：
    /// - 字面量 0-143: 8位编码，值 = 0x030 + 字面量值
    /// - 字面量 144-255: 9位编码，值 = 0x190 + (字面量值 - 144)
    /// - 结束标记 256: 7位编码，值 = 0x000
    /// - 长度 257-264: 7位编码，值 = 0x000 + (长度码 - 257)
    /// - 长度 265-284: 8位编码，值 = 0x100 + (长度码 - 265)
    /// - 长度 285: 8位编码，值 = 0x11C
    ///
    /// 距离编码（0-29）：
    /// - 距离码 0-29: 5位编码，值 = 距离码
    /// 初始化DEFLATE压缩器
    pub fn init(allocator: std.mem.Allocator) DeflateCompressor {
        return .{ .allocator = allocator };
    }

    /// 压缩数据
    /// 实现LZ77压缩和固定Huffman编码
    pub fn compress(self: DeflateCompressor, data: []const u8) ![]u8 {
        var output = std.ArrayList(u8){};
        errdefer output.deinit(self.allocator);

        // DEFLATE块头：BFINAL(1) + BTYPE(2) = 3位
        // 使用固定Huffman编码（BTYPE=01）
        // BFINAL=1（最后一个块），BTYPE=01（固定Huffman编码）
        var bit_buffer: u32 = 0;
        var bit_count: u32 = 0;

        // 写入块头：BFINAL=1, BTYPE=01
        bit_buffer |= 1 << 0; // BFINAL=1
        bit_buffer |= 1 << 1; // BTYPE=01
        bit_count = 3;

        var i: usize = 0;
        while (i < data.len) {
            // 查找最长匹配
            const match = self.findLongestMatch(data, i);

            if (match.length >= MIN_MATCH and match.distance <= MAX_DISTANCE) {
                // 找到匹配，写入长度/距离对
                try self.writeLengthDistance(&output, &bit_buffer, &bit_count, match.length, match.distance);
                i += match.length;
            } else {
                // 没有匹配，写入字面量
                try self.writeLiteral(&output, &bit_buffer, &bit_count, data[i]);
                i += 1;
            }
        }

        // 写入结束标记（256）
        try self.writeEndOfBlock(&output, &bit_buffer, &bit_count);

        // 刷新位缓冲区（对齐到字节边界）
        if (bit_count > 0) {
            try output.append(self.allocator, @truncate(bit_buffer));
        }

        return try output.toOwnedSlice(self.allocator);
    }

    /// 写入字面量（使用固定Huffman编码）
    /// 字面量 0-143: 8位编码，值 = 0x030 + 字面量值
    /// 字面量 144-255: 9位编码，值 = 0x190 + (字面量值 - 144)
    fn writeLiteral(self: DeflateCompressor, output: *std.ArrayList(u8), bit_buffer: *u32, bit_count: *u32, value: u8) !void {
        const literal = @as(u16, value);
        if (literal <= 143) {
            // 字面量 0-143: 8位编码
            // 编码值 = 0x030 + 字面量值
            // 二进制：00110000 + 字面量值（低8位）
            const code: u16 = 0x030 + literal;
            try self.writeBits(output, bit_buffer, bit_count, code, 8);
        } else {
            // 字面量 144-255: 9位编码
            // 编码值 = 0x190 + (字面量值 - 144)
            // 二进制：110010000 + (字面量值 - 144)（低9位）
            const code: u16 = 0x190 + (literal - 144);
            try self.writeBits(output, bit_buffer, bit_count, code, 9);
        }
    }

    /// 写入结束标记（256）
    /// 结束标记 256: 7位编码，值 = 0x000
    fn writeEndOfBlock(self: DeflateCompressor, output: *std.ArrayList(u8), bit_buffer: *u32, bit_count: *u32) !void {
        const code: u16 = 0x000; // 结束标记的编码（7位：0000000）
        try self.writeBits(output, bit_buffer, bit_count, code, 7);
    }

    /// 写入长度/距离对（使用固定Huffman编码）
    /// 长度编码：257-285
    /// 距离编码：0-29
    fn writeLengthDistance(self: DeflateCompressor, output: *std.ArrayList(u8), bit_buffer: *u32, bit_count: *u32, length: usize, distance: usize) !void {
        // 编码长度
        try self.writeLength(output, bit_buffer, bit_count, length);

        // 编码距离
        try self.writeDistance(output, bit_buffer, bit_count, distance);
    }

    /// 编码长度（257-285）
    /// 根据RFC 1951，长度编码包括：
    /// - 长度码（257-285）
    /// - 额外位（根据长度范围）
    fn writeLength(self: DeflateCompressor, output: *std.ArrayList(u8), bit_buffer: *u32, bit_count: *u32, length: usize) !void {
        if (length < MIN_MATCH or length > MAX_MATCH) {
            return;
        }

        // 将长度映射到长度码（257-285）
        // RFC 1951定义的长度码表：
        // 长度3: 码257
        // 长度4: 码258
        // 长度5-6: 码259-260（1额外位）
        // 长度7-8: 码261-262（1额外位）
        // 长度9-12: 码263-264（2额外位）
        // 长度13-16: 码265-266（2额外位）
        // 长度17-24: 码267-270（3额外位）
        // 长度25-32: 码271-274（3额外位）
        // 长度33-48: 码275-278（4额外位）
        // 长度49-64: 码279-282（4额外位）
        // 长度65-128: 码283-284（5额外位）
        // 长度129-258: 码285（无额外位，表示长度258）

        var length_code: u16 = 257;
        var extra_bits: u32 = 0;
        var extra_value: u32 = 0;

        if (length == 3) {
            length_code = 257;
            extra_bits = 0;
        } else if (length == 4) {
            length_code = 258;
            extra_bits = 0;
        } else if (length <= 6) {
            // 长度5-6: 码259-260
            length_code = @as(u16, @intCast(259 + (length - 5)));
            extra_bits = 1;
            extra_value = @as(u32, @intCast((length - 5) % 2));
        } else if (length <= 8) {
            // 长度7-8: 码261-262
            length_code = @as(u16, @intCast(261 + (length - 7)));
            extra_bits = 1;
            extra_value = @as(u32, @intCast((length - 7) % 2));
        } else if (length <= 12) {
            // 长度9-12: 码263-264
            length_code = @as(u16, @intCast(263 + ((length - 9) / 2)));
            extra_bits = 2;
            extra_value = @as(u32, @intCast((length - 9) % 2));
        } else if (length <= 16) {
            // 长度13-16: 码265-266
            length_code = @as(u16, @intCast(265 + ((length - 13) / 2)));
            extra_bits = 2;
            extra_value = @as(u32, @intCast((length - 13) % 2));
        } else if (length <= 24) {
            // 长度17-24: 码267-270
            length_code = @as(u16, @intCast(267 + ((length - 17) / 2)));
            extra_bits = 3;
            extra_value = @as(u32, @intCast((length - 17) % 2));
        } else if (length <= 32) {
            // 长度25-32: 码271-274
            length_code = @as(u16, @intCast(271 + ((length - 25) / 2)));
            extra_bits = 3;
            extra_value = @as(u32, @intCast((length - 25) % 2));
        } else if (length <= 48) {
            // 长度33-48: 码275-278
            length_code = @as(u16, @intCast(275 + ((length - 33) / 4)));
            extra_bits = 4;
            extra_value = @as(u32, @intCast((length - 33) % 4));
        } else if (length <= 64) {
            // 长度49-64: 码279-282
            length_code = @as(u16, @intCast(279 + ((length - 49) / 4)));
            extra_bits = 4;
            extra_value = @as(u32, @intCast((length - 49) % 4));
        } else if (length <= 128) {
            // 长度65-128: 码283-284
            length_code = @as(u16, @intCast(283 + ((length - 65) / 32)));
            extra_bits = 5;
            extra_value = @as(u32, @intCast((length - 65) % 32));
        } else {
            // 长度129-258: 码285（表示长度258）
            length_code = 285;
            extra_bits = 0;
        }

        // 编码长度码（使用固定Huffman编码）
        // 长度码257-264: 7位编码，值 = 0x000 + (长度码 - 257)
        // 长度码265-284: 8位编码，值 = 0x100 + (长度码 - 265)
        // 长度码285: 8位编码，值 = 0x11C
        if (length_code <= 264) {
            // 长度码257-264: 7位编码
            const code: u16 = @as(u16, @intCast(0x000 + (length_code - 257)));
            try self.writeBits(output, bit_buffer, bit_count, code, 7);
        } else if (length_code <= 284) {
            // 长度码265-284: 8位编码
            const code: u16 = @as(u16, @intCast(0x100 + (length_code - 265)));
            try self.writeBits(output, bit_buffer, bit_count, code, 8);
        } else {
            // 长度码285: 8位编码
            const code: u16 = 0x11C;
            try self.writeBits(output, bit_buffer, bit_count, code, 8);
        }

        // 写入额外位
        if (extra_bits > 0) {
            try self.writeBits(output, bit_buffer, bit_count, extra_value, extra_bits);
        }
    }

    /// 编码距离（0-29）
    /// 根据RFC 1951，距离编码包括：
    /// - 距离码（0-29）
    /// - 额外位（根据距离范围）
    fn writeDistance(self: DeflateCompressor, output: *std.ArrayList(u8), bit_buffer: *u32, bit_count: *u32, distance: usize) !void {
        if (distance < 1 or distance > MAX_DISTANCE) {
            return;
        }

        // 将距离映射到距离码（0-29）
        // RFC 1951定义的距离码表：
        // 距离1: 码0
        // 距离2: 码1
        // 距离3: 码2
        // 距离4: 码3
        // 距离5-6: 码4-5（1额外位）
        // 距离7-8: 码6-7（1额外位）
        // 距离9-12: 码8-9（2额外位）
        // 距离13-16: 码10-11（2额外位）
        // 距离17-24: 码12-13（3额外位）
        // 距离25-32: 码14-15（3额外位）
        // 距离33-48: 码16-17（4额外位）
        // 距离49-64: 码18-19（4额外位）
        // 距离65-96: 码20-21（5额外位）
        // 距离97-128: 码22-23（5额外位）
        // 距离129-192: 码24-25（6额外位）
        // 距离193-256: 码26-27（6额外位）
        // 距离257-512: 码28（7额外位）
        // 距离513-1024: 码29（8额外位）
        // ... 等等（最大距离32768）

        var distance_code: u16 = 0;
        var extra_bits: u32 = 0;
        var extra_value: u32 = 0;

        if (distance == 1) {
            distance_code = 0;
            extra_bits = 0;
        } else if (distance == 2) {
            distance_code = 1;
            extra_bits = 0;
        } else if (distance == 3) {
            distance_code = 2;
            extra_bits = 0;
        } else if (distance == 4) {
            distance_code = 3;
            extra_bits = 0;
        } else if (distance <= 6) {
            // 距离5-6: 码4-5
            distance_code = @as(u16, @intCast(4 + (distance - 5)));
            extra_bits = 1;
            extra_value = @as(u32, @intCast((distance - 5) % 2));
        } else if (distance <= 8) {
            // 距离7-8: 码6-7
            distance_code = @as(u16, @intCast(6 + (distance - 7)));
            extra_bits = 1;
            extra_value = @as(u32, @intCast((distance - 7) % 2));
        } else if (distance <= 12) {
            // 距离9-12: 码8-9
            distance_code = @as(u16, @intCast(8 + ((distance - 9) / 2)));
            extra_bits = 2;
            extra_value = @as(u32, @intCast((distance - 9) % 2));
        } else if (distance <= 16) {
            // 距离13-16: 码10-11
            distance_code = @as(u16, @intCast(10 + ((distance - 13) / 2)));
            extra_bits = 2;
            extra_value = @as(u32, @intCast((distance - 13) % 2));
        } else if (distance <= 24) {
            // 距离17-24: 码12-13
            distance_code = @as(u16, @intCast(12 + ((distance - 17) / 4)));
            extra_bits = 3;
            extra_value = @as(u32, @intCast((distance - 17) % 4));
        } else if (distance <= 32) {
            // 距离25-32: 码14-15
            distance_code = @as(u16, @intCast(14 + ((distance - 25) / 4)));
            extra_bits = 3;
            extra_value = @as(u32, @intCast((distance - 25) % 4));
        } else if (distance <= 48) {
            // 距离33-48: 码16-17
            distance_code = @as(u16, @intCast(16 + ((distance - 33) / 8)));
            extra_bits = 4;
            extra_value = @as(u32, @intCast((distance - 33) % 8));
        } else if (distance <= 64) {
            // 距离49-64: 码18-19
            distance_code = @as(u16, @intCast(18 + ((distance - 49) / 8)));
            extra_bits = 4;
            extra_value = @as(u32, @intCast((distance - 49) % 8));
        } else if (distance <= 96) {
            // 距离65-96: 码20-21
            distance_code = @as(u16, @intCast(20 + ((distance - 65) / 16)));
            extra_bits = 5;
            extra_value = @as(u32, @intCast((distance - 65) % 16));
        } else if (distance <= 128) {
            // 距离97-128: 码22-23
            distance_code = @as(u16, @intCast(22 + ((distance - 97) / 16)));
            extra_bits = 5;
            extra_value = @as(u32, @intCast((distance - 97) % 16));
        } else if (distance <= 192) {
            // 距离129-192: 码24-25
            distance_code = @as(u16, @intCast(24 + ((distance - 129) / 32)));
            extra_bits = 6;
            extra_value = @as(u32, @intCast((distance - 129) % 32));
        } else if (distance <= 256) {
            // 距离193-256: 码26-27
            distance_code = @as(u16, @intCast(26 + ((distance - 193) / 32)));
            extra_bits = 6;
            extra_value = @as(u32, @intCast((distance - 193) % 32));
        } else if (distance <= 512) {
            // 距离257-512: 码28
            distance_code = 28;
            extra_bits = 7;
            extra_value = @as(u32, @intCast((distance - 257) % 128));
        } else if (distance <= 1024) {
            // 距离513-1024: 码29
            distance_code = 29;
            extra_bits = 8;
            extra_value = @as(u32, @intCast((distance - 513) % 256));
        } else {
            // 更大的距离：继续使用码29，但需要更多额外位
            // TODO: 实现完整的距离编码表（最大距离32768）
            distance_code = 29;
            extra_bits = 13; // 最大距离32768需要13位
            extra_value = @as(u32, @intCast((distance - 1) % 8192));
        }

        // 编码距离码（5位编码）
        try self.writeBits(output, bit_buffer, bit_count, distance_code, 5);

        // 写入额外位
        if (extra_bits > 0) {
            try self.writeBits(output, bit_buffer, bit_count, extra_value, extra_bits);
        }
    }

    /// 查找最长匹配（简化实现）
    /// TODO: 优化：使用哈希表加速匹配查找
    pub fn findLongestMatch(self: DeflateCompressor, data: []const u8, pos: usize) struct { length: usize, distance: usize } {
        _ = self;
        var best_length: usize = 0;
        var best_distance: usize = 0;

        // 搜索窗口：从当前位置向前搜索，最多WINDOW_SIZE字节
        const search_start = if (pos > WINDOW_SIZE) pos - WINDOW_SIZE else 0;
        var search_pos = search_start;

        // 限制搜索范围以提高性能（简化实现）
        const max_search = @min(pos - search_start, 1024); // 最多搜索1024个位置

        var searched: usize = 0;
        while (searched < max_search and search_pos < pos) {
            var match_len: usize = 0;
            while (pos + match_len < data.len and
                search_pos + match_len < pos and
                data[search_pos + match_len] == data[pos + match_len] and
                match_len < MAX_MATCH)
            {
                match_len += 1;
            }

            if (match_len > best_length) {
                best_length = match_len;
                best_distance = pos - search_pos;
            }

            search_pos += 1;
            searched += 1;
        }

        return .{ .length = best_length, .distance = best_distance };
    }

    /// 写入位到输出流
    fn writeBits(self: DeflateCompressor, output: *std.ArrayList(u8), bit_buffer: *u32, bit_count: *u32, value: u32, bits: u32) !void {
        bit_buffer.* |= (value << @as(u5, @intCast(bit_count.*)));
        bit_count.* += bits;

        while (bit_count.* >= 8) {
            try output.append(self.allocator, @truncate(bit_buffer.*));
            bit_buffer.* >>= 8;
            bit_count.* -= 8;
        }
    }
};
