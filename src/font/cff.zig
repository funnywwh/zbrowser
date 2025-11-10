const std = @import("std");

/// INDEX信息结构
pub const IndexInfo = struct {
    count: u16,
    offset_size: u8,
    offset_array_start: usize,
    data_offset: usize,
};

/// CFF（Compact Font Format）解析器
/// 用于解析PostScript轮廓（OTF字体）
/// 参考：Adobe CFF规范、OpenType规范
pub const CffParser = struct {
    allocator: std.mem.Allocator,
    /// CFF表数据
    cff_data: []const u8,
    /// 当前读取位置
    offset: usize,

    const Self = @This();

    /// CFF头部
    const Header = struct {
        major: u8,
        minor: u8,
        hdr_size: u8,
        off_size: u8,
    };

    /// 初始化CFF解析器
    pub fn init(allocator: std.mem.Allocator, cff_data: []const u8) !Self {
        if (cff_data.len < 4) {
            return error.InvalidFormat;
        }

        return .{
            .allocator = allocator,
            .cff_data = cff_data,
            .offset = 0,
        };
    }

    /// 清理CFF解析器
    pub fn deinit(self: *Self) void {
        _ = self;
        // CFF解析器不分配额外内存，只需要清理offset
    }

    /// 读取CFF头部
    pub fn readHeader(self: *Self) !Header {
        if (self.offset + 4 > self.cff_data.len) {
            return error.InvalidFormat;
        }

        const header = Header{
            .major = self.cff_data[self.offset],
            .minor = self.cff_data[self.offset + 1],
            .hdr_size = self.cff_data[self.offset + 2],
            .off_size = self.cff_data[self.offset + 3],
        };

        // 跳过头部（hdr_size字节）
        self.offset += @as(usize, header.hdr_size);
        return header;
    }

    /// 读取INDEX结构
    /// INDEX是CFF中用于存储多个对象的通用结构
    pub fn readIndex(self: *Self) !IndexInfo {
        if (self.offset + 2 > self.cff_data.len) {
            return error.InvalidFormat;
        }

        const count = std.mem.readInt(u16, self.cff_data[self.offset..][0..2], .big);
        self.offset += 2;

        if (count == 0) {
            return .{ .count = 0, .offset_size = 0, .offset_array_start = self.offset, .data_offset = self.offset };
        }

        if (self.offset + 1 > self.cff_data.len) {
            return error.InvalidFormat;
        }

        const offset_size = self.cff_data[self.offset];
        self.offset += 1;

        // 记录偏移数组的起始位置
        const offset_array_start = self.offset;

        // 读取偏移数组（count + 1个偏移值）
        const offsets_size = @as(usize, count + 1) * @as(usize, offset_size);
        if (self.offset + offsets_size > self.cff_data.len) {
            return error.InvalidFormat;
        }

        const data_offset = self.offset + offsets_size;
        self.offset = data_offset;

        return .{ .count = count, .offset_size = offset_size, .offset_array_start = offset_array_start, .data_offset = data_offset };
    }

    /// 从INDEX中读取指定索引的对象
    pub fn readIndexObject(self: *Self, index_info: IndexInfo, object_index: u16) ![]const u8 {
        if (object_index >= index_info.count) {
            return error.OutOfBounds;
        }

        const offset1_pos = index_info.offset_array_start + @as(usize, object_index) * @as(usize, index_info.offset_size);
        const offset2_pos = index_info.offset_array_start + @as(usize, object_index + 1) * @as(usize, index_info.offset_size);

        const offset1 = try self.readOffset(offset1_pos, index_info.offset_size);
        const offset2 = try self.readOffset(offset2_pos, index_info.offset_size);

        const object_start = index_info.data_offset + offset1 - 1; // CFF偏移从1开始
        const object_end = index_info.data_offset + offset2 - 1;
        const object_length = object_end - object_start;

        if (object_start + object_length > self.cff_data.len) {
            return error.InvalidFormat;
        }

        return self.cff_data[object_start .. object_start + object_length];
    }

    /// 读取偏移值
    fn readOffset(self: *Self, pos: usize, size: u8) !u32 {
        if (pos + size > self.cff_data.len) {
            return error.InvalidFormat;
        }

        return switch (size) {
            1 => @as(u32, self.cff_data[pos]),
            2 => std.mem.readInt(u16, self.cff_data[pos..][0..2], .big),
            3 => blk: {
                var value: u32 = 0;
                value |= @as(u32, self.cff_data[pos]) << 16;
                value |= @as(u32, self.cff_data[pos + 1]) << 8;
                value |= @as(u32, self.cff_data[pos + 2]);
                break :blk value;
            },
            4 => std.mem.readInt(u32, self.cff_data[pos..][0..4], .big),
            else => return error.InvalidFormat,
        };
    }

    /// 解析CharStrings INDEX，获取字形数据
    pub fn getCharString(self: *Self, glyph_index: u16) ![]const u8 {
        // 重置offset到CFF表开始
        self.offset = 0;

        // 读取头部（跳过，不需要使用）
        _ = try self.readHeader();

        // 读取Name INDEX（跳过）
        const name_index = try self.readIndex();
        // 跳过Name INDEX的数据
        if (name_index.count > 0) {
            const last_offset_pos = self.offset - @as(usize, name_index.offset_size);
            const last_offset = try self.readOffset(last_offset_pos, name_index.offset_size);
            self.offset = name_index.data_offset + last_offset - 1;
        }

        // 读取Top DICT INDEX（跳过）
        const top_dict_index = try self.readIndex();
        // 跳过Top DICT INDEX的数据
        if (top_dict_index.count > 0) {
            const last_offset_pos = self.offset - @as(usize, top_dict_index.offset_size);
            const last_offset = try self.readOffset(last_offset_pos, top_dict_index.offset_size);
            self.offset = top_dict_index.data_offset + last_offset - 1;
        }

        // 读取String INDEX（跳过）
        const string_index = try self.readIndex();
        // 跳过String INDEX的数据
        if (string_index.count > 0) {
            const last_offset_pos = self.offset - @as(usize, string_index.offset_size);
            const last_offset = try self.readOffset(last_offset_pos, string_index.offset_size);
            self.offset = string_index.data_offset + last_offset - 1;
        }

        // 读取Global Subr INDEX（跳过）
        const global_subr_index = try self.readIndex();
        // 跳过Global Subr INDEX的数据
        if (global_subr_index.count > 0) {
            const last_offset_pos = self.offset - @as(usize, global_subr_index.offset_size);
            const last_offset = try self.readOffset(last_offset_pos, global_subr_index.offset_size);
            self.offset = global_subr_index.data_offset + last_offset - 1;
        }

        // 读取CharStrings INDEX
        const charstrings_index = try self.readIndex();

        if (glyph_index >= charstrings_index.count) {
            return error.OutOfBounds;
        }

        // 读取指定字形的CharString
        return self.readIndexObject(charstrings_index, glyph_index);
    }
};

