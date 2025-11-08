const std = @import("std");
const backend = @import("backend");

/// 路径点
const Point = struct {
    x: f32,
    y: f32,
};

/// CPU渲染后端（软件光栅化）
/// 使用CPU进行软件光栅化，将绘制命令转换为像素数据
pub const CpuRenderBackend = struct {
    base: backend.RenderBackend,
    width: u32,
    height: u32,
    pixels: []u8, // RGBA格式
    allocator: std.mem.Allocator,

    /// 当前路径（用于路径绘制）
    current_path: std.ArrayList(Point),

    /// 从RenderBackend获取CpuRenderBackend
    fn fromRenderBackend(self_ptr: *backend.RenderBackend) *CpuRenderBackend {
        const base_ptr = @intFromPtr(self_ptr);
        const self_ptr_addr = base_ptr - @offsetOf(CpuRenderBackend, "base");
        return @ptrFromInt(self_ptr_addr);
    }

    /// 从const RenderBackend获取const CpuRenderBackend
    fn fromRenderBackendConst(self_ptr: *const backend.RenderBackend) *const CpuRenderBackend {
        const base_ptr = @intFromPtr(self_ptr);
        const self_ptr_addr = base_ptr - @offsetOf(CpuRenderBackend, "base");
        return @ptrFromInt(self_ptr_addr);
    }

    /// 初始化CPU渲染后端
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !*CpuRenderBackend {
        const self = try allocator.create(CpuRenderBackend);
        errdefer allocator.destroy(self);

        const pixels = try allocator.alloc(u8, width * height * 4);
        errdefer allocator.free(pixels);

        // 初始化为白色背景
        @memset(pixels, 255);

        self.* = .{
            .base = .{
                .vtable = &cpu_vtable,
                .data = @ptrCast(self),
            },
            .width = width,
            .height = height,
            .pixels = pixels,
            .allocator = allocator,
            .current_path = std.ArrayList(Point){},
        };

        return self;
    }

    /// 清理CPU渲染后端
    pub fn deinit(self: *CpuRenderBackend) void {
        self.current_path.deinit(self.allocator);
        self.allocator.free(self.pixels);
        self.allocator.destroy(self);
    }

    /// 获取宽度
    pub fn getWidth(self: *const CpuRenderBackend) u32 {
        return self.width;
    }

    /// 获取高度
    pub fn getHeight(self: *const CpuRenderBackend) u32 {
        return self.height;
    }

    /// 获取像素数据（复制）
    pub fn getPixels(self: *const CpuRenderBackend, allocator: std.mem.Allocator) ![]u8 {
        const result = try allocator.alloc(u8, self.pixels.len);
        @memcpy(result, self.pixels);
        return result;
    }

    /// 填充矩形
    fn fillRectImpl(self_ptr: *backend.RenderBackend, rect: backend.Rect, color: backend.Color) void {
        const self = fromRenderBackend(self_ptr);
        fillRectInternal(self, rect, color);
    }

    /// 内部填充矩形实现
    fn fillRectInternal(self: *CpuRenderBackend, rect: backend.Rect, color: backend.Color) void {
        // 计算实际绘制区域（裁剪到画布边界）
        const start_x = @max(0, @as(i32, @intFromFloat(rect.x)));
        const start_y = @max(0, @as(i32, @intFromFloat(rect.y)));
        const end_x = @min(@as(i32, @intCast(self.width)), @as(i32, @intFromFloat(rect.x + rect.width)));
        const end_y = @min(@as(i32, @intCast(self.height)), @as(i32, @intFromFloat(rect.y + rect.height)));

        // 如果矩形完全在边界外，不绘制
        if (start_x >= end_x or start_y >= end_y) {
            return;
        }

        // 填充像素
        var y = start_y;
        while (y < end_y) : (y += 1) {
            var x = start_x;
            while (x < end_x) : (x += 1) {
                const index = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 4;
                self.pixels[index] = color.r;
                self.pixels[index + 1] = color.g;
                self.pixels[index + 2] = color.b;
                self.pixels[index + 3] = color.a;
            }
        }
    }

    // VTable实现（简化版本，其他方法暂时为空实现）
    const cpu_vtable = backend.RenderBackend.VTable{
        .fillRect = fillRectImpl,
        .strokeRect = strokeRectImpl,
        .fillText = fillTextImpl,
        .drawImage = drawImageImpl,
        .beginPath = beginPathImpl,
        .moveTo = moveToImpl,
        .lineTo = lineToImpl,
        .arc = arcImpl,
        .closePath = closePathImpl,
        .fill = fillImpl,
        .stroke = strokeImpl,
        .save = saveImpl,
        .restore = restoreImpl,
        .translate = translateImpl,
        .rotate = rotateImpl,
        .scale = scaleImpl,
        .clip = clipImpl,
        .setGlobalAlpha = setGlobalAlphaImpl,
        .getPixels = getPixelsImpl,
        .getWidth = getWidthImpl,
        .getHeight = getHeightImpl,
        .deinit = deinitImpl,
    };

    fn strokeRectImpl(self_ptr: *backend.RenderBackend, rect: backend.Rect, color: backend.Color, width: f32) void {
        const self = fromRenderBackend(self_ptr);
        strokeRectInternal(self, rect, color, width);
    }

    /// 内部绘制矩形边框实现
    fn strokeRectInternal(self: *CpuRenderBackend, rect: backend.Rect, color: backend.Color, width: f32) void {
        // 如果宽度为0或负数，不绘制
        if (width <= 0) {
            return;
        }

        const stroke_width = @as(i32, @intFromFloat(width));
        if (stroke_width <= 0) {
            return;
        }

        // 计算实际绘制区域（裁剪到画布边界）
        const start_x = @max(0, @as(i32, @intFromFloat(rect.x)));
        const start_y = @max(0, @as(i32, @intFromFloat(rect.y)));
        const end_x = @min(@as(i32, @intCast(self.width)), @as(i32, @intFromFloat(rect.x + rect.width)));
        const end_y = @min(@as(i32, @intCast(self.height)), @as(i32, @intFromFloat(rect.y + rect.height)));

        // 如果矩形完全在边界外，不绘制
        if (start_x >= end_x or start_y >= end_y) {
            return;
        }

        // 绘制上边框
        const top_y_end = @min(end_y, start_y + stroke_width);
        var y = start_y;
        while (y < top_y_end) : (y += 1) {
            var x = start_x;
            while (x < end_x) : (x += 1) {
                const index = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 4;
                self.pixels[index] = color.r;
                self.pixels[index + 1] = color.g;
                self.pixels[index + 2] = color.b;
                self.pixels[index + 3] = color.a;
            }
        }

        // 绘制下边框
        const bottom_y_start = @max(start_y, end_y - stroke_width);
        y = bottom_y_start;
        while (y < end_y) : (y += 1) {
            var x = start_x;
            while (x < end_x) : (x += 1) {
                const index = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 4;
                self.pixels[index] = color.r;
                self.pixels[index + 1] = color.g;
                self.pixels[index + 2] = color.b;
                self.pixels[index + 3] = color.a;
            }
        }

        // 绘制左边框
        const left_x_end = @min(end_x, start_x + stroke_width);
        y = start_y;
        while (y < end_y) : (y += 1) {
            var x = start_x;
            while (x < left_x_end) : (x += 1) {
                const index = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 4;
                self.pixels[index] = color.r;
                self.pixels[index + 1] = color.g;
                self.pixels[index + 2] = color.b;
                self.pixels[index + 3] = color.a;
            }
        }

        // 绘制右边框
        const right_x_start = @max(start_x, end_x - stroke_width);
        y = start_y;
        while (y < end_y) : (y += 1) {
            var x = right_x_start;
            while (x < end_x) : (x += 1) {
                const index = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 4;
                self.pixels[index] = color.r;
                self.pixels[index + 1] = color.g;
                self.pixels[index + 2] = color.b;
                self.pixels[index + 3] = color.a;
            }
        }
    }

    fn fillTextImpl(self_ptr: *backend.RenderBackend, text: []const u8, x: f32, y: f32, font: backend.Font, color: backend.Color) void {
        const self = fromRenderBackend(self_ptr);
        fillTextInternal(self, text, x, y, font, color);
    }

    /// 内部文本渲染实现
    /// TODO: 简化实现 - 当前使用简单的占位符矩形表示文本
    /// 完整实现需要：
    /// 1. 字体加载和字形渲染
    /// 2. 字符宽度计算（考虑字距、连字等）
    /// 3. 文本换行和对齐
    /// 4. 抗锯齿处理
    fn fillTextInternal(self: *CpuRenderBackend, text: []const u8, x: f32, y: f32, font: backend.Font, color: backend.Color) void {
        // 如果文本为空，不绘制
        if (text.len == 0) {
            return;
        }

        // 简化实现：使用矩形占位符表示文本
        // 估算文本宽度（简化：每个字符宽度为字体大小的0.6倍）
        // TODO: 使用font.family、font.weight、font.style等信息
        const char_width = font.size * 0.6;
        const text_width = char_width * @as(f32, @floatFromInt(text.len));
        const text_height = font.size;

        // 计算文本位置（y是基线位置，需要调整）
        // 简化：假设基线在文本底部
        const text_y = y - text_height;

        // 如果文本完全在边界外，不绘制
        if (x + text_width < 0 or x >= @as(f32, @floatFromInt(self.width)) or
            text_y + text_height < 0 or text_y >= @as(f32, @floatFromInt(self.height)))
        {
            return;
        }

        // 绘制文本占位符矩形
        const text_rect = backend.Rect.init(x, text_y, text_width, text_height);
        fillRectInternal(self, text_rect, color);
    }

    fn drawImageImpl(self_ptr: *backend.RenderBackend, image: *backend.Image, src_rect: backend.Rect, dst_rect: backend.Rect) void {
        _ = self_ptr;
        _ = image;
        _ = src_rect;
        _ = dst_rect;
        // TODO: 实现drawImage
    }

    fn beginPathImpl(self_ptr: *backend.RenderBackend) void {
        const self = fromRenderBackend(self_ptr);
        self.current_path.clearRetainingCapacity();
    }

    fn moveToImpl(self_ptr: *backend.RenderBackend, x: f32, y: f32) void {
        const self = fromRenderBackend(self_ptr);
        self.current_path.append(self.allocator, Point{ .x = x, .y = y }) catch {};
    }

    fn lineToImpl(self_ptr: *backend.RenderBackend, x: f32, y: f32) void {
        const self = fromRenderBackend(self_ptr);
        self.current_path.append(self.allocator, Point{ .x = x, .y = y }) catch {};
    }

    fn arcImpl(self_ptr: *backend.RenderBackend, x: f32, y: f32, radius: f32, start: f32, end: f32) void {
        const self = fromRenderBackend(self_ptr);
        // TODO: 简化实现 - 当前将圆弧近似为直线段
        // 完整实现需要：使用Bresenham算法或参数方程绘制圆弧
        const num_segments = @max(8, @as(i32, @intFromFloat(radius * 2)));
        var i: i32 = 0;
        while (i <= num_segments) : (i += 1) {
            const angle = start + (end - start) * (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_segments)));
            const px = x + radius * @cos(angle);
            const py = y + radius * @sin(angle);
            self.current_path.append(self.allocator, Point{ .x = px, .y = py }) catch {};
        }
    }

    fn closePathImpl(self_ptr: *backend.RenderBackend) void {
        const self = fromRenderBackend(self_ptr);
        // 如果路径有至少2个点，添加第一个点以闭合路径
        if (self.current_path.items.len >= 2) {
            const first_point = self.current_path.items[0];
            self.current_path.append(self.allocator, first_point) catch {};
        }
    }

    fn fillImpl(self_ptr: *backend.RenderBackend, color: backend.Color) void {
        const self = fromRenderBackend(self_ptr);
        fillPathInternal(self, color);
    }

    fn strokeImpl(self_ptr: *backend.RenderBackend, color: backend.Color, width: f32) void {
        const self = fromRenderBackend(self_ptr);
        strokePathInternal(self, color, width);
    }

    /// 内部路径填充实现
    /// TODO: 简化实现 - 当前使用简单的扫描线算法
    /// 完整实现需要：
    /// 1. 更精确的多边形填充算法
    /// 2. 处理自相交路径
    /// 3. 非零规则和奇偶规则
    fn fillPathInternal(self: *CpuRenderBackend, color: backend.Color) void {
        if (self.current_path.items.len < 3) {
            return; // 至少需要3个点才能形成封闭区域
        }

        // 简化实现：使用边界框填充
        // TODO: 实现完整的扫描线填充算法
        var min_x: f32 = self.current_path.items[0].x;
        var min_y: f32 = self.current_path.items[0].y;
        var max_x: f32 = self.current_path.items[0].x;
        var max_y: f32 = self.current_path.items[0].y;

        for (self.current_path.items) |point| {
            min_x = @min(min_x, point.x);
            min_y = @min(min_y, point.y);
            max_x = @max(max_x, point.x);
            max_y = @max(max_y, point.y);
        }

        // 填充边界框（简化实现）
        const rect = backend.Rect.init(min_x, min_y, max_x - min_x, max_y - min_y);
        fillRectInternal(self, rect, color);
    }

    /// 内部路径描边实现
    /// TODO: 简化实现 - 当前使用简单的直线连接
    /// 完整实现需要：
    /// 1. 使用Bresenham算法绘制直线
    /// 2. 处理线宽和线帽
    /// 3. 抗锯齿处理
    fn strokePathInternal(self: *CpuRenderBackend, color: backend.Color, width: f32) void {
        if (self.current_path.items.len < 2) {
            return; // 至少需要2个点才能绘制路径
        }

        // 简化实现：绘制连接各点的直线
        var i: usize = 0;
        while (i < self.current_path.items.len - 1) : (i += 1) {
            const p1 = self.current_path.items[i];
            const p2 = self.current_path.items[i + 1];

            // 绘制直线（简化：使用矩形近似）
            const dx = p2.x - p1.x;
            const dy = p2.y - p1.y;
            const length = @sqrt(dx * dx + dy * dy);

            if (length > 0) {
                // 简化：绘制一个矩形来表示直线
                const rect = backend.Rect.init(p1.x, p1.y, length, width);
                fillRectInternal(self, rect, color);
            }
        }
    }

    fn saveImpl(self_ptr: *backend.RenderBackend) void {
        _ = self_ptr;
        // TODO: 实现save
    }

    fn restoreImpl(self_ptr: *backend.RenderBackend) void {
        _ = self_ptr;
        // TODO: 实现restore
    }

    fn translateImpl(self_ptr: *backend.RenderBackend, x: f32, y: f32) void {
        _ = self_ptr;
        _ = x;
        _ = y;
        // TODO: 实现translate
    }

    fn rotateImpl(self_ptr: *backend.RenderBackend, angle: f32) void {
        _ = self_ptr;
        _ = angle;
        // TODO: 实现rotate
    }

    fn scaleImpl(self_ptr: *backend.RenderBackend, x: f32, y: f32) void {
        _ = self_ptr;
        _ = x;
        _ = y;
        // TODO: 实现scale
    }

    fn clipImpl(self_ptr: *backend.RenderBackend, rect: backend.Rect) void {
        _ = self_ptr;
        _ = rect;
        // TODO: 实现clip
    }

    fn setGlobalAlphaImpl(self_ptr: *backend.RenderBackend, alpha: f32) void {
        _ = self_ptr;
        _ = alpha;
        // TODO: 实现setGlobalAlpha
    }

    fn getPixelsImpl(self_ptr: *backend.RenderBackend, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        const self = fromRenderBackend(self_ptr);
        return self.getPixels(allocator);
    }

    fn getWidthImpl(self_ptr: *const backend.RenderBackend) u32 {
        const self = fromRenderBackendConst(self_ptr);
        return self.getWidth();
    }

    fn getHeightImpl(self_ptr: *const backend.RenderBackend) u32 {
        const self = fromRenderBackendConst(self_ptr);
        return self.getHeight();
    }

    fn deinitImpl(self_ptr: *backend.RenderBackend) void {
        const self = fromRenderBackend(self_ptr);
        self.deinit();
    }
};
