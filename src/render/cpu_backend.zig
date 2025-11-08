const std = @import("std");
const backend = @import("backend");

/// CPU渲染后端（软件光栅化）
/// 使用CPU进行软件光栅化，将绘制命令转换为像素数据
pub const CpuRenderBackend = struct {
    base: backend.RenderBackend,
    width: u32,
    height: u32,
    pixels: []u8, // RGBA格式
    allocator: std.mem.Allocator,

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
        };

        return self;
    }

    /// 清理CPU渲染后端
    pub fn deinit(self: *CpuRenderBackend) void {
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
        _ = font; // TODO: 使用字体信息

        // 如果文本为空，不绘制
        if (text.len == 0) {
            return;
        }

        // 简化实现：使用矩形占位符表示文本
        // 估算文本宽度（简化：每个字符宽度为字体大小的0.6倍）
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
        _ = self_ptr;
        // TODO: 实现beginPath
    }

    fn moveToImpl(self_ptr: *backend.RenderBackend, x: f32, y: f32) void {
        _ = self_ptr;
        _ = x;
        _ = y;
        // TODO: 实现moveTo
    }

    fn lineToImpl(self_ptr: *backend.RenderBackend, x: f32, y: f32) void {
        _ = self_ptr;
        _ = x;
        _ = y;
        // TODO: 实现lineTo
    }

    fn arcImpl(self_ptr: *backend.RenderBackend, x: f32, y: f32, radius: f32, start: f32, end: f32) void {
        _ = self_ptr;
        _ = x;
        _ = y;
        _ = radius;
        _ = start;
        _ = end;
        // TODO: 实现arc
    }

    fn closePathImpl(self_ptr: *backend.RenderBackend) void {
        _ = self_ptr;
        // TODO: 实现closePath
    }

    fn fillImpl(self_ptr: *backend.RenderBackend, color: backend.Color) void {
        _ = self_ptr;
        _ = color;
        // TODO: 实现fill
    }

    fn strokeImpl(self_ptr: *backend.RenderBackend, color: backend.Color, width: f32) void {
        _ = self_ptr;
        _ = color;
        _ = width;
        // TODO: 实现stroke
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