/// CharString解码器
/// 解码Type 2 CharString格式的PostScript轮廓指令
pub const CharStringDecoder = struct {
    allocator: std.mem.Allocator,
    /// CharString数据
    charstring_data: []const u8,
    /// 当前读取位置
    offset: usize,
    /// 操作数栈
    stack: std.ArrayList(i32),
    /// 解码后的点列表
    points: std.ArrayList(Point),
    /// 轮廓结束点索引列表（每个轮廓的最后一个点索引）
    contour_end_indices: std.ArrayList(usize),
    /// 上一个moveto的点索引（用于检测轮廓结束）
    last_moveto_index: ?usize,

    const Self = @This();

    /// 点结构（支持三次贝塞尔曲线）
    pub const Point = struct {
        x: f32,
        y: f32,
        /// 点类型：0=普通点，1=二次控制点，2=三次控制点1，3=三次控制点2
        point_type: u8,
    };

    /// 初始化CharString解码器
    pub fn init(allocator: std.mem.Allocator, charstring_data: []const u8) Self {
        return .{
            .allocator = allocator,
            .charstring_data = charstring_data,
            .offset = 0,
            .stack = std.ArrayList(i32){},
            .points = std.ArrayList(Point){},
            .contour_end_indices = std.ArrayList(usize){},
            .last_moveto_index = null,
        };
    }

    /// 清理CharString解码器
    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.allocator);
        self.points.deinit(self.allocator);
        self.contour_end_indices.deinit(self.allocator);
    }

    /// 解码CharString
    pub fn decode(self: *Self) !void {
        var current_x: f32 = 0;
        var current_y: f32 = 0;
        self.last_moveto_index = null; // 重置moveto索引

        while (self.offset < self.charstring_data.len) {
            const byte = self.charstring_data[self.offset];
            self.offset += 1;

            // Type 2 CharString指令
            if (byte == 12) {
                // 两字节转义序列（12.XX）
                if (self.offset >= self.charstring_data.len) {
                    return error.InvalidFormat;
                }
                const escape_byte = self.charstring_data[self.offset];
                self.offset += 1;
                std.log.warn("[CFF] CharStringDecoder: encountered escape command 12.{d}", .{escape_byte});
                // 处理转义命令（12.XX）
                try self.handleEscapeCommand(escape_byte, &current_x, &current_y);
            } else if (byte >= 0 and byte <= 27) {
                // 单字节指令（0-27）
                try self.handleCommand(byte, &current_x, &current_y);
            } else if (byte == 28) {
                // 两字节整数（-32768到32767）
                if (self.offset + 2 > self.charstring_data.len) {
                    return error.InvalidFormat;
                }
                const value = std.mem.readInt(i16, self.charstring_data[self.offset..][0..2], .big);
                self.offset += 2;
                try self.stack.append(self.allocator, value);
            } else if (byte >= 29 and byte <= 31) {
                // 特殊指令（29-31）
                try self.handleCommand(byte, &current_x, &current_y);
            } else if (byte >= 32 and byte <= 246) {
                // 单字节整数（-107到107）
                const value = @as(i32, byte) - 139;
                try self.stack.append(self.allocator, value);
            } else if (byte >= 247 and byte <= 250) {
                // 两字节整数（108到1131）
                if (self.offset >= self.charstring_data.len) {
                    return error.InvalidFormat;
                }
                const byte2 = self.charstring_data[self.offset];
                self.offset += 1;
                const value = (@as(i32, byte) - 247) * 256 + @as(i32, byte2) + 108;
                try self.stack.append(self.allocator, value);
            } else if (byte >= 251 and byte <= 254) {
                // 两字节整数（-1131到-108）
                if (self.offset >= self.charstring_data.len) {
                    return error.InvalidFormat;
                }
                const byte2 = self.charstring_data[self.offset];
                self.offset += 1;
                const value = -(@as(i32, byte) - 251) * 256 - @as(i32, byte2) - 108;
                try self.stack.append(self.allocator, value);
            } else if (byte == 255) {
                // 四字节浮点数（暂不支持，简化实现）
                // TODO: 实现浮点数解码
                std.log.warn("[CFF] CharStringDecoder: encountered float (byte 255) at offset {d}, skipping", .{self.offset - 1});
                // 跳过4字节浮点数
                if (self.offset + 4 > self.charstring_data.len) {
                    return error.InvalidFormat;
                }
                self.offset += 4;
                // 不添加到栈中，因为当前实现不支持浮点数
                // 这可能导致某些字形无法正确渲染，但至少不会崩溃
            } else {
                std.log.warn("[CFF] CharStringDecoder: unknown byte {d} at offset {d}, charstring_data.len={d}", .{ byte, self.offset - 1, self.charstring_data.len });
                return error.InvalidFormat;
            }
        }
    }

    /// 处理CharString指令
    fn handleCommand(self: *Self, command: u8, current_x: *f32, current_y: *f32) !void {
        std.log.warn("[CFF] CharStringDecoder: handleCommand command={d}, offset={d}, stack.len={d}", .{ command, self.offset - 1, self.stack.items.len });
        switch (command) {
            0 => {
                // reserved - 保留命令，忽略
                std.log.warn("[CFF] CharStringDecoder: encountered reserved command 0, ignoring", .{});
            },
            1 => {
                // hstem - 水平stem提示（忽略）
                _ = try self.popStack();
                _ = try self.popStack();
            },
            3 => {
                // vstem - 垂直stem提示（忽略）
                _ = try self.popStack();
                _ = try self.popStack();
            },
            4 => {
                // vmoveto - 垂直移动到
                // 如果之前有轮廓，记录上一个轮廓的结束点
                if (self.last_moveto_index) |last_index| {
                    if (self.points.items.len > last_index) {
                        try self.contour_end_indices.append(self.allocator, self.points.items.len - 1);
                    }
                }
                if (self.stack.items.len >= 1) {
                    const dy = @as(f32, @floatFromInt(try self.popStack()));
                    current_y.* += dy;
                    try self.points.append(self.allocator, Point{
                        .x = current_x.*,
                        .y = current_y.*,
                        .point_type = 0,
                    });
                    self.last_moveto_index = self.points.items.len - 1;
                }
            },
            5 => {
                // rlineto - 相对直线
                while (self.stack.items.len >= 2) {
                    const dx = @as(f32, @floatFromInt(try self.popStack()));
                    const dy = @as(f32, @floatFromInt(try self.popStack()));
                    current_x.* += dx;
                    current_y.* += dy;
                    try self.points.append(self.allocator, Point{
                        .x = current_x.*,
                        .y = current_y.*,
                        .point_type = 0,
                    });
                }
            },
            6 => {
                // hlineto - 水平线
                var is_horizontal = true;
                while (self.stack.items.len >= 1) {
                    if (is_horizontal) {
                        const dx = @as(f32, @floatFromInt(try self.popStack()));
                        current_x.* += dx;
                    } else {
                        const dy = @as(f32, @floatFromInt(try self.popStack()));
                        current_y.* += dy;
                    }
                    try self.points.append(self.allocator, Point{
                        .x = current_x.*,
                        .y = current_y.*,
                        .point_type = 0,
                    });
                    is_horizontal = !is_horizontal;
                }
            },
            7 => {
                // vlineto - 垂直线
                var is_vertical = true;
                while (self.stack.items.len >= 1) {
                    if (is_vertical) {
                        const dy = @as(f32, @floatFromInt(try self.popStack()));
                        current_y.* += dy;
                    } else {
                        const dx = @as(f32, @floatFromInt(try self.popStack()));
                        current_x.* += dx;
                    }
                    try self.points.append(self.allocator, Point{
                        .x = current_x.*,
                        .y = current_y.*,
                        .point_type = 0,
                    });
                    is_vertical = !is_vertical;
                }
            },
            8 => {
                // rrcurveto - 相对三次贝塞尔曲线
                while (self.stack.items.len >= 6) {
                    const dx1 = @as(f32, @floatFromInt(try self.popStack()));
                    const dy1 = @as(f32, @floatFromInt(try self.popStack()));
                    const dx2 = @as(f32, @floatFromInt(try self.popStack()));
                    const dy2 = @as(f32, @floatFromInt(try self.popStack()));
                    const dx3 = @as(f32, @floatFromInt(try self.popStack()));
                    const dy3 = @as(f32, @floatFromInt(try self.popStack()));

                    // 第一个控制点
                    const cp1_x = current_x.* + dx1;
                    const cp1_y = current_y.* + dy1;
                    try self.points.append(self.allocator, Point{
                        .x = cp1_x,
                        .y = cp1_y,
                        .point_type = 2, // 三次贝塞尔曲线控制点1
                    });

                    // 第二个控制点
                    const cp2_x = cp1_x + dx2;
                    const cp2_y = cp1_y + dy2;
                    try self.points.append(self.allocator, Point{
                        .x = cp2_x,
                        .y = cp2_y,
                        .point_type = 3, // 三次贝塞尔曲线控制点2
                    });

                    // 终点
                    current_x.* = cp2_x + dx3;
                    current_y.* = cp2_y + dy3;
                    try self.points.append(self.allocator, Point{
                        .x = current_x.*,
                        .y = current_y.*,
                        .point_type = 0,
                    });
                }
            },
            10 => {
                // callsubr - 调用局部子程序（暂不支持）
                // TODO: 实现子程序调用
                std.log.warn("[CFF] CharStringDecoder: encountered callsubr (command 10) at offset {d}, stack.len={d}, skipping", .{ self.offset - 1, self.stack.items.len });
                // 从栈中弹出子程序编号（如果存在）
                if (self.stack.items.len > 0) {
                    const subr_num = try self.popStack();
                    std.log.warn("[CFF] CharStringDecoder: callsubr subr_num={d}, skipping call", .{subr_num});
                } else {
                    std.log.warn("[CFF] CharStringDecoder: callsubr with empty stack", .{});
                }
                // 不执行子程序调用，这可能导致某些字形无法正确渲染，但至少不会崩溃
            },
            11 => {
                // return - 从子程序返回（暂不支持）
                std.log.warn("[CFF] CharStringDecoder: encountered return (command 11) at offset {d}, stack.len={d}, skipping", .{ self.offset - 1, self.stack.items.len });
                // 不执行返回操作，这可能导致某些字形无法正确渲染，但至少不会崩溃
                // 注意：如果在主程序中遇到return，可能是格式错误
                if (self.stack.items.len > 0) {
                    std.log.warn("[CFF] CharStringDecoder: return with non-empty stack, clearing", .{});
                    self.stack.clearRetainingCapacity();
                }
            },
            14 => {
                // endchar - 结束字符
                // 可以包含宽度信息（如果栈中有值）
                if (self.stack.items.len >= 1) {
                    _ = try self.popStack(); // 宽度（忽略，使用hmtx表）
                }
                // 记录最后一个轮廓的结束点
                if (self.points.items.len > 0) {
                    try self.contour_end_indices.append(self.allocator, self.points.items.len - 1);
                }
            },
            18 => {
                // hstemhm - 水平stem提示（hintmask，忽略）
                // 需要读取hintmask数据
                const stem_count = self.stack.items.len / 2;
                for (0..stem_count) |_| {
                    _ = try self.popStack();
                    _ = try self.popStack();
                }
                // 读取hintmask（位掩码）
                const hintmask_size = (stem_count + 7) / 8;
                if (self.offset + hintmask_size > self.charstring_data.len) {
                    return error.InvalidFormat;
                }
                self.offset += hintmask_size;
            },
            19 => {
                // hintmask - hintmask指令（忽略）
                const stem_count = self.stack.items.len / 2;
                for (0..stem_count) |_| {
                    _ = try self.popStack();
                    _ = try self.popStack();
                }
                const hintmask_size = (stem_count + 7) / 8;
                if (self.offset + hintmask_size > self.charstring_data.len) {
                    return error.InvalidFormat;
                }
                self.offset += hintmask_size;
            },
            20 => {
                // cntrmask - cntrmask指令（忽略）
                const stem_count = self.stack.items.len / 2;
                for (0..stem_count) |_| {
                    _ = try self.popStack();
                    _ = try self.popStack();
                }
                const hintmask_size = (stem_count + 7) / 8;
                if (self.offset + hintmask_size > self.charstring_data.len) {
                    return error.InvalidFormat;
                }
                self.offset += hintmask_size;
            },
            21 => {
                // rmoveto - 相对移动
                // 如果之前有轮廓，记录上一个轮廓的结束点
                if (self.last_moveto_index) |last_index| {
                    if (self.points.items.len > last_index) {
                        try self.contour_end_indices.append(self.allocator, self.points.items.len - 1);
                    }
                }
                if (self.stack.items.len >= 2) {
                    const dx = @as(f32, @floatFromInt(try self.popStack()));
                    const dy = @as(f32, @floatFromInt(try self.popStack()));
                    current_x.* += dx;
                    current_y.* += dy;
                    try self.points.append(self.allocator, Point{
                        .x = current_x.*,
                        .y = current_y.*,
                        .point_type = 0,
                    });
                    self.last_moveto_index = self.points.items.len - 1;
                }
            },
            22 => {
                // hmoveto - 水平移动
                // 如果之前有轮廓，记录上一个轮廓的结束点
                if (self.last_moveto_index) |last_index| {
                    if (self.points.items.len > last_index) {
                        try self.contour_end_indices.append(self.allocator, self.points.items.len - 1);
                    }
                }
                if (self.stack.items.len >= 1) {
                    const dx = @as(f32, @floatFromInt(try self.popStack()));
                    current_x.* += dx;
                    try self.points.append(self.allocator, Point{
                        .x = current_x.*,
                        .y = current_y.*,
                        .point_type = 0,
                    });
                    self.last_moveto_index = self.points.items.len - 1;
                }
            },
            23 => {
                // vstemhm - 垂直stem提示（hintmask，忽略）
                const stem_count = self.stack.items.len / 2;
                for (0..stem_count) |_| {
                    _ = try self.popStack();
                    _ = try self.popStack();
                }
                const hintmask_size = (stem_count + 7) / 8;
                if (self.offset + hintmask_size > self.charstring_data.len) {
                    return error.InvalidFormat;
                }
                self.offset += hintmask_size;
            },
            24 => {
                // rcurveto - 相对曲线后接直线
                // 格式：dx1 dy1 dx2 dy2 dx3 dy3 dx4 dy4 ... dxn dyn
                // 每6个值是一条曲线，最后2个值是一条直线
                const total_values = self.stack.items.len;
                if (total_values < 8) {
                    return error.InvalidFormat;
                }

                // 处理曲线（每6个值一条曲线）
                var processed: usize = 0;
                while (processed + 6 < total_values - 2) {
                    const dx1 = @as(f32, @floatFromInt(try self.popStack()));
                    const dy1 = @as(f32, @floatFromInt(try self.popStack()));
                    const dx2 = @as(f32, @floatFromInt(try self.popStack()));
                    const dy2 = @as(f32, @floatFromInt(try self.popStack()));
                    const dx3 = @as(f32, @floatFromInt(try self.popStack()));
                    const dy3 = @as(f32, @floatFromInt(try self.popStack()));

                    const cp1_x = current_x.* + dx1;
                    const cp1_y = current_y.* + dy1;
                    try self.points.append(self.allocator, Point{
                        .x = cp1_x,
                        .y = cp1_y,
                        .point_type = 2,
                    });

                    const cp2_x = cp1_x + dx2;
                    const cp2_y = cp1_y + dy2;
                    try self.points.append(self.allocator, Point{
                        .x = cp2_x,
                        .y = cp2_y,
                        .point_type = 3,
                    });

                    current_x.* = cp2_x + dx3;
                    current_y.* = cp2_y + dy3;
                    try self.points.append(self.allocator, Point{
                        .x = current_x.*,
                        .y = current_y.*,
                        .point_type = 0,
                    });

                    processed += 6;
                }

                // 处理最后的直线
                const dx = @as(f32, @floatFromInt(try self.popStack()));
                const dy = @as(f32, @floatFromInt(try self.popStack()));
                current_x.* += dx;
                current_y.* += dy;
                try self.points.append(self.allocator, Point{
                    .x = current_x.*,
                    .y = current_y.*,
                    .point_type = 0,
                });
            },
            25 => {
                // rlinecurve - 相对直线后接曲线
                // 格式：dx1 dy1 ... dxn dyn dxa dya dxb dyb dxc dyc
                // 前面的值对是直线，最后6个值是一条曲线
                const total_values = self.stack.items.len;
                if (total_values < 8) {
                    return error.InvalidFormat;
                }

                // 处理直线（除了最后6个值）
                while (self.stack.items.len > 6) {
                    const dx = @as(f32, @floatFromInt(try self.popStack()));
                    const dy = @as(f32, @floatFromInt(try self.popStack()));
                    current_x.* += dx;
                    current_y.* += dy;
                    try self.points.append(self.allocator, Point{
                        .x = current_x.*,
                        .y = current_y.*,
                        .point_type = 0,
                    });
                }

                // 处理最后的曲线
                const dx1 = @as(f32, @floatFromInt(try self.popStack()));
                const dy1 = @as(f32, @floatFromInt(try self.popStack()));
                const dx2 = @as(f32, @floatFromInt(try self.popStack()));
                const dy2 = @as(f32, @floatFromInt(try self.popStack()));
                const dx3 = @as(f32, @floatFromInt(try self.popStack()));
                const dy3 = @as(f32, @floatFromInt(try self.popStack()));

                const cp1_x = current_x.* + dx1;
                const cp1_y = current_y.* + dy1;
                try self.points.append(self.allocator, Point{
                    .x = cp1_x,
                    .y = cp1_y,
                    .point_type = 2,
                });

                const cp2_x = cp1_x + dx2;
                const cp2_y = cp1_y + dy2;
                try self.points.append(self.allocator, Point{
                    .x = cp2_x,
                    .y = cp2_y,
                    .point_type = 3,
                });

                current_x.* = cp2_x + dx3;
                current_y.* = cp2_y + dy3;
                try self.points.append(self.allocator, Point{
                    .x = current_x.*,
                    .y = current_y.*,
                    .point_type = 0,
                });
            },
            26 => {
                // vvcurveto - 垂直垂直曲线
                // 格式：dy1 dx2 dy2 dx3 dy3 ... 或 dx1 dy1 dx2 dy2 dx3 dy3 ... (如果栈中元素数是奇数)
                const count = self.stack.items.len;
                if (count < 4) {
                    return error.InvalidFormat;
                }

                // 如果元素数是奇数，第一个是dx1（x方向偏移）
                if ((count % 2) == 1) {
                    const dx1 = @as(f32, @floatFromInt(try self.popStack()));
                    current_x.* += dx1;
                }

                // 处理曲线对：dy1 dx2 dy2 dx3 dy3
                while (self.stack.items.len >= 4) {
                    const dy1 = @as(f32, @floatFromInt(try self.popStack()));
                    const dx2 = @as(f32, @floatFromInt(try self.popStack()));
                    const dy2 = @as(f32, @floatFromInt(try self.popStack()));
                    const dx3 = @as(f32, @floatFromInt(try self.popStack()));
                    const dy3 = @as(f32, @floatFromInt(try self.popStack()));

                    const cp1_x = current_x.*;
                    const cp1_y = current_y.* + dy1;
                    try self.points.append(self.allocator, Point{
                        .x = cp1_x,
                        .y = cp1_y,
                        .point_type = 2,
                    });

                    const cp2_x = cp1_x + dx2;
                    const cp2_y = cp1_y + dy2;
                    try self.points.append(self.allocator, Point{
                        .x = cp2_x,
                        .y = cp2_y,
                        .point_type = 3,
                    });

                    current_x.* = cp2_x + dx3;
                    current_y.* = cp2_y + dy3;
                    try self.points.append(self.allocator, Point{
                        .x = current_x.*,
                        .y = current_y.*,
                        .point_type = 0,
                    });
                }
            },
            27 => {
                // hhcurveto - 水平水平曲线
                // 格式：dx1 dy2 dx2 dy3 dx3 ... 或 dy1 dx2 dy2 dx3 dy3 ... (如果栈中元素数是奇数)
                const count = self.stack.items.len;
                if (count < 4) {
                    return error.InvalidFormat;
                }

                // 如果元素数是奇数，第一个是dy1（y方向偏移）
                if ((count % 2) == 1) {
                    const dy1 = @as(f32, @floatFromInt(try self.popStack()));
                    current_y.* += dy1;
                }

                // 处理曲线对：dx1 dy2 dx2 dy3 dx3
                while (self.stack.items.len >= 4) {
                    const dx1 = @as(f32, @floatFromInt(try self.popStack()));
                    const dy2 = @as(f32, @floatFromInt(try self.popStack()));
                    const dx2 = @as(f32, @floatFromInt(try self.popStack()));
                    const dy3 = @as(f32, @floatFromInt(try self.popStack()));
                    const dx3 = @as(f32, @floatFromInt(try self.popStack()));

                    const cp1_x = current_x.* + dx1;
                    const cp1_y = current_y.*;
                    try self.points.append(self.allocator, Point{
                        .x = cp1_x,
                        .y = cp1_y,
                        .point_type = 2,
                    });

                    const cp2_x = cp1_x + dx2;
                    const cp2_y = cp1_y + dy2;
                    try self.points.append(self.allocator, Point{
                        .x = cp2_x,
                        .y = cp2_y,
                        .point_type = 3,
                    });

                    current_x.* = cp2_x + dx3;
                    current_y.* = cp2_y + dy3;
                    try self.points.append(self.allocator, Point{
                        .x = current_x.*,
                        .y = current_y.*,
                        .point_type = 0,
                    });
                }
            },
            28 => {
                // 短整数（已在主循环中处理）
                return error.InvalidFormat;
            },
            29 => {
                // callgsubr - 调用全局子程序（暂不支持）
                // TODO: 实现全局子程序调用
                std.log.warn("[CFF] CharStringDecoder: encountered callgsubr (command 29) at offset {d}, skipping", .{self.offset - 1});
                // 从栈中弹出子程序编号（如果存在）
                if (self.stack.items.len > 0) {
                    _ = self.stack.pop();
                }
                // 不执行子程序调用，这可能导致某些字形无法正确渲染，但至少不会崩溃
            },
            30 => {
                // vhcurveto - 垂直水平曲线
                // 格式：dy1 dx2 dy2 dx3 [dx4 dy5 dx6 dy6 dx7] ... 或 dx1 dy1 dx2 dy2 dx3 ... (如果栈中元素数是奇数)
                const count = self.stack.items.len;
                if (count < 4) {
                    return error.InvalidFormat;
                }

                // 如果元素数是奇数，第一个是dx1（x方向偏移）
                if ((count % 2) == 1) {
                    const dx1 = @as(f32, @floatFromInt(try self.popStack()));
                    current_x.* += dx1;
                }

                // 处理曲线对：dy1 dx2 dy2 dx3
                var is_vertical = true;
                while (self.stack.items.len >= 4) {
                    if (is_vertical) {
                        // 垂直开始：dy1 dx2 dy2 dx3
                        const dy1 = @as(f32, @floatFromInt(try self.popStack()));
                        const dx2 = @as(f32, @floatFromInt(try self.popStack()));
                        const dy2 = @as(f32, @floatFromInt(try self.popStack()));
                        const dx3 = @as(f32, @floatFromInt(try self.popStack()));

                        // 如果还有更多值，可能是下一个曲线的开始
                        const has_next = self.stack.items.len >= 4;
                        const dy3 = if (has_next) @as(f32, 0) else @as(f32, @floatFromInt(try self.popStack()));

                        const cp1_x = current_x.*;
                        const cp1_y = current_y.* + dy1;
                        try self.points.append(self.allocator, Point{
                            .x = cp1_x,
                            .y = cp1_y,
                            .point_type = 2,
                        });

                        const cp2_x = cp1_x + dx2;
                        const cp2_y = cp1_y + dy2;
                        try self.points.append(self.allocator, Point{
                            .x = cp2_x,
                            .y = cp2_y,
                            .point_type = 3,
                        });

                        current_x.* = cp2_x + dx3;
                        current_y.* = cp2_y + (if (has_next) 0 else dy3);
                        try self.points.append(self.allocator, Point{
                            .x = current_x.*,
                            .y = current_y.*,
                            .point_type = 0,
                        });
                    } else {
                        // 水平开始：dx1 dy2 dx2 dy3
                        const dx1 = @as(f32, @floatFromInt(try self.popStack()));
                        const dy2 = @as(f32, @floatFromInt(try self.popStack()));
                        const dx2 = @as(f32, @floatFromInt(try self.popStack()));
                        const dy3 = @as(f32, @floatFromInt(try self.popStack()));

                        const cp1_x = current_x.* + dx1;
                        const cp1_y = current_y.*;
                        try self.points.append(self.allocator, Point{
                            .x = cp1_x,
                            .y = cp1_y,
                            .point_type = 2,
                        });

                        const cp2_x = cp1_x + dx2;
                        const cp2_y = cp1_y + dy2;
                        try self.points.append(self.allocator, Point{
                            .x = cp2_x,
                            .y = cp2_y,
                            .point_type = 3,
                        });

                        current_x.* = cp2_x;
                        current_y.* = cp2_y + dy3;
                        try self.points.append(self.allocator, Point{
                            .x = current_x.*,
                            .y = current_y.*,
                            .point_type = 0,
                        });
                    }
                    is_vertical = !is_vertical;
                }
            },
            31 => {
                // hvcurveto - 水平垂直曲线
                // 格式：dx1 dy2 dx2 dy3 [dy4 dx5 dy5 dx6] ... 或 dy1 dx2 dy2 dx3 ... (如果栈中元素数是奇数)
                const count = self.stack.items.len;
                if (count < 4) {
                    return error.InvalidFormat;
                }

                // 如果元素数是奇数，第一个是dy1（y方向偏移）
                if ((count % 2) == 1) {
                    const dy1 = @as(f32, @floatFromInt(try self.popStack()));
                    current_y.* += dy1;
                }

                // 处理曲线对：dx1 dy2 dx2 dy3
                var is_horizontal = true;
                while (self.stack.items.len >= 4) {
                    if (is_horizontal) {
                        // 水平开始：dx1 dy2 dx2 dy3
                        const dx1 = @as(f32, @floatFromInt(try self.popStack()));
                        const dy2 = @as(f32, @floatFromInt(try self.popStack()));
                        const dx2 = @as(f32, @floatFromInt(try self.popStack()));
                        const dy3 = @as(f32, @floatFromInt(try self.popStack()));

                        // 如果还有更多值，可能是下一个曲线的开始
                        const has_next = self.stack.items.len >= 4;
                        const dx3 = if (has_next) @as(f32, 0) else @as(f32, @floatFromInt(try self.popStack()));

                        const cp1_x = current_x.* + dx1;
                        const cp1_y = current_y.*;
                        try self.points.append(self.allocator, Point{
                            .x = cp1_x,
                            .y = cp1_y,
                            .point_type = 2,
                        });

                        const cp2_x = cp1_x + dx2;
                        const cp2_y = cp1_y + dy2;
                        try self.points.append(self.allocator, Point{
                            .x = cp2_x,
                            .y = cp2_y,
                            .point_type = 3,
                        });

                        current_x.* = cp2_x + (if (has_next) 0 else dx3);
                        current_y.* = cp2_y + dy3;
                        try self.points.append(self.allocator, Point{
                            .x = current_x.*,
                            .y = current_y.*,
                            .point_type = 0,
                        });
                    } else {
                        // 垂直开始：dy1 dx2 dy2 dx3
                        const dy1 = @as(f32, @floatFromInt(try self.popStack()));
                        const dx2 = @as(f32, @floatFromInt(try self.popStack()));
                        const dy2 = @as(f32, @floatFromInt(try self.popStack()));
                        const dx3 = @as(f32, @floatFromInt(try self.popStack()));

                        const cp1_x = current_x.*;
                        const cp1_y = current_y.* + dy1;
                        try self.points.append(self.allocator, Point{
                            .x = cp1_x,
                            .y = cp1_y,
                            .point_type = 2,
                        });

                        const cp2_x = cp1_x + dx2;
                        const cp2_y = cp1_y + dy2;
                        try self.points.append(self.allocator, Point{
                            .x = cp2_x,
                            .y = cp2_y,
                            .point_type = 3,
                        });

                        current_x.* = cp2_x + dx3;
                        current_y.* = cp2_y;
                        try self.points.append(self.allocator, Point{
                            .x = current_x.*,
                            .y = current_y.*,
                            .point_type = 0,
                        });
                    }
                    is_horizontal = !is_horizontal;
                }
            },
            else => {
                // 未知指令，忽略
                std.log.warn("Unknown CharString command: {d}\n", .{command});
            },
        }
    }

    /// 处理转义命令（12.XX）
    fn handleEscapeCommand(self: *Self, escape_byte: u8, _: *f32, _: *f32) !void {
        std.log.warn("[CFF] CharStringDecoder: handleEscapeCommand escape_byte={d}", .{escape_byte});
        switch (escape_byte) {
            0 => {
                // dotsection - 点部分（忽略）
                std.log.warn("[CFF] CharStringDecoder: encountered dotsection (12.0), ignoring", .{});
            },
            23 => {
                // mul - 乘法
                std.log.warn("[CFF] CharStringDecoder: encountered mul (12.23), skipping", .{});
                if (self.stack.items.len >= 2) {
                    const b = try self.popStack();
                    const a = try self.popStack();
                    try self.stack.append(self.allocator, a * b);
                }
            },
            else => {
                std.log.warn("[CFF] CharStringDecoder: unknown escape command 12.{d}, ignoring", .{escape_byte});
                // 未知的转义命令，忽略
            },
        }
    }

    /// 从栈中弹出值
    fn popStack(self: *Self) !i32 {
        if (self.stack.items.len == 0) {
            return error.StackUnderflow;
        }
        const value = self.stack.items[self.stack.items.len - 1];
        _ = self.stack.pop();
        return value;
    }
};
