const std = @import("std");
const backend = @import("backend");
const font_module = @import("font");
const glyph_module = @import("glyph");
const math = std.math;
const log = std.log;

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
    /// 使用2D变换矩阵：先缩放，再旋转，最后平移
    /// 变换矩阵：[sx*cos(angle)  -sy*sin(angle)  tx]
    ///          [sx*sin(angle)   sy*cos(angle)   ty]
    ///          [0               0               1]
    fn apply(self: Transform, x: f32, y: f32) struct { x: f32, y: f32 } {
        // 如果角度为0，可以优化（只应用缩放和平移）
        if (self.angle == 0.0) {
            return .{
                .x = x * self.sx + self.tx,
                .y = y * self.sy + self.ty,
            };
        }

        // 应用完整的变换矩阵（缩放 + 旋转 + 平移）
        const cos_a = @cos(self.angle);
        const sin_a = @sin(self.angle);

        // 先应用缩放
        const scaled_x = x * self.sx;
        const scaled_y = y * self.sy;

        // 然后应用旋转
        const rotated_x = scaled_x * cos_a - scaled_y * sin_a;
        const rotated_y = scaled_x * sin_a + scaled_y * cos_a;

        // 最后应用平移
        return .{
            .x = rotated_x + self.tx,
            .y = rotated_y + self.ty,
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

    /// 字体管理器（用于加载和管理字体）
    font_manager: font_module.FontManager,

    /// 字形渲染器（用于渲染字形）
    glyph_renderer: glyph_module.GlyphRenderer,

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
            .font_manager = font_module.FontManager.init(allocator),
            .glyph_renderer = glyph_module.GlyphRenderer.init(allocator),
        };

        return self;
    }

    /// 清理CPU渲染后端
    pub fn deinit(self: *CpuRenderBackend) void {
        self.current_path.deinit(self.allocator);
        self.state_stack.deinit(self.allocator);
        self.font_manager.deinit();
        self.glyph_renderer.deinit();
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
        log.debug("fillRect: x={d:.1}, y={d:.1}, w={d:.1}, h={d:.1}, color=#{x:0>2}{x:0>2}{x:0>2}\n", .{
            rect.x,  rect.y,  rect.width, rect.height,
            color.r, color.g, color.b,
        });
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
        .strokeDashedRect = strokeDashedRectImpl,
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
        log.debug("strokeRect: x={d:.1}, y={d:.1}, w={d:.1}, h={d:.1}, width={d:.1}, color=#{x:0>2}{x:0>2}{x:0>2}\n", .{
            rect.x,  rect.y,  rect.width, rect.height, width,
            color.r, color.g, color.b,
        });
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
        var pixels_drawn: usize = 0;
        var y = start_y;
        while (y < top_y_end) : (y += 1) {
            var x = start_x;
            while (x < end_x) : (x += 1) {
                const index = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 4;
                self.pixels[index] = color.r;
                self.pixels[index + 1] = color.g;
                self.pixels[index + 2] = color.b;
                self.pixels[index + 3] = color.a;
                pixels_drawn += 1;
            }
        }
        log.debug("strokeRectInternal: drew top border, pixels_drawn={d}", .{pixels_drawn});

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

    /// 绘制虚线矩形边框
    fn strokeDashedRectImpl(self_ptr: *backend.RenderBackend, rect: backend.Rect, color: backend.Color, width: f32) void {
        const self = fromRenderBackend(self_ptr);
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

        // 虚线模式：每段长度约为边框宽度的3倍，间隔为边框宽度的2倍
        const dash_length = @max(3, stroke_width * 3);
        const gap_length = @max(2, stroke_width * 2);

        // 声明y变量（用于所有边框绘制）
        var y: i32 = 0;
        var dash_pos: i32 = 0;

        // 绘制上边框（虚线）
        const top_y_end = @min(end_y, start_y + stroke_width);
        y = start_y;
        while (y < top_y_end) : (y += 1) {
            var x = start_x;
            dash_pos = 0;
            while (x < end_x) {
                if (dash_pos < dash_length) {
                    // 绘制虚线段
                    const index = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 4;
                    self.pixels[index] = color.r;
                    self.pixels[index + 1] = color.g;
                    self.pixels[index + 2] = color.b;
                    self.pixels[index + 3] = color.a;
                    x += 1;
                    dash_pos += 1;
                } else {
                    // 跳过间隔
                    x += gap_length;
                    dash_pos = 0;
                }
            }
        }

        // 绘制下边框（虚线）
        const bottom_y_start = @max(start_y, end_y - stroke_width);
        y = bottom_y_start;
        while (y < end_y) : (y += 1) {
            var x = start_x;
            dash_pos = 0;
            while (x < end_x) {
                if (dash_pos < dash_length) {
                    // 绘制虚线段
                    const index = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 4;
                    self.pixels[index] = color.r;
                    self.pixels[index + 1] = color.g;
                    self.pixels[index + 2] = color.b;
                    self.pixels[index + 3] = color.a;
                    x += 1;
                    dash_pos += 1;
                } else {
                    // 跳过间隔
                    x += gap_length;
                    dash_pos = 0;
                }
            }
        }

        // 绘制左边框（虚线）- 沿着y方向绘制
        const left_x_end = @min(end_x, start_x + stroke_width);
        y = start_y;
        dash_pos = 0;
        while (y < end_y) {
            if (dash_pos < dash_length) {
                // 绘制虚线段（在当前y坐标，绘制整个边框宽度）
                var x = start_x;
                while (x < left_x_end) : (x += 1) {
                    const index = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 4;
                    self.pixels[index] = color.r;
                    self.pixels[index + 1] = color.g;
                    self.pixels[index + 2] = color.b;
                    self.pixels[index + 3] = color.a;
                }
                y += 1;
                dash_pos += 1;
            } else {
                // 跳过间隔
                y += gap_length;
                dash_pos = 0;
            }
        }

        // 绘制右边框（虚线）- 沿着y方向绘制
        const right_x_start = @max(start_x, end_x - stroke_width);
        y = start_y; // 重用之前声明的y变量
        dash_pos = 0;
        while (y < end_y) {
            if (dash_pos < dash_length) {
                // 绘制虚线段（在当前y坐标，绘制整个边框宽度）
                var x = right_x_start;
                while (x < end_x) : (x += 1) {
                    const index = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 4;
                    self.pixels[index] = color.r;
                    self.pixels[index + 1] = color.g;
                    self.pixels[index + 2] = color.b;
                    self.pixels[index + 3] = color.a;
                }
                y += 1;
                dash_pos += 1;
            } else {
                // 跳过间隔
                y += gap_length;
                dash_pos = 0;
            }
        }
    }

    fn fillTextImpl(self_ptr: *backend.RenderBackend, text: []const u8, x: f32, y: f32, font: backend.Font, color: backend.Color, letter_spacing: ?f32) void {
        const self = fromRenderBackend(self_ptr);
        log.debug("fillText: text=\"{s}\", x={d:.1}, y={d:.1}, font_size={d:.1}, color=#{x:0>2}{x:0>2}{x:0>2}, letter_spacing={?}\n", .{
            text,    x,       y,       font.size,
            color.r, color.g, color.b, letter_spacing,
        });
        fillTextInternal(self, text, x, y, font, color, letter_spacing);
    }

    /// 计算文本的实际渲染宽度（不渲染，只计算）
    /// 返回文本的结束x坐标
    pub fn calculateTextWidth(self: *CpuRenderBackend, text: []const u8, x: f32, font: backend.Font) !f32 {
        if (text.len == 0) {
            return x;
        }

        // 检测文本中是否包含CJK字符
        const cjk_language = self.detectCJKLanguage(text);

        // 获取字体
        var font_face: ?*font_module.FontFace = null;

        if (cjk_language == 3) {
            // 韩文
            font_face = self.font_manager.getFont("KoreanFont");
            if (font_face == null) {
                font_face = self.tryLoadKoreanFont() catch null;
            }
            const chinese_font_face = self.font_manager.getFont("ChineseFont") orelse self.tryLoadChineseFont() catch null;
            return self.calculateTextWidthWithMixedFonts(font_face, chinese_font_face, text, x, font.size);
        } else if (cjk_language == 2) {
            // 日文
            font_face = self.font_manager.getFont("JapaneseFont");
            if (font_face == null) {
                font_face = self.tryLoadJapaneseFont() catch null;
            }
            if (font_face == null) {
                font_face = self.font_manager.getFont("ChineseFont");
                if (font_face == null) {
                    font_face = self.tryLoadChineseFont() catch null;
                }
            }
        } else if (cjk_language == 1) {
            // 中文
            font_face = self.font_manager.getFont("ChineseFont");
            if (font_face == null) {
                font_face = self.tryLoadChineseFont() catch null;
            }
        }

        if (font_face == null) {
            font_face = self.font_manager.getFont(font.family);
            if (font_face == null) {
                font_face = self.tryLoadDefaultFont(font.family) catch null;
            }
        }

        if (font_face) |face| {
            return self.calculateTextWidthWithFont(face, text, x, font.size);
        } else {
            // 如果没有字体，使用估算值
            const char_width = font.size * 0.7;
            return x + char_width * @as(f32, @floatFromInt(text.len));
        }
    }

    /// 使用字体计算文本宽度
    fn calculateTextWidthWithFont(
        self: *CpuRenderBackend,
        font_face: *font_module.FontFace,
        text: []const u8,
        x: f32,
        font_size: f32,
    ) !f32 {
        const font_metrics = try font_face.getFontMetrics();
        const units_per_em = font_metrics.units_per_em;
        const scale = font_size / @as(f32, @floatFromInt(units_per_em));

        var current_x = x;
        var i: usize = 0;
        while (i < text.len) {
            const decode_result = self.decodeUtf8Codepoint(text[i..]) catch {
                i += 1;
                continue;
            };
            const codepoint = decode_result.codepoint;
            i += decode_result.bytes_consumed;

            const glyph_index_opt = try font_face.getGlyphIndex(codepoint);
            if (glyph_index_opt) |glyph_index| {
                const h_metrics = try font_face.getHorizontalMetrics(glyph_index);
                const advance_width = @as(f32, @floatFromInt(h_metrics.advance_width));
                // 对于CJK字符，如果advance_width明显大于字体大小，则缩小到字体大小的0.95倍
                const is_cjk = (codepoint >= 0x4E00 and codepoint <= 0x9FFF) or // 中文
                    (codepoint >= 0x3040 and codepoint <= 0x309F) or // 日文平假名
                    (codepoint >= 0x30A0 and codepoint <= 0x30FF) or // 日文片假名
                    (codepoint >= 0xAC00 and codepoint <= 0xD7AF); // 韩文
                const adjusted_advance = if (is_cjk and advance_width * scale > font_size * 1.1)
                    font_size * 0.95
                else
                    advance_width * scale;
                current_x += adjusted_advance;
            } else {
                const placeholder_width = font_size * 0.6;
                current_x += placeholder_width;
            }
        }
        return current_x;
    }

    /// 使用混合字体计算文本宽度
    fn calculateTextWidthWithMixedFonts(
        self: *CpuRenderBackend,
        primary_font: ?*font_module.FontFace,
        fallback_font: ?*font_module.FontFace,
        text: []const u8,
        x: f32,
        font_size: f32,
    ) !f32 {
        if (primary_font == null) {
            if (fallback_font) |fallback| {
                return self.calculateTextWidthWithFont(fallback, text, x, font_size);
            } else {
                const char_width = font_size * 0.7;
                return x + char_width * @as(f32, @floatFromInt(text.len));
            }
        }

        const font_face = primary_font.?;
        const font_metrics = try font_face.getFontMetrics();
        const units_per_em = font_metrics.units_per_em;
        const scale = font_size / @as(f32, @floatFromInt(units_per_em));

        var current_x = x;
        var i: usize = 0;
        while (i < text.len) {
            const decode_result = self.decodeUtf8Codepoint(text[i..]) catch {
                i += 1;
                continue;
            };
            const codepoint = decode_result.codepoint;
            i += decode_result.bytes_consumed;

            const glyph_index_opt = try font_face.getGlyphIndex(codepoint);
            if (glyph_index_opt) |glyph_index| {
                const h_metrics = try font_face.getHorizontalMetrics(glyph_index);
                const advance_width = @as(f32, @floatFromInt(h_metrics.advance_width));
                // 对于CJK字符，如果advance_width明显大于字体大小，则缩小到字体大小的0.95倍
                const is_cjk = (codepoint >= 0x4E00 and codepoint <= 0x9FFF) or // 中文
                    (codepoint >= 0x3040 and codepoint <= 0x309F) or // 日文平假名
                    (codepoint >= 0x30A0 and codepoint <= 0x30FF) or // 日文片假名
                    (codepoint >= 0xAC00 and codepoint <= 0xD7AF); // 韩文
                const adjusted_advance = if (is_cjk and advance_width * scale > font_size * 1.1)
                    font_size * 0.95
                else
                    advance_width * scale;
                current_x += adjusted_advance;
            } else {
                // 主字体不支持，尝试备用字体
                if (fallback_font) |fallback| {
                    const fallback_glyph_index_opt = try fallback.getGlyphIndex(codepoint);
                    if (fallback_glyph_index_opt) |fallback_glyph_index| {
                        const fallback_metrics = try fallback.getFontMetrics();
                        const fallback_scale = font_size / @as(f32, @floatFromInt(fallback_metrics.units_per_em));
                        const h_metrics = try fallback.getHorizontalMetrics(fallback_glyph_index);
                        const advance_width = @as(f32, @floatFromInt(h_metrics.advance_width));
                        // 对于CJK字符，如果advance_width明显大于字体大小，则缩小到字体大小的0.95倍
                        const is_cjk = (codepoint >= 0x4E00 and codepoint <= 0x9FFF) or // 中文
                            (codepoint >= 0x3040 and codepoint <= 0x309F) or // 日文平假名
                            (codepoint >= 0x30A0 and codepoint <= 0x30FF) or // 日文片假名
                            (codepoint >= 0xAC00 and codepoint <= 0xD7AF); // 韩文
                        const adjusted_advance = if (is_cjk and advance_width * fallback_scale > font_size * 1.1)
                            font_size * 0.95
                        else
                            advance_width * fallback_scale;
                        current_x += adjusted_advance;
                        continue;
                    }
                }
                // 如果备用字体也不支持，使用占位符宽度
                const placeholder_width = font_size * 0.6;
                current_x += placeholder_width;
            }
        }
        return current_x;
    }

    /// 检测文本中是否包含CJK字符（中文、日文、韩文）
    /// 返回：语言类型（0=无，1=中文，2=日文，3=韩文）
    fn detectCJKLanguage(self: *CpuRenderBackend, text: []const u8) u8 {
        _ = self;
        var i: usize = 0;
        var has_chinese: bool = false;
        var has_japanese_kana: bool = false; // 日文假名（平假名、片假名）
        var has_korean: bool = false;
        var japanese_kana_count: usize = 0;
        var chinese_han_count: usize = 0;
        var korean_count: usize = 0;

        while (i < text.len) {
            // 检查是否是多字节UTF-8字符
            if (i + 2 < text.len) {
                const b1 = text[i];
                const b2 = text[i + 1];
                const b3 = text[i + 2];

                // 3字节UTF-8字符（CJK字符通常是3字节）
                if ((b1 & 0xF0) == 0xE0) {
                    const codepoint = (@as(u21, b1 & 0x0F) << 12) | (@as(u21, b2 & 0x3F) << 6) | (@as(u21, b3 & 0x3F));

                    // 日文平假名：0x3040-0x309F
                    // 日文片假名：0x30A0-0x30FF
                    if ((codepoint >= 0x3040 and codepoint <= 0x309F) or
                        (codepoint >= 0x30A0 and codepoint <= 0x30FF))
                    {
                        has_japanese_kana = true;
                        japanese_kana_count += 1;
                    }
                    // 中文汉字（简体+繁体）：0x4E00-0x9FFF
                    // 注意：这个范围也包含日文汉字，但如果没有日文假名，优先判断为中文
                    if (codepoint >= 0x4E00 and codepoint <= 0x9FFF) {
                        has_chinese = true;
                        chinese_han_count += 1;
                    }
                    // 韩文音节：0xAC00-0xD7A3
                    if (codepoint >= 0xAC00 and codepoint <= 0xD7A3) {
                        has_korean = true;
                        korean_count += 1;
                        log.debug("detectCJKLanguage: found Korean character U+{X:0>4}, korean_count={d}\n", .{ codepoint, korean_count });
                    }
                    i += 3;
                    continue;
                }
            }

            // 检查2字节UTF-8字符（韩文字母）
            if (i + 1 < text.len) {
                const b1 = text[i];
                const b2 = text[i + 1];

                // 2字节UTF-8字符
                if ((b1 & 0xE0) == 0xC0) {
                    const codepoint = (@as(u21, b1 & 0x1F) << 6) | (@as(u21, b2 & 0x3F));
                    // 韩文字母：0x1100-0x11FF
                    if (codepoint >= 0x1100 and codepoint <= 0x11FF) {
                        has_korean = true;
                    }
                    i += 2;
                    continue;
                }
            }

            i += 1;
        }

        // 返回优先级：韩文 > 日文（有假名）> 中文
        // 如果同时有中文汉字和日文假名，优先判断为日文
        if (has_korean) {
            log.debug("detectCJKLanguage: detected Korean (has_korean=true, korean_count={d}, has_chinese={}, has_japanese_kana={})\n", .{ korean_count, has_chinese, has_japanese_kana });
            return 3;
        }
        if (has_japanese_kana) {
            log.debug("detectCJKLanguage: detected Japanese (has_japanese_kana=true, has_chinese={})\n", .{has_chinese});
            return 2; // 有日文假名，判断为日文
        }
        if (has_chinese) {
            log.debug("detectCJKLanguage: detected Chinese (has_chinese=true, has_korean={}, has_japanese_kana={})\n", .{ has_korean, has_japanese_kana });
            return 1; // 只有中文汉字，判断为中文
        }
        return 0;
    }

    /// 内部文本渲染实现
    /// 尝试使用字体模块渲染真正的文本，如果失败则回退到占位符
    /// TODO: 完整实现需要：
    /// 1. 字符宽度计算（考虑字距、连字等）
    /// 2. 文本换行和对齐
    /// 3. 抗锯齿处理
    fn fillTextInternal(self: *CpuRenderBackend, text: []const u8, x: f32, y: f32, font: backend.Font, color: backend.Color, letter_spacing: ?f32) void {
        // 如果文本为空，不绘制
        if (text.len == 0) {
            return;
        }

        // 检测文本中是否包含CJK字符（中文、日文、韩文）
        const cjk_language = self.detectCJKLanguage(text);

        // 尝试使用字体模块渲染文本
        var font_face: ?*font_module.FontFace = null;

        // 根据检测到的语言类型，优先尝试加载相应的字体
        if (cjk_language == 3) {
            // 韩文：优先尝试加载韩文字体
            // 注意：如果文本中同时包含中文汉字和韩文字符，使用韩文字体
            // 如果韩文字体不支持某些中文汉字，这些汉字可能无法显示
            log.debug("fillTextInternal: detected Korean, attempting to load Korean font\n", .{});
            font_face = self.font_manager.getFont("KoreanFont");
            if (font_face == null) {
                font_face = self.tryLoadKoreanFont() catch null;
            }
            // 如果韩文字体加载失败，回退到中文字体（因为中文字体通常也支持韩文）
            if (font_face == null) {
                log.debug("fillTextInternal: Korean font failed, falling back to Chinese font\n", .{});
                font_face = self.font_manager.getFont("ChineseFont");
                if (font_face == null) {
                    font_face = self.tryLoadChineseFont() catch null;
                }
            }

            // 尝试使用韩文字体渲染，如果某些字符找不到字形，按字符分别处理
            if (font_face) |face| {
                // 获取中文字体作为备用（用于渲染中文汉字）
                const chinese_font_face = self.font_manager.getFont("ChineseFont") orelse self.tryLoadChineseFont() catch null;

                // 按字符分别渲染，对每个字符使用合适的字体
                self.renderTextWithMixedFonts(face, chinese_font_face, text, x, y, font.size, color, letter_spacing) catch |err| {
                    // 如果渲染失败，使用占位符
                    log.debug("fillTextInternal: renderTextWithMixedFonts failed: {}, using placeholder\n", .{err});
                    self.renderTextPlaceholder(text, x, y, font, color);
                };
                return;
            }
        } else if (cjk_language == 2) {
            // 日文：优先尝试加载日文字体，如果失败则回退到中文字体（因为中文字体通常也支持日文汉字）
            log.debug("fillTextInternal: detected Japanese, attempting to load Japanese font\n", .{});
            font_face = self.font_manager.getFont("JapaneseFont");
            if (font_face == null) {
                font_face = self.tryLoadJapaneseFont() catch null;
            }
            // 如果日文字体加载失败，回退到中文字体
            if (font_face == null) {
                log.debug("fillTextInternal: Japanese font failed, falling back to Chinese font\n", .{});
                font_face = self.font_manager.getFont("ChineseFont");
                if (font_face == null) {
                    font_face = self.tryLoadChineseFont() catch null;
                }
            }
        } else if (cjk_language == 1) {
            // 中文：优先尝试加载中文字体
            log.debug("fillTextInternal: detected Chinese, attempting to load Chinese font\n", .{});
            font_face = self.font_manager.getFont("ChineseFont");
            if (font_face == null) {
                font_face = self.tryLoadChineseFont() catch null;
            }
        }

        // 如果特定语言字体加载失败，或者不包含CJK字符，尝试加载默认字体
        if (font_face == null) {
            font_face = self.font_manager.getFont(font.family);
            if (font_face == null) {
                font_face = self.tryLoadDefaultFont(font.family) catch null;
            }
        }

        if (font_face) |face| {
            // 字体已加载，使用真正的字形渲染，支持字体回退
            // 构建字体回退列表：主字体 + 其他已加载的字体
            var fallback_fonts = std.ArrayList(*font_module.FontFace){};
            defer fallback_fonts.deinit(self.allocator);

            fallback_fonts.append(self.allocator, face) catch {};

            // 添加其他已加载的字体作为回退
            if (self.font_manager.getFont("ChineseFont")) |chinese_font| {
                if (chinese_font != face) {
                    fallback_fonts.append(self.allocator, chinese_font) catch {};
                }
            }
            if (self.font_manager.getFont("JapaneseFont")) |japanese_font| {
                if (japanese_font != face) {
                    fallback_fonts.append(self.allocator, japanese_font) catch {};
                }
            }
            if (self.font_manager.getFont("KoreanFont")) |korean_font| {
                if (korean_font != face) {
                    fallback_fonts.append(self.allocator, korean_font) catch {};
                }
            }
            // 尝试预加载支持Unicode符号的字体（如果尚未加载）
            if (self.font_manager.getFont("SymbolFont")) |symbol_font| {
                if (symbol_font != face) {
                    fallback_fonts.append(self.allocator, symbol_font) catch {};
                }
            } else {
                // 尝试加载Segoe UI Symbol
                _ = self.tryLoadSymbolFont() catch null;
                if (self.font_manager.getFont("SymbolFont")) |symbol_font| {
                    if (symbol_font != face) {
                        fallback_fonts.append(self.allocator, symbol_font) catch {};
                    }
                }
            }
            if (self.font_manager.getFont("EmojiFont")) |emoji_font| {
                if (emoji_font != face) {
                    fallback_fonts.append(self.allocator, emoji_font) catch {};
                }
            } else {
                // 尝试加载Segoe UI Emoji
                _ = self.tryLoadEmojiFont() catch null;
                if (self.font_manager.getFont("EmojiFont")) |emoji_font| {
                    if (emoji_font != face) {
                        fallback_fonts.append(self.allocator, emoji_font) catch {};
                    }
                }
            }

            // 使用字体回退机制渲染文本
            self.renderTextWithFontFallback(fallback_fonts.items, text, x, y, font.size, color, letter_spacing) catch |err| {
                // 如果所有字体都失败，回退到占位符
                log.debug("fillTextInternal: all fonts failed: {}, falling back to placeholder\n", .{err});
                self.renderTextPlaceholder(text, x, y, font, color);
            };
        } else {
            // 字体未加载，使用占位符
            self.renderTextPlaceholder(text, x, y, font, color);
        }
    }

    /// 尝试加载中文字体
    /// 通用字体加载函数：遍历字体路径数组，尝试加载字体
    /// 参数：
    /// - font_paths: 字体路径数组
    /// - font_name: 字体名称（用于缓存）
    /// - log_prefix: 日志前缀（用于区分不同的字体类型）
    /// 返回：成功加载的字体面，如果所有路径都失败则返回null
    fn tryLoadFontFromPaths(
        self: *CpuRenderBackend,
        font_paths: []const []const u8,
        font_name: []const u8,
        log_prefix: []const u8,
    ) !?*font_module.FontFace {
        for (font_paths) |path| {
            if (self.font_manager.loadFont(path, font_name)) |face| {
                log.debug("Successfully loaded {s} font from: {s}\n", .{ log_prefix, path });
                return face;
            } else |_| {
                // 继续尝试下一个路径
                continue;
            }
        }
        return null;
    }

    /// 优先尝试加载支持中文的字体（包括简体、繁体）
    fn tryLoadChineseFont(self: *CpuRenderBackend) !?*font_module.FontFace {
        // 中文字体路径（按优先级排序）
        // 注意：这些字体通常也支持繁体中文
        // 优先使用TTF字体（使用glyf表），然后是OTF字体（使用CFF表）
        // 注意：TTC格式（TrueType Collection）暂不支持，需要先解析TTC头部
        const chinese_font_paths = [_][]const u8{
            // 优先使用支持中文的TrueType字体（TTF格式，使用glyf表）
            "fonts/NotoSansCJKSC-Regular.ttf", // Noto Sans CJK SC（TrueType格式，支持简体中文）
            // Windows系统字体（TrueType格式，仅Windows）
            "C:\\Windows\\Fonts\\simhei.ttf", // 黑体（TrueType格式）
            "C:\\Windows\\Fonts\\SimHei.ttf",
            "C:\\Windows\\Fonts\\simkai.ttf", // 楷体（TrueType格式）
            "C:\\Windows\\Fonts\\SimKai.ttf",
            // 本地路径（TrueType格式）
            "fonts/simhei.ttf",
            "simhei.ttf",
            // 注意：TTC格式（TrueType Collection）暂不支持，需要先解析TTC头部
            // "fonts/wqy-zenhei.ttc", // 文泉驿正黑（TTC格式，暂不支持）
            // "fonts/wqy-microhei.ttc", // 文泉驿微米黑（TTC格式，暂不支持）
            // "C:\\Windows\\Fonts\\msyh.ttc", // 微软雅黑（TTC格式，暂不支持）
            // "C:\\Windows\\Fonts\\simsun.ttc", // 宋体（TTC格式，暂不支持）
            // 备选：使用支持中文的OTF字体（CFF格式），因为CFF子程序调用功能未完全实现，可能导致某些复杂字形无法正确渲染
            "fonts/SourceHanSansSC-Regular.otf", // 思源黑体简体中文（OTF格式，CFF表，支持中文）
            "fonts/SourceHanSansSC-Medium.otf", // 思源黑体简体中文（OTF格式，CFF表，支持中文）
            // 本地路径（TrueType格式）
            "fonts/simhei.ttf",
            "simhei.ttf",
            // 注意：TTC格式（TrueType Collection）暂不支持，需要先解析TTC头部
            // "fonts/wqy-zenhei.ttc", // 文泉驿正黑（TTC格式，暂不支持）
            // "fonts/wqy-microhei.ttc", // 文泉驿微米黑（TTC格式，暂不支持）
            // "C:\\Windows\\Fonts\\msyh.ttc", // 微软雅黑（TTC格式，暂不支持）
            // "C:\\Windows\\Fonts\\simsun.ttc", // 宋体（TTC格式，暂不支持）
            // 以下字体不支持中文，仅作为最后备选
            // "fonts/NotoSansArabic-Regular.ttf", // Noto Sans（TrueType格式，不支持中文）
            // "fonts/NotoSansArabic-Bold.ttf",
            // "fonts/NotoSansThai-Regular.ttf",
            // "fonts/NotoSansThai-Bold.ttf",
        };

        // 尝试加载中文字体
        return try self.tryLoadFontFromPaths(&chinese_font_paths, "ChineseFont", "Chinese");
    }

    /// 尝试加载日文字体
    /// 优先尝试加载支持日文的字体
    fn tryLoadJapaneseFont(self: *CpuRenderBackend) !?*font_module.FontFace {
        // 日文字体路径（按优先级排序）
        const japanese_font_paths = [_][]const u8{
            // 优先使用TrueType字体（TTF格式，使用glyf表）
            // Windows系统字体（TrueType格式）
            "C:\\Windows\\Fonts\\yugothic.ttf", // Yu Gothic（TrueType格式）
            "C:\\Windows\\Fonts\\YuGothic.ttf",
            // 注意：TTC格式（TrueType Collection）暂不支持
            // "C:\\Windows\\Fonts\\msgothic.ttc", // MS Gothic（TTC格式，暂不支持）
            // "C:\\Windows\\Fonts\\msmincho.ttc", // MS Mincho（TTC格式，暂不支持）
            // "C:\\Windows\\Fonts\\msyh.ttc", // 微软雅黑（TTC格式，暂不支持）
            // 暂时不使用OTF字体（CFF格式），因为CFF子程序调用功能未完全实现
            // "fonts/SourceHanSansSC-Regular.otf", // 思源黑体（OTF格式，CFF表）
            // "fonts/SourceHanSansSC-Medium.otf", // 思源黑体（OTF格式，CFF表）
        };

        // 尝试加载日文字体
        return try self.tryLoadFontFromPaths(&japanese_font_paths, "JapaneseFont", "Japanese");
    }

    /// 尝试加载韩文字体
    /// 优先尝试加载支持韩文的字体
    fn tryLoadKoreanFont(self: *CpuRenderBackend) !?*font_module.FontFace {
        // 韩文字体路径（按优先级排序）
        const korean_font_paths = [_][]const u8{
            // 优先使用TrueType字体（TTF格式，使用glyf表）
            // 本地项目字体（TrueType格式，支持韩文）
            "fonts/NotoSansCJKKR-Regular.ttf", // Noto Sans CJK KR（TrueType格式，支持韩文）
            // Windows系统字体（TrueType格式，支持韩文）
            "C:\\Windows\\Fonts\\arialuni.ttf", // Arial Unicode MS（TrueType格式，支持韩文等多种语言）
            "C:\\Windows\\Fonts\\ArialUni.ttf",
            "C:\\Windows\\Fonts\\ARIALUNI.TTF",
            "C:\\Windows\\Fonts\\malgun.ttf", // Malgun Gothic（맑은 고딕，TrueType格式）
            "C:\\Windows\\Fonts\\Malgun.ttf",
            "C:\\Windows\\Fonts\\malgunbd.ttf", // Malgun Gothic Bold（TrueType格式）
            "C:\\Windows\\Fonts\\MalgunBD.ttf",
            // 本地路径（TrueType格式）
            "fonts/malgun.ttf",
            "malgun.ttf",
            // 注意：TTC格式（TrueType Collection）暂不支持
            // "C:\\Windows\\Fonts\\gulim.ttc", // Gulim（TTC格式，暂不支持）
            // "C:\\Windows\\Fonts\\batang.ttc", // Batang（TTC格式，暂不支持）
            // 暂时不使用OTF字体（CFF格式），因为CFF子程序调用功能未完全实现
            // "fonts/SourceHanSansSC-Regular.otf", // 思源黑体（OTF格式，CFF表）
            // "fonts/SourceHanSansSC-Medium.otf", // 思源黑体（OTF格式，CFF表）
        };

        // 尝试加载韩文字体
        const result = try self.tryLoadFontFromPaths(&korean_font_paths, "KoreanFont", "Korean");
        if (result == null) {
            log.warn("Warning: No Korean font found, Korean text may not display correctly\n", .{});
        }
        return result;
    }

    /// 尝试加载符号字体（Segoe UI Symbol）
    fn tryLoadSymbolFont(self: *CpuRenderBackend) !?*font_module.FontFace {
        const symbol_font_paths = [_][]const u8{
            "C:\\Windows\\Fonts\\seguisym.ttf", // Segoe UI Symbol
            "C:\\Windows\\Fonts\\SegoeUISymbol.ttf",
            "C:\\Windows\\Fonts\\seguisym.ttc",
        };
        return try self.tryLoadFontFromPaths(&symbol_font_paths, "SymbolFont", "Symbol");
    }

    /// 尝试加载Emoji字体（Segoe UI Emoji）
    fn tryLoadEmojiFont(self: *CpuRenderBackend) !?*font_module.FontFace {
        const emoji_font_paths = [_][]const u8{
            "C:\\Windows\\Fonts\\seguiemj.ttf", // Segoe UI Emoji
            "C:\\Windows\\Fonts\\SegoeUIEmoji.ttf",
            "C:\\Windows\\Fonts\\seguiemj.ttc",
        };
        return try self.tryLoadFontFromPaths(&emoji_font_paths, "EmojiFont", "Emoji");
    }

    /// 根据字符码点尝试加载合适的回退字体
    /// 用于支持Unicode符号、数学符号、箭头、Emoji等
    fn tryLoadFallbackFontForCodepoint(self: *CpuRenderBackend, codepoint: u21) !?*font_module.FontFace {
        // 检查字符类型，选择合适的字体
        if (codepoint >= 0x1F300 and codepoint <= 0x1F9FF) {
            // Emoji范围（U+1F300-U+1F9FF）
            if (self.tryLoadEmojiFont() catch null) |face| {
                log.debug("Successfully loaded emoji font for codepoint U+{X:0>4}\n", .{codepoint});
                return face;
            }
        } else if ((codepoint >= 0x2190 and codepoint <= 0x21FF) or // 箭头
            (codepoint >= 0x2200 and codepoint <= 0x22FF) or // 数学运算符
            (codepoint >= 0x2300 and codepoint <= 0x23FF) or // 技术符号
            (codepoint >= 0x2600 and codepoint <= 0x26FF) or // 杂项符号
            (codepoint >= 0x2700 and codepoint <= 0x27BF))
        { // 装饰符号
            // Unicode符号范围
            if (self.tryLoadSymbolFont() catch null) |face| {
                log.debug("Successfully loaded symbol font for codepoint U+{X:0>4}\n", .{codepoint});
                return face;
            }
        }

        // 尝试加载泰文字体（U+0E00 - U+0E7F）
        if (codepoint >= 0x0E00 and codepoint <= 0x0E7F) {
            const thai_font_paths = [_][]const u8{
                // 本地项目字体（优先）
                "fonts/NotoSansThai-Regular.ttf",
                "fonts/NotoSansThai-Bold.ttf",
                // Windows系统字体
                "C:\\Windows\\Fonts\\tahoma.ttf",
                "C:\\Windows\\Fonts\\Tahoma.ttf",
            };
            for (thai_font_paths) |path| {
                if (self.font_manager.loadFont(path, "ThaiFont")) |face| {
                    const glyph_index_opt = face.getGlyphIndex(codepoint) catch null;
                    if (glyph_index_opt != null) {
                        log.debug("Successfully loaded Thai font from: {s} for codepoint U+{X:0>4}\n", .{ path, codepoint });
                        return face;
                    }
                } else |_| {
                    continue;
                }
            }
        }

        // 尝试加载阿拉伯文字体（U+0600 - U+06FF, U+0750 - U+077F, U+08A0 - U+08FF, U+FB50 - U+FDFF, U+FE70 - U+FEFF）
        if ((codepoint >= 0x0600 and codepoint <= 0x06FF) or
            (codepoint >= 0x0750 and codepoint <= 0x077F) or
            (codepoint >= 0x08A0 and codepoint <= 0x08FF) or
            (codepoint >= 0xFB50 and codepoint <= 0xFDFF) or
            (codepoint >= 0xFE70 and codepoint <= 0xFEFF))
        {
            const arabic_font_paths = [_][]const u8{
                // 本地项目字体（优先）
                "fonts/NotoSansArabic-Regular.ttf",
                "fonts/NotoSansArabic-Bold.ttf",
                // Windows系统字体
                "C:\\Windows\\Fonts\\tahoma.ttf",
                "C:\\Windows\\Fonts\\Tahoma.ttf",
                "C:\\Windows\\Fonts\\arial.ttf",
                "C:\\Windows\\Fonts\\Arial.ttf",
            };
            for (arabic_font_paths) |path| {
                if (self.font_manager.loadFont(path, "ArabicFont")) |face| {
                    const glyph_index_opt = face.getGlyphIndex(codepoint) catch null;
                    if (glyph_index_opt != null) {
                        log.debug("Successfully loaded Arabic font from: {s} for codepoint U+{X:0>4}\n", .{ path, codepoint });
                        return face;
                    }
                } else |_| {
                    continue;
                }
            }
        }

        // 对于其他Unicode字符，尝试加载通用Unicode字体
        // 注意：Arial Unicode MS可能不在所有Windows系统上，所以作为最后尝试
        const unicode_font_paths = [_][]const u8{
            // 优先使用TrueType字体（TTF格式，使用glyf表）
            // Windows系统字体（TrueType格式）
            "C:\\Windows\\Fonts\\arialuni.ttf", // Arial Unicode MS（TrueType格式）
            "C:\\Windows\\Fonts\\ArialUni.ttf",
            "C:\\Windows\\Fonts\\calibri.ttf", // Calibri（TrueType格式，支持一些Unicode字符）
            "C:\\Windows\\Fonts\\Calibri.ttf",
            "C:\\Windows\\Fonts\\segoeui.ttf", // Segoe UI（TrueType格式，支持一些Unicode字符）
            "C:\\Windows\\Fonts\\SegoeUI.ttf",
            // 暂时不使用OTF字体（CFF格式），因为CFF子程序调用功能未完全实现
            // "fonts/SourceHanSansSC-Regular.otf", // 思源黑体（OTF格式，CFF表）
            // "fonts/SourceHanSansSC-Medium.otf", // 思源黑体（OTF格式，CFF表）
        };
        for (unicode_font_paths) |path| {
            if (self.font_manager.loadFont(path, "UnicodeFont")) |face| {
                // 验证这个字体是否真的支持该字符
                const glyph_index_opt = face.getGlyphIndex(codepoint) catch null;
                if (glyph_index_opt != null) {
                    log.debug("Successfully loaded unicode font from: {s} for codepoint U+{X:0>4}\n", .{ path, codepoint });
                    return face;
                }
            } else |_| {
                continue;
            }
        }

        return null;
    }

    /// 尝试加载默认字体
    /// 从常见路径查找并加载字体文件
    fn tryLoadDefaultFont(self: *CpuRenderBackend, font_family: []const u8) !?*font_module.FontFace {
        // 常见的字体文件路径（Windows）
        // 优先尝试中文字体
        const font_paths = [_][]const u8{
            // 优先使用TrueType字体（TTF格式，使用glyf表）
            // 本地项目字体（TrueType格式）
            "fonts/NotoSansArabic-Regular.ttf", // Noto Sans（TrueType格式）
            "fonts/NotoSansArabic-Bold.ttf",
            "fonts/NotoSansThai-Regular.ttf",
            "fonts/NotoSansThai-Bold.ttf",
            // Windows系统字体（TrueType格式，仅Windows）
            "C:\\Windows\\Fonts\\simhei.ttf", // 黑体（TrueType格式）
            "C:\\Windows\\Fonts\\SimHei.ttf",
            "C:\\Windows\\Fonts\\simkai.ttf", // 楷体（TrueType格式）
            "C:\\Windows\\Fonts\\SimKai.ttf",
            // 英文字体（TrueType格式，回退）
            "C:\\Windows\\Fonts\\arial.ttf",
            "C:\\Windows\\Fonts\\Arial.ttf",
            "C:\\Windows\\Fonts\\calibri.ttf",
            "C:\\Windows\\Fonts\\Calibri.ttf",
            // 本地路径（TrueType格式）
            "fonts/simhei.ttf",
            "fonts/arial.ttf",
            "fonts/Arial.ttf",
            "simhei.ttf",
            "arial.ttf",
            "Arial.ttf",
            // 注意：TTC格式（TrueType Collection）暂不支持
            // "C:\\Windows\\Fonts\\simsun.ttc", // 宋体（TTC格式，暂不支持）
            // "C:\\Windows\\Fonts\\msyh.ttc", // 微软雅黑（TTC格式，暂不支持）
            // 暂时不使用OTF字体（CFF格式），因为CFF子程序调用功能未完全实现
            // "fonts/SourceHanSansSC-Regular.otf", // 思源黑体（OTF格式，CFF表）
            // "fonts/SourceHanSansSC-Medium.otf", // 思源黑体（OTF格式，CFF表）
        };

        // 根据字体名称选择可能的路径
        var font_name_lower = std.ArrayList(u8){};
        defer font_name_lower.deinit(self.allocator);
        for (font_family) |c| {
            font_name_lower.append(self.allocator, std.ascii.toLower(c)) catch break;
        }
        const font_name_lower_slice = font_name_lower.items;

        // 尝试从常见路径加载字体
        for (font_paths) |path| {
            // 如果路径包含字体名称（不区分大小写），优先尝试
            var path_lower = std.ArrayList(u8){};
            defer path_lower.deinit(self.allocator);
            for (path) |c| {
                path_lower.append(self.allocator, std.ascii.toLower(c)) catch break;
            }
            const path_lower_slice = path_lower.items;

            // 检查路径是否包含字体名称
            const should_try = if (std.mem.indexOf(u8, path_lower_slice, font_name_lower_slice) != null) true else if (std.mem.eql(u8, font_name_lower_slice, "arial") and std.mem.indexOf(u8, path_lower_slice, "arial") != null) true else false;

            if (should_try) {
                if (self.font_manager.loadFont(path, font_family)) |face| {
                    log.debug("Successfully loaded font from: {s}\n", .{path});
                    return face;
                } else |_| {
                    // 继续尝试下一个路径
                    continue;
                }
            }
        }

        // 如果按名称匹配失败，尝试所有路径
        for (font_paths) |path| {
            if (self.font_manager.loadFont(path, font_family)) |face| {
                log.debug("Successfully loaded font from: {s}\n", .{path});
                return face;
            } else |_| {
                // 继续尝试下一个路径
                continue;
            }
        }

        return null;
    }

    /// 使用混合字体渲染文本（支持按字符切换字体）
    /// 参数：
    /// - primary_font: 主字体（用于大部分字符）
    /// - fallback_font: 备用字体（用于主字体不支持的字符，如中文汉字）
    /// - letter_spacing: 字符间距（如果为null，表示使用默认间距）
    fn renderTextWithMixedFonts(
        self: *CpuRenderBackend,
        primary_font: *font_module.FontFace,
        fallback_font: ?*font_module.FontFace,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        color: backend.Color,
        letter_spacing: ?f32,
    ) !void {
        // 获取主字体度量信息
        const font_metrics = try primary_font.getFontMetrics();
        const units_per_em = font_metrics.units_per_em;
        const scale = font_size / @as(f32, @floatFromInt(units_per_em));

        // 当前X位置
        var current_x = x;
        var is_first_char = true;

        // 遍历文本中的每个字符
        var i: usize = 0;
        while (i < text.len) {
            const decode_result = self.decodeUtf8Codepoint(text[i..]) catch {
                i += 1;
                continue;
            };
            const codepoint = decode_result.codepoint;
            i += decode_result.bytes_consumed;

            // 确定使用哪个字体
            var font_to_use = primary_font;
            var font_metrics_to_use = font_metrics;
            var scale_to_use = scale;

            // 尝试从主字体获取字形索引
            const glyph_index_opt = try primary_font.getGlyphIndex(codepoint);
            if (glyph_index_opt == null) {
                // 主字体不支持，尝试使用备用字体
                if (fallback_font) |fallback| {
                    const fallback_glyph_index_opt = try fallback.getGlyphIndex(codepoint);
                    if (fallback_glyph_index_opt) |fallback_glyph_index| {
                        font_to_use = fallback;
                        font_metrics_to_use = try fallback.getFontMetrics();
                        scale_to_use = font_size / @as(f32, @floatFromInt(font_metrics_to_use.units_per_em));

                        // 使用备用字体渲染
                        const h_metrics = try fallback.getHorizontalMetrics(fallback_glyph_index);
                        var glyph = try fallback.getGlyph(fallback_glyph_index);
                        defer glyph.deinit(self.allocator);

                        const glyph_x = if (is_first_char) current_x else current_x + @as(f32, @floatFromInt(h_metrics.left_side_bearing)) * scale_to_use;
                        is_first_char = false;

                        self.glyph_renderer.renderGlyph(
                            &glyph,
                            self.pixels,
                            self.width,
                            self.height,
                            glyph_x,
                            y,
                            font_size,
                            font_metrics_to_use.units_per_em,
                            color,
                        );

                        const advance_width = @as(f32, @floatFromInt(h_metrics.advance_width));
                        // 对于CJK字符，如果advance_width明显大于字体大小，则缩小到字体大小的0.95倍
                        const is_cjk = (codepoint >= 0x4E00 and codepoint <= 0x9FFF) or // 中文
                            (codepoint >= 0x3040 and codepoint <= 0x309F) or // 日文平假名
                            (codepoint >= 0x30A0 and codepoint <= 0x30FF) or // 日文片假名
                            (codepoint >= 0xAC00 and codepoint <= 0xD7AF); // 韩文
                        const adjusted_advance = if (is_cjk and advance_width * scale_to_use > font_size * 1.1)
                            font_size * 0.95
                        else
                            advance_width * scale_to_use;
                        current_x += adjusted_advance;
                        continue;
                    }
                }
                // 如果备用字体也不支持，跳过这个字符
                const placeholder_width = font_size * 0.6;
                current_x += placeholder_width;
                
                // 应用letter-spacing（如果不是最后一个字符）
                if (letter_spacing) |spacing| {
                    if (i < text.len) {
                        current_x += spacing;
                    }
                }
                continue;
            }

            // 使用主字体渲染
            const glyph_index = glyph_index_opt.?;
            const h_metrics = try primary_font.getHorizontalMetrics(glyph_index);
            var glyph = try primary_font.getGlyph(glyph_index);
            defer glyph.deinit(self.allocator);

            const glyph_x = if (is_first_char) current_x else current_x + @as(f32, @floatFromInt(h_metrics.left_side_bearing)) * scale;
            is_first_char = false;

            self.glyph_renderer.renderGlyph(
                &glyph,
                self.pixels,
                self.width,
                self.height,
                glyph_x,
                y,
                font_size,
                units_per_em,
                color,
            );

            const advance_width = @as(f32, @floatFromInt(h_metrics.advance_width));
            current_x += advance_width * scale;
            
            // 应用letter-spacing（如果不是最后一个字符）
            if (letter_spacing) |spacing| {
                if (i < text.len) {
                    current_x += spacing;
                }
            }
        }
    }

    /// 使用字体回退列表渲染文本
    /// 按字符逐个尝试字体列表，直到找到支持该字符的字体
    /// 如果所有字体都不支持某个字符，跳过该字符（不绘制）
    /// - letter_spacing: 字符间距（如果为null，表示使用默认间距）
    fn renderTextWithFontFallback(
        self: *CpuRenderBackend,
        font_faces: []*font_module.FontFace,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        color: backend.Color,
        letter_spacing: ?f32,
    ) !void {
        if (font_faces.len == 0) {
            return error.NoFontAvailable;
        }

        // 使用第一个字体初始化hinting（简化：只初始化一次）
        const primary_face = font_faces[0];
        const fpgm_data = primary_face.getFpgm();
        const prep_data = primary_face.getPrep();
        const cvt_data = primary_face.getCvt();
        _ = self.glyph_renderer.initHinting(fpgm_data, prep_data, cvt_data) catch {};

        var current_x = x;
        var is_first_char = true;
        var i: usize = 0;

        while (i < text.len) {
            const decode_result = self.decodeUtf8Codepoint(text[i..]) catch {
                i += 1;
                continue;
            };
            const codepoint = decode_result.codepoint;
            i += decode_result.bytes_consumed;

            // 尝试所有字体，找到支持该字符的字体
            var found_font: ?*font_module.FontFace = null;
            var found_glyph_index: ?u16 = null;
            var found_metrics: ?struct { advance_width: u16, left_side_bearing: i16 } = null;
            var found_scale: f32 = 0;
            var found_units_per_em: u16 = 0;

            for (font_faces) |font_face| {
                const glyph_index_opt = font_face.getGlyphIndex(codepoint) catch continue;
                if (glyph_index_opt) |glyph_index| {
                    const font_metrics = font_face.getFontMetrics() catch continue;
                    const units_per_em = font_metrics.units_per_em;
                    const scale = font_size / @as(f32, @floatFromInt(units_per_em));
                    const h_metrics = font_face.getHorizontalMetrics(glyph_index) catch continue;

                    found_font = font_face;
                    found_glyph_index = glyph_index;
                    found_metrics = .{
                        .advance_width = h_metrics.advance_width,
                        .left_side_bearing = h_metrics.left_side_bearing,
                    };
                    found_scale = scale;
                    found_units_per_em = units_per_em;
                    break;
                }
            }

            if (found_font) |font_face| {
                const glyph_index = found_glyph_index.?;
                const h_metrics = found_metrics.?;
                const scale = found_scale;
                const units_per_em = found_units_per_em;

                // 获取字形数据
                std.log.warn("[CpuBackend] renderTextWithFontFallback: calling getGlyph for glyph_index={d}", .{glyph_index});
                var glyph = font_face.getGlyph(glyph_index) catch |err| {
                    std.log.warn("[CpuBackend] renderTextWithFontFallback: getGlyph failed for glyph_index={d}, error={}", .{ glyph_index, err });
                    // 如果获取字形失败，跳过这个字符
                    const placeholder_width = font_size * 0.6;
                    current_x += placeholder_width;
                    
                    // 应用letter-spacing（如果不是最后一个字符）
                    if (letter_spacing) |spacing| {
                        if (i < text.len) {
                            current_x += spacing;
                        }
                    }
                    continue;
                };
                std.log.warn("[CpuBackend] renderTextWithFontFallback: got glyph, points.len={d}", .{glyph.points.items.len});
                defer glyph.deinit(self.allocator);

                // 计算字形的X位置
                const glyph_x = if (is_first_char)
                    current_x
                else
                    current_x + @as(f32, @floatFromInt(h_metrics.left_side_bearing)) * scale;

                is_first_char = false;

                // 渲染字形
                self.glyph_renderer.renderGlyph(
                    &glyph,
                    self.pixels,
                    self.width,
                    self.height,
                    glyph_x,
                    y,
                    font_size,
                    units_per_em,
                    color,
                );

                // 移动到下一个字符位置
                const advance_width = @as(f32, @floatFromInt(h_metrics.advance_width));
                const is_cjk = (codepoint >= 0x4E00 and codepoint <= 0x9FFF) or
                    (codepoint >= 0x3040 and codepoint <= 0x309F) or
                    (codepoint >= 0x30A0 and codepoint <= 0x30FF) or
                    (codepoint >= 0xAC00 and codepoint <= 0xD7AF);
                const adjusted_advance = if (is_cjk and advance_width * scale > font_size * 1.1)
                    font_size * 0.95
                else
                    advance_width * scale;
                current_x += adjusted_advance;
                
                // 应用letter-spacing（如果不是最后一个字符）
                if (letter_spacing) |spacing| {
                    if (i < text.len) {
                        current_x += spacing;
                    }
                }
            } else {
                // 所有已加载字体都不支持这个字符，尝试动态加载支持该字符的字体
                const fallback_font = self.tryLoadFallbackFontForCodepoint(codepoint) catch null;
                if (fallback_font) |font_face| {
                    // 尝试从新加载的字体获取字形
                    const glyph_index_opt = font_face.getGlyphIndex(codepoint) catch null;
                    if (glyph_index_opt) |glyph_index| {
                        const font_metrics = font_face.getFontMetrics() catch {
                            const placeholder_width = font_size * 0.6;
                            current_x += placeholder_width;
                            continue;
                        };
                        const units_per_em = font_metrics.units_per_em;
                        const scale = font_size / @as(f32, @floatFromInt(units_per_em));
                        const h_metrics = font_face.getHorizontalMetrics(glyph_index) catch {
                            const placeholder_width = font_size * 0.6;
                            current_x += placeholder_width;
                            continue;
                        };

                        // 获取字形数据
                        var glyph = font_face.getGlyph(glyph_index) catch {
                            const placeholder_width = font_size * 0.6;
                            current_x += placeholder_width;
                            continue;
                        };
                        defer glyph.deinit(self.allocator);

                        // 计算字形的X位置
                        const glyph_x = if (is_first_char)
                            current_x
                        else
                            current_x + @as(f32, @floatFromInt(h_metrics.left_side_bearing)) * scale;

                        is_first_char = false;

                        // 渲染字形
                        self.glyph_renderer.renderGlyph(
                            &glyph,
                            self.pixels,
                            self.width,
                            self.height,
                            glyph_x,
                            y,
                            font_size,
                            units_per_em,
                            color,
                        );

                        // 移动到下一个字符位置
                        const advance_width = @as(f32, @floatFromInt(h_metrics.advance_width));
                        current_x += advance_width * scale;
                        
                        // 应用letter-spacing（如果不是最后一个字符）
                        if (letter_spacing) |spacing| {
                            if (i < text.len) {
                                current_x += spacing;
                            }
                        }
                        continue;
                    }
                }
                // 如果所有字体都不支持这个字符，跳过（不绘制占位符框）
                const placeholder_width = font_size * 0.6;
                current_x += placeholder_width;
                
                // 应用letter-spacing（如果不是最后一个字符）
                if (letter_spacing) |spacing| {
                    if (i < text.len) {
                        current_x += spacing;
                    }
                }
            }
        }
    }

    /// 使用字体渲染真正的文本
    /// 如果字体不支持某个字符，返回error.GlyphNotFound
    fn renderTextWithFont(
        self: *CpuRenderBackend,
        font_face: *font_module.FontFace,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        color: backend.Color,
        letter_spacing: ?f32,
    ) !void {
        // 初始化Hinting（如果尚未初始化）
        // 获取hinting表
        const fpgm_data = font_face.getFpgm();
        const prep_data = font_face.getPrep();
        const cvt_data = font_face.getCvt();

        // 初始化hinting解释器
        _ = self.glyph_renderer.initHinting(fpgm_data, prep_data, cvt_data) catch {
            // Hinting初始化失败，继续使用原始渲染
        };

        // 获取字体度量信息
        const font_metrics = try font_face.getFontMetrics();
        const units_per_em = font_metrics.units_per_em;

        // 计算缩放因子
        const scale = font_size / @as(f32, @floatFromInt(units_per_em));

        // 当前X位置
        var current_x = x;
        // y是基线位置，直接传递给renderGlyph

        // 遍历文本中的每个字符
        var i: usize = 0;
        var is_first_char = true; // 标记是否是第一个字符
        while (i < text.len) {
            const decode_result = self.decodeUtf8Codepoint(text[i..]) catch {
                // 如果解码失败，跳过这个字节
                i += 1;
                continue;
            };
            const codepoint = decode_result.codepoint;
            i += decode_result.bytes_consumed;

            // 获取字符的字形索引
            const glyph_index_opt = try font_face.getGlyphIndex(codepoint);
            if (glyph_index_opt) |glyph_index| {
                // 调试：检查"韩"字（U+97E9）的字形索引
                if (codepoint == 0x97E9) {
                    log.debug("renderTextWithFont: found glyph for '韩' (U+97E9), glyph_index={d}\n", .{glyph_index});
                }
                // 获取字形的水平度量
                const h_metrics = try font_face.getHorizontalMetrics(glyph_index);

                // 获取字形数据
                var glyph = try font_face.getGlyph(glyph_index);
                defer glyph.deinit(self.allocator);

                // 计算字形的X位置
                // 注意：对于第一个字符，不应该使用left_side_bearing，因为它会改变文本的起始位置
                // left_side_bearing主要用于调整字符之间的间距，而不是文本的起始位置
                const glyph_x = if (is_first_char)
                    current_x // 第一个字符直接使用current_x，不使用left_side_bearing
                else
                    current_x + @as(f32, @floatFromInt(h_metrics.left_side_bearing)) * scale;

                is_first_char = false; // 后续字符不再是第一个

                // 渲染字形
                self.glyph_renderer.renderGlyph(
                    &glyph,
                    self.pixels,
                    self.width,
                    self.height,
                    glyph_x,
                    y, // y是基线位置
                    font_size,
                    units_per_em,
                    color,
                );

                // 移动到下一个字符位置（考虑字符宽度）
                // 对于中文字符，advance_width可能过大，需要适当缩小
                const advance_width = @as(f32, @floatFromInt(h_metrics.advance_width));
                // 检测是否为CJK字符（中文、日文、韩文）
                const is_cjk = (codepoint >= 0x4E00 and codepoint <= 0x9FFF) or // 中文
                    (codepoint >= 0x3040 and codepoint <= 0x309F) or // 日文平假名
                    (codepoint >= 0x30A0 and codepoint <= 0x30FF) or // 日文片假名
                    (codepoint >= 0xAC00 and codepoint <= 0xD7AF); // 韩文
                // 对于CJK字符，如果advance_width明显大于字体大小，则缩小到字体大小的0.95倍
                // 这样可以减少字符间距，让文本更紧凑
                const adjusted_advance = if (is_cjk and advance_width * scale > font_size * 1.1)
                    font_size * 0.95
                else
                    advance_width * scale;
                current_x += adjusted_advance;
                
                // 应用letter-spacing（如果不是最后一个字符）
                if (letter_spacing) |spacing| {
                    if (i < text.len) {
                        current_x += spacing;
                    }
                }
            } else {
                // 如果找不到字形，返回错误，让调用者回退到其他字体
                // 调试：检查"韩"字（U+97E9）是否找不到字形
                if (codepoint == 0x97E9) {
                    log.debug("renderTextWithFont: glyph not found for '韩' (U+97E9), will fallback to Chinese font\n", .{});
                }
                return error.GlyphNotFound;
            }
        }
    }

    /// 解码UTF-8字符码点（完整实现，支持中文等多字节字符）
    fn decodeUtf8Codepoint(self: *CpuRenderBackend, bytes: []const u8) !struct { codepoint: u21, bytes_consumed: usize } {
        _ = self;
        if (bytes.len == 0) {
            return error.InvalidUtf8;
        }

        const first_byte = bytes[0];

        // ASCII字符（0-127）
        if (first_byte < 128) {
            return .{ .codepoint = first_byte, .bytes_consumed = 1 };
        }

        // 多字节UTF-8字符
        var codepoint: u21 = 0;
        var bytes_consumed: usize = 0;

        if ((first_byte & 0xE0) == 0xC0) {
            // 2字节字符（110xxxxx 10xxxxxx）
            if (bytes.len < 2) return error.InvalidUtf8;
            if ((bytes[1] & 0xC0) != 0x80) return error.InvalidUtf8;
            codepoint = (@as(u21, first_byte & 0x1F) << 6) | @as(u21, bytes[1] & 0x3F);
            bytes_consumed = 2;
        } else if ((first_byte & 0xF0) == 0xE0) {
            // 3字节字符（1110xxxx 10xxxxxx 10xxxxxx）
            if (bytes.len < 3) return error.InvalidUtf8;
            if ((bytes[1] & 0xC0) != 0x80) return error.InvalidUtf8;
            if ((bytes[2] & 0xC0) != 0x80) return error.InvalidUtf8;
            codepoint = (@as(u21, first_byte & 0x0F) << 12) |
                (@as(u21, bytes[1] & 0x3F) << 6) |
                @as(u21, bytes[2] & 0x3F);
            bytes_consumed = 3;
        } else if ((first_byte & 0xF8) == 0xF0) {
            // 4字节字符（11110xxx 10xxxxxx 10xxxxxx 10xxxxxx）
            if (bytes.len < 4) return error.InvalidUtf8;
            if ((bytes[1] & 0xC0) != 0x80) return error.InvalidUtf8;
            if ((bytes[2] & 0xC0) != 0x80) return error.InvalidUtf8;
            if ((bytes[3] & 0xC0) != 0x80) return error.InvalidUtf8;
            codepoint = (@as(u21, first_byte & 0x07) << 18) |
                (@as(u21, bytes[1] & 0x3F) << 12) |
                (@as(u21, bytes[2] & 0x3F) << 6) |
                @as(u21, bytes[3] & 0x3F);
            bytes_consumed = 4;
        } else {
            return error.InvalidUtf8;
        }

        return .{ .codepoint = codepoint, .bytes_consumed = bytes_consumed };
    }

    /// 绘制字符的简单模式（用于占位符）
    fn drawCharPattern(
        self: *CpuRenderBackend,
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        char: u8,
        color: backend.Color,
        font_size: f32,
    ) void {
        const line_width = @max(1.0, font_size * 0.08);
        const center_x = x + width * 0.5;
        const center_y = y + height * 0.5;
        const top_y = y;
        const bottom_y = y + height;
        const left = x;
        const right = x + width;

        // 根据字符绘制不同的模式
        switch (char) {
            'A', 'a' => {
                // 绘制一个简单的"A"形状：倒三角形 + 横线
                self.drawLineBresenham(center_x, top_y, left, bottom_y, color, line_width);
                self.drawLineBresenham(center_x, top_y, right, bottom_y, color, line_width);
                self.drawLineBresenham(left + width * 0.3, center_y, right - width * 0.3, center_y, color, line_width);
            },
            'H', 'h' => {
                // 绘制一个简单的"H"形状：两条竖线 + 横线
                self.drawLineBresenham(left, top_y, left, bottom_y, color, line_width);
                self.drawLineBresenham(right, top_y, right, bottom_y, color, line_width);
                self.drawLineBresenham(left, center_y, right, center_y, color, line_width);
            },
            'E', 'e' => {
                // 绘制一个简单的"E"形状：竖线 + 三条横线
                self.drawLineBresenham(left, top_y, left, bottom_y, color, line_width);
                self.drawLineBresenham(left, top_y, right, top_y, color, line_width);
                self.drawLineBresenham(left, center_y, right * 0.7, center_y, color, line_width);
                self.drawLineBresenham(left, bottom_y, right, bottom_y, color, line_width);
            },
            'L', 'l' => {
                // 绘制一个简单的"L"形状：竖线 + 底横线
                self.drawLineBresenham(left, top_y, left, bottom_y, color, line_width);
                self.drawLineBresenham(left, bottom_y, right, bottom_y, color, line_width);
            },
            'O', 'o' => {
                // 绘制一个简单的"O"形状：椭圆/圆
                const radius = @min(width, height) * 0.4;
                self.drawCircleOutline(center_x, center_y, radius, color, line_width);
            },
            'T', 't' => {
                // 绘制一个简单的"T"形状：顶横线 + 竖线
                self.drawLineBresenham(left, top_y, right, top_y, color, line_width);
                self.drawLineBresenham(center_x, top_y, center_x, bottom_y, color, line_width);
            },
            'I', 'i' => {
                // 绘制一个简单的"I"形状：竖线
                self.drawLineBresenham(center_x, top_y, center_x, bottom_y, color, line_width);
            },
            'N', 'n' => {
                // 绘制一个简单的"N"形状：两条竖线 + 斜线
                self.drawLineBresenham(left, top_y, left, bottom_y, color, line_width);
                self.drawLineBresenham(right, top_y, right, bottom_y, color, line_width);
                self.drawLineBresenham(left, top_y, right, bottom_y, color, line_width);
            },
            'R', 'r' => {
                // 绘制一个简单的"R"形状：竖线 + 半圆 + 斜线
                self.drawLineBresenham(left, top_y, left, bottom_y, color, line_width);
                self.drawLineBresenham(left, top_y, right * 0.7, top_y, color, line_width);
                self.drawLineBresenham(right * 0.7, top_y, right * 0.7, center_y, color, line_width);
                self.drawLineBresenham(left, center_y, right * 0.7, center_y, color, line_width);
                self.drawLineBresenham(right * 0.7, center_y, right, bottom_y, color, line_width);
            },
            'S', 's' => {
                // 绘制一个简单的"S"形状：曲线
                self.drawLineBresenham(left, top_y, right * 0.8, top_y, color, line_width);
                self.drawLineBresenham(left, top_y, left, center_y, color, line_width);
                self.drawLineBresenham(left, center_y, right * 0.8, center_y, color, line_width);
                self.drawLineBresenham(right * 0.8, center_y, right, bottom_y, color, line_width);
                self.drawLineBresenham(right, bottom_y, left * 1.2, bottom_y, color, line_width);
            },
            else => {
                // 默认：绘制一条对角线，表示有字符
                self.drawLineBresenham(left, top_y, right, bottom_y, color, line_width);
            },
        }
    }

    /// 绘制圆形轮廓（简化实现）
    fn drawCircleOutline(
        self: *CpuRenderBackend,
        center_x: f32,
        center_y: f32,
        radius: f32,
        color: backend.Color,
        line_width: f32,
    ) void {
        // 简化实现：绘制16个点形成圆形轮廓
        const num_points = 16;
        var i: usize = 0;
        var prev_x: f32 = center_x + radius;
        var prev_y: f32 = center_y;

        while (i <= num_points) : (i += 1) {
            const angle = 2.0 * math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_points));
            const x = center_x + radius * math.cos(angle);
            const y = center_y + radius * math.sin(angle);

            if (i > 0) {
                self.drawLineBresenham(prev_x, prev_y, x, y, color, line_width);
            }

            prev_x = x;
            prev_y = y;
        }
    }

    /// 使用占位符渲染文本（回退方案）
    fn renderTextPlaceholder(
        self: *CpuRenderBackend,
        text: []const u8,
        x: f32,
        y: f32,
        font: backend.Font,
        color: backend.Color,
    ) void {
        // 估算文本宽度（简化：每个字符宽度为字体大小的0.7倍）
        const char_width = @max(6.0, font.size * 0.7);
        const text_width = char_width * @as(f32, @floatFromInt(text.len));
        const text_height = @max(6.0, font.size);

        // 计算文本位置（y是基线位置，需要调整）
        const text_y = if (y >= text_height) y - text_height else y;

        // 如果文本完全在边界外，不绘制
        if (x + text_width < 0 or x >= @as(f32, @floatFromInt(self.width)) or
            text_y + text_height < 0 or text_y >= @as(f32, @floatFromInt(self.height)))
        {
            return;
        }

        // 确保文本矩形在画布范围内
        const clamped_x = @max(0.0, x);
        const clamped_y = @max(0.0, text_y);
        const max_x = @as(f32, @floatFromInt(self.width));
        const max_y = @as(f32, @floatFromInt(self.height));
        const clamped_width = @min(text_width, max_x - clamped_x);
        const clamped_height = @min(text_height, max_y - clamped_y);

        if (clamped_width > 0 and clamped_height > 0) {
            // 改进的占位符：使用线条绘制简单的字符形状，而不是实心矩形
            const min_char_width = @max(6.0, char_width);
            const min_char_height = @max(6.0, clamped_height * 0.95);

            var char_x = clamped_x;
            var i: usize = 0;
            while (i < text.len and char_x < max_x) : (i += 1) {
                const char_w = @min(min_char_width, max_x - char_x);
                if (char_w > 0) {
                    const char_h = min_char_height;
                    const char_y = clamped_y + (clamped_height - char_h) * 0.5; // 垂直居中

                    // 为每个字符绘制一个简单的线条模式，使其看起来更像文本
                    // 使用边框矩形 + 内部线条
                    const char_rect = backend.Rect.init(char_x, char_y, char_w, char_h);

                    // 绘制边框（细线）
                    const border_width = @max(1.0, font.size * 0.05);
                    strokeRectInternal(self, char_rect, color, border_width);

                    // 根据字符绘制简单的内部线条模式
                    const c = if (i < text.len) text[i] else ' ';
                    self.drawCharPattern(char_x, char_y, char_w, char_h, c, color, font.size);
                }
                char_x += min_char_width;
            }
        }
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
        // 累积旋转角度（支持多次旋转）
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
