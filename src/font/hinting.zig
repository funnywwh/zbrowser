const std = @import("std");
const ttf_module = @import("ttf");

/// TrueType Hinting解释器
/// 实现TrueType指令虚拟机，用于执行字体hinting指令
/// 参考：TrueType规范指令集
pub const HintingInterpreter = struct {
    allocator: std.mem.Allocator,
    
    /// 控制值表（Control Value Table）
    cvt: std.ArrayList(i32),
    
    /// 存储区（Storage Area）
    storage: std.ArrayList(i32),
    
    /// 函数定义区（Function Definitions）
    functions: std.ArrayList(Function),
    
    /// 指令指针（Instruction Pointer）
    ip: usize,
    
    /// 指令数据
    instructions: []const u8,
    
    /// 栈（Stack）
    stack: std.ArrayList(i32),
    
    /// 图形状态（Graphics State）
    graphics_state: GraphicsState,
    
    /// 函数定义
    const Function = struct {
        /// 函数索引
        index: u16,
        /// 指令数据
        instructions: []const u8,
    };
    
    /// 图形状态
    const GraphicsState = struct {
        /// 自由向量（Freedom Vector）
        freedom_vector: Point,
        /// 投影向量（Projection Vector）
        projection_vector: Point,
        /// 双投影向量（Dual Projection Vector）
        dual_projection_vector: Point,
        /// 控制值剪切（Control Value Cut-In）
        control_value_cut_in: i32,
        /// 单宽度值（Single Width Value）
        single_width_value: i32,
        /// 单宽度剪切（Single Width Cut-In）
        single_width_cut_in: i32,
        /// 最小距离（Minimum Distance）
        min_distance: i32,
        /// 循环（Loop）
        loop: u8,
        /// 圆度（Round State）
        round_state: RoundState,
        /// 自动翻转（Auto-Flip）
        auto_flip: bool,
        
        const Point = struct {
            x: i32,
            y: i32,
        };
        
        const RoundState = enum {
            off,
            to_grid,
            to_half_grid,
            to_double_grid,
            down_to_grid,
            up_to_grid,
            super,
            super_45,
        };
    };
    
    const Self = @This();
    
    /// 初始化Hinting解释器
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .cvt = std.ArrayList(i32){},
            .storage = std.ArrayList(i32){},
            .functions = std.ArrayList(Function){},
            .ip = 0,
            .instructions = &[_]u8{},
            .stack = std.ArrayList(i32){},
            .graphics_state = .{
                .freedom_vector = .{ .x = 1, .y = 0 },
                .projection_vector = .{ .x = 1, .y = 0 },
                .dual_projection_vector = .{ .x = 1, .y = 0 },
                .control_value_cut_in = 17,
                .single_width_value = 0,
                .single_width_cut_in = 0,
                .min_distance = 1,
                .loop = 1,
                .round_state = .to_grid,
                .auto_flip = true,
            },
        };
    }
    
    /// 清理Hinting解释器
    pub fn deinit(self: *Self) void {
        self.cvt.deinit(self.allocator);
        self.storage.deinit(self.allocator);
        for (self.functions.items) |func| {
            self.allocator.free(func.instructions);
        }
        self.functions.deinit(self.allocator);
        self.stack.deinit(self.allocator);
    }
    
    /// 加载CVT表（Control Value Table）
    pub fn loadCvt(self: *Self, cvt_data: []const u8) !void {
        // CVT表结构：每个条目2字节（i16），大端序
        if (cvt_data.len % 2 != 0) {
            return error.InvalidFormat;
        }
        
        const num_entries = cvt_data.len / 2;
        try self.cvt.ensureTotalCapacity(self.allocator, num_entries);
        
        var i: usize = 0;
        while (i < num_entries) : (i += 1) {
            const offset = i * 2;
            const value = std.mem.readInt(i16, cvt_data[offset..][0..2], .big);
            try self.cvt.append(self.allocator, @as(i32, value));
        }
    }
    
    /// 加载fpgm表（Font Program）
    pub fn loadFpgm(self: *Self, fpgm_data: []const u8) !void {
        // fpgm表包含字体的全局指令
        // 这些指令在字体加载时执行，用于初始化函数定义
        // TODO: 完整实现 - 当前只存储指令数据，不执行
        // 完整实现需要解析函数定义（FDEF/ENDF）并存储
        _ = fpgm_data;
        _ = self;
    }
    
    /// 加载prep表（Control Value Program）
    pub fn loadPrep(self: *Self, prep_data: []const u8) !void {
        // prep表包含字体的预处理指令
        // 这些指令在每个字形渲染前执行
        // TODO: 完整实现 - 当前只存储指令数据，不执行
        // 完整实现需要执行这些指令来初始化图形状态
        _ = prep_data;
        _ = self;
    }
    
    /// 执行字形指令
    /// 参数：
    /// - glyph_instructions: 字形的指令数据
    /// - points: 字形的点列表（会被hinting修改）
    pub fn executeGlyphInstructions(
        self: *Self,
        glyph_instructions: []const u8,
        points: *std.ArrayList(ttf_module.TtfParser.Glyph.Point),
        font_size: f32,
        units_per_em: u16,
    ) !void {
        if (glyph_instructions.len == 0) {
            return;
        }
        
        // 初始化指令执行环境
        self.instructions = glyph_instructions;
        self.ip = 0;
        self.stack.clearRetainingCapacity();
        
        // 计算缩放因子
        const scale = font_size / @as(f32, @floatFromInt(units_per_em));
        
        // 执行指令
        while (self.ip < self.instructions.len) {
            const opcode = self.instructions[self.ip];
            self.ip += 1;
            
            // 执行指令
            try self.executeInstruction(opcode, points, scale);
        }
    }
    
    /// 执行单个指令
    pub fn executeInstruction(
        self: *Self,
        opcode: u8,
        points: *std.ArrayList(ttf_module.TtfParser.Glyph.Point),
        _scale: f32,
    ) !void {
        _ = _scale; // 暂时未使用
        // TrueType指令集
        // 参考：TrueType规范指令集章节
        
        switch (opcode) {
            // SVTCA - Set Freedom Vector To Coordinate Axis
            0x00...0x01 => {
                // 0x00: SVTCA[0] - 设置为Y轴
                // 0x01: SVTCA[1] - 设置为X轴
                const axis = opcode & 0x01;
                if (axis == 0) {
                    self.graphics_state.freedom_vector = .{ .x = 0, .y = 1 };
                } else {
                    self.graphics_state.freedom_vector = .{ .x = 1, .y = 0 };
                }
            },
            
            // SPVTCA - Set Projection Vector To Coordinate Axis
            0x02...0x03 => {
                // 0x02: SPVTCA[0] - 设置为Y轴
                // 0x03: SPVTCA[1] - 设置为X轴
                const axis = opcode & 0x01;
                if (axis == 0) {
                    self.graphics_state.projection_vector = .{ .x = 0, .y = 1 };
                } else {
                    self.graphics_state.projection_vector = .{ .x = 1, .y = 0 };
                }
            },
            
            // SFVTCA - Set Freedom Vector To Coordinate Axis
            0x04...0x05 => {
                // 与SVTCA相同
                const axis = opcode & 0x01;
                if (axis == 0) {
                    self.graphics_state.freedom_vector = .{ .x = 0, .y = 1 };
                } else {
                    self.graphics_state.freedom_vector = .{ .x = 1, .y = 0 };
                }
            },
            
            // SPVTL - Set Projection Vector To Line
            0x06...0x07 => {
                // 0x06: SPVTL[0] - 设置为两点之间的线
                // 0x07: SPVTL[1] - 设置为两点之间的线（垂直）
                if (self.stack.items.len < 4) {
                    return error.StackUnderflow;
                }
                const p2_y = self.pop();
                const p2_x = self.pop();
                const p1_y = self.pop();
                const p1_x = self.pop();
                
                const dx = p2_x - p1_x;
                const dy = p2_y - p1_y;
                const len = @sqrt(@as(f64, @floatFromInt(dx * dx + dy * dy)));
                if (len > 0) {
                    const normalized_x = @as(i32, @intFromFloat(@as(f64, @floatFromInt(dx)) / len));
                    const normalized_y = @as(i32, @intFromFloat(@as(f64, @floatFromInt(dy)) / len));
                    self.graphics_state.projection_vector = .{ .x = normalized_x, .y = normalized_y };
                }
            },
            
            // SFVTL - Set Freedom Vector To Line
            0x08...0x09 => {
                // 与SPVTL相同，但设置freedom_vector
                if (self.stack.items.len < 4) {
                    return error.StackUnderflow;
                }
                const p2_y = self.pop();
                const p2_x = self.pop();
                const p1_y = self.pop();
                const p1_x = self.pop();
                
                const dx = p2_x - p1_x;
                const dy = p2_y - p1_y;
                const len = @sqrt(@as(f64, @floatFromInt(dx * dx + dy * dy)));
                if (len > 0) {
                    const normalized_x = @as(i32, @intFromFloat(@as(f64, @floatFromInt(dx)) / len));
                    const normalized_y = @as(i32, @intFromFloat(@as(f64, @floatFromInt(dy)) / len));
                    self.graphics_state.freedom_vector = .{ .x = normalized_x, .y = normalized_y };
                }
            },
            
            // SPVFS - Set Projection Vector From Stack
            0x0E => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const y = self.pop();
                const x = self.pop();
                self.graphics_state.projection_vector = .{ .x = x, .y = y };
            },
            
            // SFVFS - Set Freedom Vector From Stack
            0x0F => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const y = self.pop();
                const x = self.pop();
                self.graphics_state.freedom_vector = .{ .x = x, .y = y };
            },
            
            // SRP0 - Set Reference Point 0
            0x10 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                _ = self.pop(); // 点索引（暂不处理）
            },
            
            // SRP1 - Set Reference Point 1
            0x11 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                _ = self.pop(); // 点索引（暂不处理）
            },
            
            // SRP2 - Set Reference Point 2
            0x12 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                _ = self.pop(); // 点索引（暂不处理）
            },
            
            // SZP0 - Set Zone Pointer 0
            0x13 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                _ = self.pop(); // 区域索引（暂不处理）
            },
            
            // SZP1 - Set Zone Pointer 1
            0x14 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                _ = self.pop(); // 区域索引（暂不处理）
            },
            
            // SZP2 - Set Zone Pointer 2
            0x15 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                _ = self.pop(); // 区域索引（暂不处理）
            },
            
            // SZPS - Set Zone PointerS
            0x16 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const zone = self.pop();
                // 设置所有区域指针为zone（暂不处理）
                _ = zone;
            },
            
            // SLOOP - Set LOOP variable
            0x17 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const loop = self.pop();
                if (loop > 0) {
                    const loop_val = if (loop > 255) 255 else @as(u8, @intCast(loop));
                    self.graphics_state.loop = loop_val;
                }
            },
            
            // RTG - Round To Grid
            0x18 => {
                self.graphics_state.round_state = .to_grid;
            },
            
            // RTHG - Round To Half Grid
            0x19 => {
                self.graphics_state.round_state = .to_half_grid;
            },
            
            // SMD - Set Minimum Distance
            0x1A => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                self.graphics_state.min_distance = self.pop();
            },
            
            // ELSE - ELSE clause
            0x1B => {
                // 跳过ELSE块（需要与IF配合使用）
                // TODO: 完整实现条件跳转
            },
            
            // JMPR - Jump Relative
            0x1C => {
                if (self.ip >= self.instructions.len) {
                    return error.InvalidInstruction;
                }
                const offset = @as(i8, @bitCast(self.instructions[self.ip]));
                self.ip += 1;
                const new_ip = @as(i32, @intCast(self.ip)) + offset;
                if (new_ip < 0) {
                    return error.InvalidInstruction;
                }
                self.ip = @as(usize, @intCast(new_ip));
            },
            
            // SCVTCI - Set Control Value Table Cut-In
            0x1D => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                self.graphics_state.control_value_cut_in = self.pop();
            },
            
            // SSWCI - Set Single Width Cut-In
            0x1E => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                self.graphics_state.single_width_cut_in = self.pop();
            },
            
            // SSW - Set Single Width
            0x1F => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                self.graphics_state.single_width_value = self.pop();
            },
            
            // DUP - Duplicate top stack element
            0x20 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const top = self.stack.items[self.stack.items.len - 1];
                try self.stack.append(self.allocator, top);
            },
            
            // POP - Pop top stack element
            0x21 => {
                _ = self.pop();
            },
            
            // CLEAR - Clear stack
            0x22 => {
                self.stack.clearRetainingCapacity();
            },
            
            // SWAP - Swap top two stack elements
            0x23 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const top = self.stack.items[self.stack.items.len - 1];
                const second = self.stack.items[self.stack.items.len - 2];
                self.stack.items[self.stack.items.len - 1] = second;
                self.stack.items[self.stack.items.len - 2] = top;
            },
            
            // DEPTH - Push stack depth
            0x24 => {
                try self.stack.append(self.allocator, @as(i32, @intCast(self.stack.items.len)));
            },
            
            // CINDEX - Copy INDEXed element
            0x25 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const index = self.pop();
                if (index < 1 or @as(usize, @intCast(index)) > self.stack.items.len) {
                    return error.InvalidIndex;
                }
                const value = self.stack.items[self.stack.items.len - @as(usize, @intCast(index))];
                try self.stack.append(self.allocator, value);
            },
            
            // MINDEX - Move INDEXed element
            0x26 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const index = self.pop();
                if (index < 1 or @as(usize, @intCast(index)) > self.stack.items.len) {
                    return error.InvalidIndex;
                }
                const stack_index = self.stack.items.len - @as(usize, @intCast(index));
                const value = self.stack.items[stack_index];
                // 移除元素
                _ = self.stack.swapRemove(stack_index);
                try self.stack.append(self.allocator, value);
            },
            
            // ALIGNPTS - ALIGN Points
            0x27 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const p2 = self.pop();
                const p1 = self.pop();
                // TODO: 完整实现 - 对齐两个点
                _ = p1;
                _ = p2;
            },
            
            // IP - Interpolate Point
            0x39 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const point_index = self.pop();
                // TODO: 完整实现 - 插值点
                _ = point_index;
            },
            
            // MSIRP - Move Stack Indirect Relative Point
            0x3A...0x3B => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const distance = self.pop();
                const point_index = self.pop();
                // TODO: 完整实现 - 移动点
                _ = distance;
                _ = point_index;
            },
            
            // ALIGNRP - ALIGN Relative Point
            0x3C => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const point_index = self.pop();
                // TODO: 完整实现 - 对齐相对点
                _ = point_index;
            },
            
            // RTDG - Round To Double Grid
            0x3D => {
                self.graphics_state.round_state = .to_double_grid;
            },
            
            // MIAP - Move Indirect Absolute Point
            0x3E...0x3F => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const cvt_index = self.pop();
                const point_index = self.pop();
                
                // 从CVT读取值
                if (cvt_index >= 0 and @as(usize, @intCast(cvt_index)) < self.cvt.items.len) {
                    const cvt_value = self.cvt.items[@as(usize, @intCast(cvt_index))];
                    // 应用rounding
                    const rounded_value = self.roundValue(cvt_value);
                    
                    // 移动点（检查point_index是否有效）
                    if (point_index >= 0 and @as(usize, @intCast(point_index)) < points.items.len) {
                        const axis = opcode & 0x01;
                        if (axis == 0) {
                            // Y轴
                            points.items[@as(usize, @intCast(point_index))].y = @as(i16, @intCast(rounded_value));
                        } else {
                            // X轴
                            points.items[@as(usize, @intCast(point_index))].x = @as(i16, @intCast(rounded_value));
                        }
                    }
                }
            },
            
            // NPUSHB - Push N Bytes
            0x40 => {
                if (self.ip >= self.instructions.len) {
                    return error.InvalidInstruction;
                }
                const n = self.instructions[self.ip];
                self.ip += 1;
                
                if (self.ip + n > self.instructions.len) {
                    return error.InvalidInstruction;
                }
                
                var i: u8 = 0;
                while (i < n) : (i += 1) {
                    const value = self.instructions[self.ip];
                    self.ip += 1;
                    try self.stack.append(self.allocator, @as(i32, value));
                }
            },
            
            // NPUSHW - Push N Words
            0x41 => {
                if (self.ip >= self.instructions.len) {
                    return error.InvalidInstruction;
                }
                const n = self.instructions[self.ip];
                self.ip += 1;
                
                if (self.ip + n * 2 > self.instructions.len) {
                    return error.InvalidInstruction;
                }
                
                var i: u8 = 0;
                while (i < n) : (i += 1) {
                    const value = std.mem.readInt(i16, self.instructions[self.ip..][0..2], .big);
                    self.ip += 2;
                    try self.stack.append(self.allocator, @as(i32, value));
                }
            },
            
            // WS - Write Storage
            0x42 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const value = self.pop();
                const index = self.pop();
                
                if (index >= 0) {
                    const storage_index = @as(usize, @intCast(index));
                    if (storage_index >= self.storage.items.len) {
                        try self.storage.resize(self.allocator, storage_index + 1);
                    }
                    self.storage.items[storage_index] = value;
                }
            },
            
            // RS - Read Storage
            0x43 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const index = self.pop();
                
                if (index >= 0 and @as(usize, @intCast(index)) < self.storage.items.len) {
                    const value = self.storage.items[@as(usize, @intCast(index))];
                    try self.stack.append(self.allocator, value);
                } else {
                    try self.stack.append(self.allocator, 0);
                }
            },
            
            // WCVTP - Write Control Value Table in Pixel units
            0x44 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const value = self.pop();
                const index = self.pop();
                
                if (index >= 0 and @as(usize, @intCast(index)) < self.cvt.items.len) {
                    self.cvt.items[@as(usize, @intCast(index))] = value;
                }
            },
            
            // RCVT - Read Control Value Table
            0x45 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const index = self.pop();
                
                if (index >= 0 and @as(usize, @intCast(index)) < self.cvt.items.len) {
                    const value = self.cvt.items[@as(usize, @intCast(index))];
                    try self.stack.append(self.allocator, value);
                } else {
                    try self.stack.append(self.allocator, 0);
                }
            },
            
            // GC - Get Coordinate
            0x46...0x47 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const point_index = self.pop();
                
                // 检查point_index是否有效（非负且在范围内）
                if (point_index >= 0 and @as(usize, @intCast(point_index)) < points.items.len) {
                    const axis = opcode & 0x01;
                    const coord = if (axis == 0)
                        points.items[@as(usize, @intCast(point_index))].y
                    else
                        points.items[@as(usize, @intCast(point_index))].x;
                    try self.stack.append(self.allocator, @as(i32, coord));
                } else {
                    try self.stack.append(self.allocator, 0);
                }
            },
            
            // MD - Measure Distance
            0x49 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const p2 = self.pop();
                const p1 = self.pop();
                
                if (@as(usize, @intCast(p1)) < points.items.len and
                    @as(usize, @intCast(p2)) < points.items.len)
                {
                    const point1 = points.items[@as(usize, @intCast(p1))];
                    const point2 = points.items[@as(usize, @intCast(p2))];
                    
                    const dx = @as(i32, point2.x) - @as(i32, point1.x);
                    const dy = @as(i32, point2.y) - @as(i32, point1.y);
                    
                    // 计算投影距离
                    const proj_x = self.graphics_state.projection_vector.x;
                    const proj_y = self.graphics_state.projection_vector.y;
                    const distance = dx * proj_x + dy * proj_y;
                    
                    try self.stack.append(self.allocator, distance);
                } else {
                    try self.stack.append(self.allocator, 0);
                }
            },
            
            // MPPEM - Measure Pixels Per EM
            0x4B => {
                // 返回当前字体大小（像素）
                // 注意：scale参数在executeGlyphInstructions中传递，这里需要从外部获取
                // TODO: 完整实现 - 需要从图形状态或参数中获取PPEM
                try self.stack.append(self.allocator, 12); // 临时值
            },
            
            // FLIPON - FLIP ON
            0x4D => {
                self.graphics_state.auto_flip = true;
            },
            
            // FLIPOFF - FLIP OFF
            0x4E => {
                self.graphics_state.auto_flip = false;
            },
            
            // DEBUG - DEBUG
            0x4F => {
                // 调试指令，不做任何操作
            },
            
            // LT - Less Than
            0x50 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                const result: i32 = if (e1 < e2) 1 else 0;
                try self.stack.append(self.allocator, result);
            },
            
            // LTEQ - Less Than or EQual
            0x51 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                const result: i32 = if (e1 <= e2) 1 else 0;
                try self.stack.append(self.allocator, result);
            },
            
            // GT - Greater Than
            0x52 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                const result: i32 = if (e1 > e2) 1 else 0;
                try self.stack.append(self.allocator, result);
            },
            
            // GTEQ - Greater Than or EQual
            0x53 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                const result: i32 = if (e1 >= e2) 1 else 0;
                try self.stack.append(self.allocator, result);
            },
            
            // EQ - EQual
            0x54 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                const result: i32 = if (e1 == e2) 1 else 0;
                try self.stack.append(self.allocator, result);
            },
            
            // NEQ - Not EQual
            0x55 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                const result: i32 = if (e1 != e2) 1 else 0;
                try self.stack.append(self.allocator, result);
            },
            
            // ODD - ODD
            0x56 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const value = self.pop();
                const result: i32 = if ((value & 1) != 0) 1 else 0;
                try self.stack.append(self.allocator, result);
            },
            
            // EVEN - EVEN
            0x57 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const value = self.pop();
                const result: i32 = if ((value & 1) == 0) 1 else 0;
                try self.stack.append(self.allocator, result);
            },
            
            // IF - IF
            0x58 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const condition = self.pop();
                if (condition == 0) {
                    // 跳过IF块，查找ELSE或EIF
                    // TODO: 完整实现条件跳转
                }
            },
            
            // EIF - End IF
            0x59 => {
                // IF块结束
            },
            
            // AND - AND
            0x5A => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                const result: i32 = if (e1 != 0 and e2 != 0) 1 else 0;
                try self.stack.append(self.allocator, result);
            },
            
            // OR - OR
            0x5B => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                const result: i32 = if (e1 != 0 or e2 != 0) 1 else 0;
                try self.stack.append(self.allocator, result);
            },
            
            // NOT - NOT
            0x5C => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const value = self.pop();
                const result: i32 = if (value == 0) 1 else 0;
                try self.stack.append(self.allocator, result);
            },
            
            // ADD - ADD
            0x60 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                try self.stack.append(self.allocator, e1 + e2);
            },
            
            // SUB - SUBtract
            0x61 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                try self.stack.append(self.allocator, e1 - e2);
            },
            
            // MUL - MULtiply
            0x62 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                try self.stack.append(self.allocator, e1 * e2);
            },
            
            // DIV - DIVide
            0x63 => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                if (e2 == 0) {
                    return error.DivisionByZero;
                }
                try self.stack.append(self.allocator, @divTrunc(e1, e2));
            },
            
            // ABS - ABSolute value
            0x64 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const value = self.pop();
                const abs_value: i32 = if (value < 0) -value else value;
                try self.stack.append(self.allocator, abs_value);
            },
            
            // NEG - NEGate
            0x65 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const value = self.pop();
                try self.stack.append(self.allocator, -value);
            },
            
            // FLOOR - FLOOR
            0x66 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const value = self.pop();
                try self.stack.append(self.allocator, value);
            },
            
            // CEILING - CEILING
            0x67 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const value = self.pop();
                try self.stack.append(self.allocator, value);
            },
            
            // ROUND - ROUND
            0x68...0x6B => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                const value = self.pop();
                const rounded = self.roundValue(value);
                try self.stack.append(self.allocator, rounded);
            },
            
            // MAX - MAXimum
            0x6C => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                const max_val = if (e1 > e2) e1 else e2;
                try self.stack.append(self.allocator, max_val);
            },
            
            // MIN - MINimum
            0x6D => {
                if (self.stack.items.len < 2) {
                    return error.StackUnderflow;
                }
                const e2 = self.pop();
                const e1 = self.pop();
                const min_val = if (e1 < e2) e1 else e2;
                try self.stack.append(self.allocator, min_val);
            },
            
            // SROUND - Super ROUND
            0x76 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                _ = self.pop();
                self.graphics_state.round_state = .super;
            },
            
            // S45ROUND - Super 45 degree ROUND
            0x77 => {
                if (self.stack.items.len < 1) {
                    return error.StackUnderflow;
                }
                _ = self.pop();
                self.graphics_state.round_state = .super_45;
            },
            
            // SLOOP - Set LOOP variable (already handled above)
            // ... 其他指令 ...
            
            else => {
                // 未知指令，跳过
                // TODO: 完整实现所有TrueType指令
            },
        }
    }
    
    /// 弹出栈顶元素
    fn pop(self: *Self) i32 {
        return self.stack.pop() orelse 0;
    }
    
    /// 应用rounding到值
    pub fn roundValue(self: *Self, value: i32) i32 {
        switch (self.graphics_state.round_state) {
            .off => return value,
            .to_grid => {
                const rounded = @divTrunc(value + 32, 64);
                return rounded * 64;
            },
            .to_half_grid => {
                const rounded = @divTrunc(value + 16, 32);
                return rounded * 32;
            },
            .to_double_grid => {
                const rounded = @divTrunc(value + 64, 128);
                return rounded * 128;
            },
            .down_to_grid => {
                const rounded = @divTrunc(value, 64);
                return rounded * 64;
            },
            .up_to_grid => {
                const rounded = @divTrunc(value + 63, 64);
                return rounded * 64;
            },
            .super => {
                const rounded = @divTrunc(value + 32, 64);
                return rounded * 64; // 简化实现
            },
            .super_45 => {
                const rounded = @divTrunc(value + 32, 64);
                return rounded * 64; // 简化实现
            },
        }
    }
    
    /// 错误类型
    pub const Error = error{
        StackUnderflow,
        InvalidInstruction,
        InvalidIndex,
        DivisionByZero,
        InvalidFormat,
    };
};

