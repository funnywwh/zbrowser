const std = @import("std");
const backend = @import("backend");

/// 路径点
const Point = struct {
    x: f32,
    y: f32,
};

/// 变换矩阵（2D）
/// 简化实现：只支持平移、旋转、缩放
const Transform = struct {
    tx: f32 = 0, // 平移X
    ty: f32 = 0, // 平移Y
    sx: f32 = 1, // 缩放X
    sy: f32 = 1, // 缩放Y
    angle: f32 = 0, // 旋转角度（弧度）

    /// 应用变换到点
    fn apply(self: Transform, x: f32, y: f32) struct { x: f32, y: f32 } {
        // 简化实现：只应用平移和缩放
        // TODO: 完整实现需要支持旋转
        return .{
            .x = x * self.sx + self.tx,
            .y = y * self.sy + self.ty,
        };
    }
};

/// 渲染状态
const RenderState = struct {
    transform: Transform,
    clip_rect: ?backend.Rect = null,
    global_alpha: f32 = 1.0,
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

    /// 当前渲染状态
    current_state: RenderState,

    /// 状态栈（用于save/restore）
    state_stack: std.ArrayList(RenderState),

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
            .current_state = RenderState{ .transform = Transform{} },
            .state_stack = std.ArrayList(RenderState){},
        };

        return self;
    }

    /// 清理CPU渲染后端
    pub fn deinit(self: *CpuRenderBackend) void {
        self.current_path.deinit(self.allocator);
        self.state_stack.deinit(self.allocator);
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
        // 应用变换
        const transformed = self.current_state.transform.apply(rect.x, rect.y);
        const transformed_width = rect.width * self.current_state.transform.sx;
        const transformed_height = rect.height * self.current_state.transform.sy;

        // 应用裁剪
        var draw_rect = backend.Rect.init(transformed.x, transformed.y, transformed_width, transformed_height);
        if (self.current_state.clip_rect) |clip| {
            // 计算裁剪后的矩形
            const clip_x = @max(draw_rect.x, clip.x);
            const clip_y = @max(draw_rect.y, clip.y);
            const clip_w = @min(draw_rect.x + draw_rect.width, clip.x + clip.width) - clip_x;
            const clip_h = @min(draw_rect.y + draw_rect.height, clip.y + clip.height) - clip_y;
            if (clip_w <= 0 or clip_h <= 0) {
                return; // 完全在裁剪区域外
            }
            draw_rect = backend.Rect.init(clip_x, clip_y, clip_w, clip_h);
        }

        // 应用全局透明度
        const alpha = @as(f32, @floatFromInt(color.a)) * self.current_state.global_alpha;
        const final_alpha = @as(u8, @intFromFloat(alpha));

        // 计算实际绘制区域（裁剪到画布边界）
        const start_x = @max(0, @as(i32, @intFromFloat(draw_rect.x)));
        const start_y = @max(0, @as(i32, @intFromFloat(draw_rect.y)));
        const end_x = @min(@as(i32, @intCast(self.width)), @as(i32, @intFromFloat(draw_rect.x + draw_rect.width)));
        const end_y = @min(@as(i32, @intCast(self.height)), @as(i32, @intFromFloat(draw_rect.y + draw_rect.height)));

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
                // 简化混合：如果透明度小于255，进行alpha混合
                if (final_alpha < 255) {
                    const src_alpha = @as(f32, @floatFromInt(final_alpha)) / 255.0;
                    const dst_alpha = @as(f32, @floatFromInt(self.pixels[index + 3])) / 255.0;
                    const combined_alpha = src_alpha + dst_alpha * (1 - src_alpha);
                    if (combined_alpha > 0) {
                        const inv_alpha = 1.0 / combined_alpha;
                        self.pixels[index] = @as(u8, @intFromFloat((@as(f32, @floatFromInt(color.r)) * src_alpha + @as(f32, @floatFromInt(self.pixels[index])) * dst_alpha * (1 - src_alpha)) * inv_alpha));
                        self.pixels[index + 1] = @as(u8, @intFromFloat((@as(f32, @floatFromInt(color.g)) * src_alpha + @as(f32, @floatFromInt(self.pixels[index + 1])) * dst_alpha * (1 - src_alpha)) * inv_alpha));
                        self.pixels[index + 2] = @as(u8, @intFromFloat((@as(f32, @floatFromInt(color.b)) * src_alpha + @as(f32, @floatFromInt(self.pixels[index + 2])) * dst_alpha * (1 - src_alpha)) * inv_alpha));
                        self.pixels[index + 3] = @as(u8, @intFromFloat(combined_alpha * 255));
                    }
                } else {
                    self.pixels[index] = color.r;
                    self.pixels[index + 1] = color.g;
                    self.pixels[index + 2] = color.b;
                    self.pixels[index + 3] = final_alpha;
                }
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
    /// 使用Bresenham算法绘制直线
    /// TODO: 完整实现需要：
    /// 1. 处理线宽和线帽（round、square、butt）
    /// 2. 抗锯齿处理
    fn strokePathInternal(self: *CpuRenderBackend, color: backend.Color, width: f32) void {
        if (self.current_path.items.len < 2) {
            return; // 至少需要2个点才能绘制路径
        }

        // 使用Bresenham算法绘制连接各点的直线
        var i: usize = 0;
        while (i < self.current_path.items.len - 1) : (i += 1) {
            const p1 = self.current_path.items[i];
            const p2 = self.current_path.items[i + 1];

            // 使用Bresenham算法绘制直线
            self.drawLineBresenham(p1.x, p1.y, p2.x, p2.y, color, width);
        }
    }

    /// 使用Bresenham算法绘制直线
    /// 参考：Bresenham's line algorithm
    fn drawLineBresenham(self: *CpuRenderBackend, x0: f32, y0: f32, x1: f32, y1: f32, color: backend.Color, width: f32) void {
        const start_x = @as(i32, @intFromFloat(x0));
        const start_y = @as(i32, @intFromFloat(y0));
        const end_x = @as(i32, @intFromFloat(x1));
        const end_y = @as(i32, @intFromFloat(y1));

        const dx: i32 = @intCast(@abs(end_x - start_x));
        const dy: i32 = @intCast(@abs(end_y - start_y));
        const sx: i32 = if (start_x < end_x) 1 else -1;
        const sy: i32 = if (start_y < end_y) 1 else -1;

        var err: i32 = dx - dy;
        var x = start_x;
        var y = start_y;

        // 绘制直线上的每个像素
        while (true) {
            // 绘制当前像素（考虑线宽）
            if (width <= 1.0) {
                // 单像素宽度
                if (x >= 0 and x < @as(i32, @intCast(self.width)) and
                    y >= 0 and y < @as(i32, @intCast(self.height)))
                {
                    const index = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 4;
                    self.pixels[index] = color.r;
                    self.pixels[index + 1] = color.g;
                    self.pixels[index + 2] = color.b;
                    self.pixels[index + 3] = color.a;
                }
            } else {
                // 多像素宽度：绘制一个小矩形
                const rect = backend.Rect.init(@as(f32, @floatFromInt(x)), @as(f32, @floatFromInt(y)), width, width);
                fillRectInternal(self, rect, color);
            }

            // 检查是否到达终点
            if (x == end_x and y == end_y) {
                break;
            }

            const e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x += sx;
            }
            if (e2 < dx) {
                err += dx;
                y += sy;
            }
        }
    }

    fn saveImpl(self_ptr: *backend.RenderBackend) void {
        const self = fromRenderBackend(self_ptr);
        self.state_stack.append(self.allocator, self.current_state) catch {};
    }

    fn restoreImpl(self_ptr: *backend.RenderBackend) void {
        const self = fromRenderBackend(self_ptr);
        if (self.state_stack.items.len > 0) {
            const state = self.state_stack.pop();
            if (state) |s| {
                self.current_state = s;
            }
        }
    }

    fn translateImpl(self_ptr: *backend.RenderBackend, x: f32, y: f32) void {
        const self = fromRenderBackend(self_ptr);
        self.current_state.transform.tx += x;
        self.current_state.transform.ty += y;
    }

    fn rotateImpl(self_ptr: *backend.RenderBackend, angle: f32) void {
        const self = fromRenderBackend(self_ptr);
        // TODO: 简化实现 - 当前只记录角度，不实际应用旋转
        // 完整实现需要：更新变换矩阵以支持旋转
        self.current_state.transform.angle += angle;
    }

    fn scaleImpl(self_ptr: *backend.RenderBackend, x: f32, y: f32) void {
        const self = fromRenderBackend(self_ptr);
        self.current_state.transform.sx *= x;
        self.current_state.transform.sy *= y;
    }

    fn clipImpl(self_ptr: *backend.RenderBackend, rect: backend.Rect) void {
        const self = fromRenderBackend(self_ptr);
        // 应用当前变换到裁剪矩形
        const transformed = self.current_state.transform.apply(rect.x, rect.y);
        const transformed_width = rect.width * self.current_state.transform.sx;
        const transformed_height = rect.height * self.current_state.transform.sy;
        const transformed_rect = backend.Rect.init(transformed.x, transformed.y, transformed_width, transformed_height);

        // 如果已有裁剪区域，取交集
        if (self.current_state.clip_rect) |existing_clip| {
            const clip_x = @max(transformed_rect.x, existing_clip.x);
            const clip_y = @max(transformed_rect.y, existing_clip.y);
            const clip_w = @min(transformed_rect.x + transformed_rect.width, existing_clip.x + existing_clip.width) - clip_x;
            const clip_h = @min(transformed_rect.y + transformed_rect.height, existing_clip.y + existing_clip.height) - clip_y;
            if (clip_w > 0 and clip_h > 0) {
                self.current_state.clip_rect = backend.Rect.init(clip_x, clip_y, clip_w, clip_h);
            } else {
                self.current_state.clip_rect = null; // 裁剪区域为空
            }
        } else {
            self.current_state.clip_rect = transformed_rect;
        }
    }

    fn setGlobalAlphaImpl(self_ptr: *backend.RenderBackend, alpha: f32) void {
        const self = fromRenderBackend(self_ptr);
        self.current_state.global_alpha = @max(0.0, @min(1.0, alpha));
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
