const std = @import("std");
const backend = @import("backend");
const ttf_module = @import("ttf");
const hinting_module = @import("hinting");

/// 字形渲染器
/// 负责将字形轮廓转换为像素
pub const GlyphRenderer = struct {
    allocator: std.mem.Allocator,
    /// Hinting解释器
    hinting_interpreter: hinting_module.HintingInterpreter,

    const Self = @This();

    /// 初始化字形渲染器
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .hinting_interpreter = hinting_module.HintingInterpreter.init(allocator),
        };
    }

    /// 清理字形渲染器
    pub fn deinit(self: *Self) void {
        self.hinting_interpreter.deinit();
    }
    
    /// 初始化Hinting（加载fpgm、prep、cvt表）
    pub fn initHinting(
        self: *Self,
        fpgm_data: ?[]const u8,
        prep_data: ?[]const u8,
        cvt_data: ?[]const u8,
    ) !void {
        // 加载CVT表
        if (cvt_data) |cvt| {
            try self.hinting_interpreter.loadCvt(cvt);
        }
        
        // 加载fpgm表
        if (fpgm_data) |fpgm| {
            try self.hinting_interpreter.loadFpgm(fpgm);
        }
        
        // 加载prep表
        if (prep_data) |prep| {
            try self.hinting_interpreter.loadPrep(prep);
        }
    }

    /// 渲染字形到像素缓冲区
    /// 参数：
    /// - glyph: 字形数据
    /// - pixels: 像素缓冲区（RGBA格式）
    /// - width: 图像宽度
    /// - height: 图像高度
    /// - x: 字形X位置
    /// - y: 字形Y位置（基线位置）
    /// - font_size: 字体大小（像素）
    /// - units_per_em: 字体单位/EM
    /// - color: 文本颜色
    pub fn renderGlyph(
        self: *Self,
        glyph: *ttf_module.TtfParser.Glyph,
        pixels: []u8,
        width: u32,
        height: u32,
        x: f32,
        y: f32,
        font_size: f32,
        units_per_em: u16,
        color: backend.Color,
    ) void {
        std.log.warn("[GlyphRenderer] renderGlyph: x={d:.1}, y={d:.1}, font_size={d:.1}, units_per_em={d}, points.len={d}, width={d}, height={d}", .{ x, y, font_size, units_per_em, glyph.points.items.len, width, height });
        if (glyph.points.items.len == 0) {
            // 空字形，不渲染
            std.log.warn("[GlyphRenderer] renderGlyph: empty glyph, skipping", .{});
            return;
        }

        // 边界检查：units_per_em 不能为 0
        if (units_per_em == 0) {
            // units_per_em 为 0 时，无法计算缩放因子，不渲染
            return;
        }

        // 计算缩放因子
        const scale = font_size / @as(f32, @floatFromInt(units_per_em));
        
        // 应用Hinting指令（如果存在）
        if (glyph.instructions.items.len > 0) {
            _ = self.hinting_interpreter.executeGlyphInstructions(
                glyph.instructions.items,
                &glyph.points,
                font_size,
                units_per_em,
            ) catch {
                // Hinting执行失败，继续使用原始点
            };
        }

        // 将轮廓点转换为像素坐标，并处理二次贝塞尔曲线
        var pixel_points = std.ArrayList(Point){};
        defer pixel_points.deinit(self.allocator);
        
        // 记录每个轮廓在pixel_points中的结束索引
        var pixel_contour_end_points = std.ArrayList(usize){};
        defer pixel_contour_end_points.deinit(self.allocator);

        // 处理每个轮廓
        // 如果没有轮廓信息，将所有点作为一个轮廓处理
        if (glyph.contour_end_points.items.len == 0) {
            // 回退到旧的处理方式：将所有点作为一个轮廓
            var i: usize = 0;
            while (i < glyph.points.items.len) : (i += 1) {
                const point = glyph.points.items[i];
                var px = x + @as(f32, @floatFromInt(point.x)) * scale;
                var py = y - @as(f32, @floatFromInt(point.y)) * scale;
                
                // 应用字体Hinting（字体提示）：将坐标对齐到像素网格
                px = self.applyHinting(px, font_size);
                py = self.applyHinting(py, font_size);

                if (point.is_control) {
                    if (i > 0 and i + 1 < glyph.points.items.len) {
                        const prev_point = glyph.points.items[i - 1];
                        const next_point = glyph.points.items[i + 1];
                        var prev_px = x + @as(f32, @floatFromInt(prev_point.x)) * scale;
                        var prev_py = y - @as(f32, @floatFromInt(prev_point.y)) * scale;
                        var next_px = x + @as(f32, @floatFromInt(next_point.x)) * scale;
                        var next_py = y - @as(f32, @floatFromInt(next_point.y)) * scale;
                        
                        // 应用字体Hinting
                        prev_px = self.applyHinting(prev_px, font_size);
                        prev_py = self.applyHinting(prev_py, font_size);
                        next_px = self.applyHinting(next_px, font_size);
                        next_py = self.applyHinting(next_py, font_size);

                        const num_segments = 8;
                        var j: usize = 0;
                        while (j <= num_segments) : (j += 1) {
                            const t = @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(num_segments));
                            const curve_x = (1 - t) * (1 - t) * prev_px + 2 * (1 - t) * t * px + t * t * next_px;
                            const curve_y = (1 - t) * (1 - t) * prev_py + 2 * (1 - t) * t * py + t * t * next_py;
                            pixel_points.append(self.allocator, Point{ .x = curve_x, .y = curve_y }) catch return;
                        }
                    } else {
                        pixel_points.append(self.allocator, Point{ .x = px, .y = py }) catch return;
                    }
                } else {
                    pixel_points.append(self.allocator, Point{ .x = px, .y = py }) catch return;
                }
            }
            // 将整个点列表作为一个轮廓
            if (pixel_points.items.len > 0) {
                pixel_contour_end_points.append(self.allocator, pixel_points.items.len - 1) catch return;
            }
        } else {
            // 正常处理多个轮廓
            var contour_start: usize = 0;
            var contour_idx: usize = 0;
            while (contour_idx < glyph.contour_end_points.items.len) : (contour_idx += 1) {
                const contour_end = glyph.contour_end_points.items[contour_idx];
                
                // 处理当前轮廓的点
                var i = contour_start;
                while (i <= contour_end) : (i += 1) {
                    if (i >= glyph.points.items.len) break;
                    
                    const point = glyph.points.items[i];
                    var px = x + @as(f32, @floatFromInt(point.x)) * scale;
                    var py = y - @as(f32, @floatFromInt(point.y)) * scale; // Y轴翻转：字体坐标系y向上，屏幕坐标系y向下
                    
                    // 应用字体Hinting（字体提示）：将坐标对齐到像素网格
                    // 这可以改善小尺寸文本的清晰度，确保笔画对齐到像素边界
                    px = self.applyHinting(px, font_size);
                    py = self.applyHinting(py, font_size);

                    if (point.is_control) {
                        // 控制点：需要与前一个点和后一个点形成二次贝塞尔曲线
                        const prev_i = if (i > contour_start) i - 1 else contour_end;
                        const next_i = if (i < contour_end) i + 1 else contour_start;
                        
                        if (prev_i < glyph.points.items.len and next_i < glyph.points.items.len) {
                            const prev_point = glyph.points.items[prev_i];
                            const next_point = glyph.points.items[next_i];
                            var prev_px = x + @as(f32, @floatFromInt(prev_point.x)) * scale;
                            var prev_py = y - @as(f32, @floatFromInt(prev_point.y)) * scale;
                            var next_px = x + @as(f32, @floatFromInt(next_point.x)) * scale;
                            var next_py = y - @as(f32, @floatFromInt(next_point.y)) * scale;
                            
                            // 应用字体Hinting
                            prev_px = self.applyHinting(prev_px, font_size);
                            prev_py = self.applyHinting(prev_py, font_size);
                            next_px = self.applyHinting(next_px, font_size);
                            next_py = self.applyHinting(next_py, font_size);

                            // 将二次贝塞尔曲线细分为多个点
                            const num_segments = 8; // 每个曲线段细分为8个点
                            var j: usize = 0;
                            while (j <= num_segments) : (j += 1) {
                                const t = @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(num_segments));
                                const curve_x = (1 - t) * (1 - t) * prev_px + 2 * (1 - t) * t * px + t * t * next_px;
                                const curve_y = (1 - t) * (1 - t) * prev_py + 2 * (1 - t) * t * py + t * t * next_py;
                                pixel_points.append(self.allocator, Point{ .x = curve_x, .y = curve_y }) catch return;
                            }
                        } else {
                            // 边界情况：直接添加点
                            pixel_points.append(self.allocator, Point{ .x = px, .y = py }) catch return;
                        }
                    } else {
                        // 在曲线上的点：直接添加
                        pixel_points.append(self.allocator, Point{ .x = px, .y = py }) catch return;
                    }
                }
                
                // 记录当前轮廓的结束索引
                pixel_contour_end_points.append(self.allocator, pixel_points.items.len - 1) catch return;
                contour_start = contour_end + 1;
            }
        }

        // 使用扫描线算法填充轮廓（支持多个轮廓）
        self.fillOutline(pixel_points.items, pixel_contour_end_points.items, pixels, width, height, color, font_size);
    }

    /// 使用扫描线算法填充轮廓（带抗锯齿，支持多个轮廓）
    /// 使用奇偶填充规则（even-odd rule）：从外向内，奇数个轮廓内的区域填充，偶数个轮廓内的区域不填充
    fn fillOutline(
        self: *Self,
        points: []const Point,
        contour_end_points: []const usize,
        pixels: []u8,
        width: u32,
        height: u32,
        color: backend.Color,
        font_size: f32,
    ) void {
        if (points.len < 3) {
            return;
        }

        // 找到Y坐标的范围
        var min_y: f32 = points[0].y;
        var max_y: f32 = points[0].y;
        for (points) |p| {
            min_y = @min(min_y, p.y);
            max_y = @max(max_y, p.y);
        }
        std.log.warn("[GlyphRenderer] fillOutline: min_y={d:.1}, max_y={d:.1}, height={d}", .{ min_y, max_y, height });

        // 扩展扫描范围以处理边缘抗锯齿
        // 注意：不要过早裁剪，允许扫描超出画布边界（但会在像素写入时检查）
        // 增加扩展范围以提供更好的平滑度（参考Chrome的实现）
        const start_scanline = @as(i32, @intFromFloat(min_y)) - 3;
        const end_scanline = @as(i32, @intFromFloat(max_y)) + 4;
        std.log.warn("[GlyphRenderer] fillOutline: start_scanline={d}, end_scanline={d}", .{ start_scanline, end_scanline });

        // 对每条扫描线，计算与所有轮廓的交点
        var scanline = start_scanline;
        while (scanline < end_scanline) : (scanline += 1) {
            // 检查扫描线是否在画布范围内
            if (scanline < 0 or scanline >= @as(i32, @intCast(height))) continue;
            
            const y = @as(f32, @floatFromInt(scanline)) + 0.5; // 扫描线中心

            // 计算与所有轮廓的交点
            var intersections = std.ArrayList(f32){};
            defer intersections.deinit(std.heap.page_allocator);

            // 遍历每个轮廓
            var contour_start: usize = 0;
            var contour_idx: usize = 0;
            while (contour_idx < contour_end_points.len) : (contour_idx += 1) {
                const contour_end = contour_end_points[contour_idx];
                
                // 计算当前轮廓与扫描线的交点
                var i = contour_start;
                while (i <= contour_end) : (i += 1) {
                    if (i >= points.len) break;
                    
                    const p1 = points[i];
                    const next_i = if (i < contour_end) i + 1 else contour_start;
                    if (next_i >= points.len) break;
                    const p2 = points[next_i];

                    // 检查线段是否与扫描线相交
                    if ((p1.y <= y and p2.y > y) or (p1.y > y and p2.y <= y)) {
                        if (p1.y != p2.y) {
                            const t = (y - p1.y) / (p2.y - p1.y);
                            const x = p1.x + t * (p2.x - p1.x);
                            intersections.append(std.heap.page_allocator, x) catch continue;
                        }
                    }
                }
                
                contour_start = contour_end + 1;
            }

            // 对交点排序
            std.mem.sort(f32, intersections.items, {}, comptime std.sort.asc(f32));

            // 使用奇偶填充规则：填充奇数索引区间（0-1, 2-3, 4-5, ...）
            var j: usize = 0;
            while (j + 1 < intersections.items.len) : (j += 2) {
                const x1 = intersections.items[j];
                const x2 = intersections.items[j + 1];

                // 扩展X范围以处理边缘抗锯齿
                // 注意：不要过早裁剪，允许扫描超出画布边界（但会在像素写入时检查）
                // 增加扩展范围以提供更好的平滑度（参考Chrome的实现）
                const start_x = @as(i32, @intFromFloat(x1)) - 3;
                const end_x = @as(i32, @intFromFloat(x2)) + 4;

                var px = start_x;
            while (px < end_x) : (px += 1) {
                    // 检查像素是否在画布范围内
                    if (px < 0 or px >= @as(i32, @intCast(width))) continue;
                    
                    const pixel_x = @as(f32, @floatFromInt(px)) + 0.5;
                    
                    // 使用子像素渲染（RGB子像素）和MSDF（多通道有符号距离场）
                    // 计算每个RGB子像素的覆盖度，获得3倍的水平分辨率
                    const subpixel_offsets = [_]f32{ -1.0/3.0, 0.0, 1.0/3.0 }; // R, G, B子像素偏移
                    var subpixel_coverages = [_]f32{ 0.0, 0.0, 0.0 };
                    
                    // 计算每个子像素的覆盖度（传入字体大小以调整小字体的抗锯齿参数）
                    var i: usize = 0;
                    while (i < 3) : (i += 1) {
                        const subpixel_x = pixel_x + subpixel_offsets[i];
                        subpixel_coverages[i] = self.calculateCoverageWithMSDF(subpixel_x, y, x1, x2, font_size);
                    }
                    
                    // 使用子像素覆盖度渲染
                    if (subpixel_coverages[0] > 0.0 or subpixel_coverages[1] > 0.0 or subpixel_coverages[2] > 0.0) {
                        const index = (@as(usize, @intCast(scanline)) * width + @as(usize, @intCast(px))) * 4;
                if (index + 3 < pixels.len) {
                            const alpha = @as(f32, @floatFromInt(color.a)) / 255.0;
                            
                            // 分别处理RGB三个通道，使用对应的子像素覆盖度
                            const r_coverage = subpixel_coverages[0] * alpha;
                            const g_coverage = subpixel_coverages[1] * alpha;
                            const b_coverage = subpixel_coverages[2] * alpha;
                            
                            // 计算最终alpha（使用最大覆盖度）
                            const max_coverage = @max(@max(subpixel_coverages[0], subpixel_coverages[1]), subpixel_coverages[2]);
                            const final_alpha = max_coverage * alpha;
                            const final_alpha_u8 = @as(u8, @intFromFloat(final_alpha * 255.0));
                            
                            // 如果像素已有内容，进行alpha混合
                            if (pixels[index + 3] > 0) {
                                const existing_alpha = @as(f32, @floatFromInt(pixels[index + 3])) / 255.0;
                                const combined_alpha = existing_alpha + final_alpha * (1.0 - existing_alpha);
                                
                                if (combined_alpha > 0.0) {
                                    // 分别混合RGB通道
                                    const r_t = r_coverage / combined_alpha;
                                    const g_t = g_coverage / combined_alpha;
                                    const b_t = b_coverage / combined_alpha;
                                    
                                    pixels[index] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(pixels[index])) * (1.0 - r_t) + @as(f32, @floatFromInt(color.r)) * r_t));
                                    pixels[index + 1] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(pixels[index + 1])) * (1.0 - g_t) + @as(f32, @floatFromInt(color.g)) * g_t));
                                    pixels[index + 2] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(pixels[index + 2])) * (1.0 - b_t) + @as(f32, @floatFromInt(color.b)) * b_t));
                                    pixels[index + 3] = @as(u8, @intFromFloat(combined_alpha * 255.0));
                                }
                            } else {
                                // 直接设置像素，使用子像素覆盖度
                                pixels[index] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(color.r)) * r_coverage));
                                pixels[index + 1] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(color.g)) * g_coverage));
                                pixels[index + 2] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(color.b)) * b_coverage));
                                pixels[index + 3] = final_alpha_u8;
                            }
                        }
                    }
                }
            }
        }
    }

    /// 计算像素的覆盖度（用于抗锯齿）- 保留用于兼容性
    fn calculateCoverage(self: *Self, pixel_x: f32, pixel_y: f32, x1: f32, x2: f32) f32 {
        // 使用默认字体大小16px（如果没有提供字体大小信息）
        return self.calculateCoverageWithMSDF(pixel_x, pixel_y, x1, x2, 16.0);
    }

    /// 计算像素的覆盖度（使用MSDF - 多通道有符号距离场）
    /// 使用子像素采样和距离场方法获得更平滑的边缘
    /// 参考Chrome的高质量抗锯齿算法和MSDF技术
    /// font_size: 字体大小（像素），用于调整小字体的抗锯齿参数
    fn calculateCoverageWithMSDF(_: *Self, pixel_x: f32, pixel_y: f32, x1: f32, x2: f32, font_size: f32) f32 {
        const pixel_left = pixel_x - 0.5;
        const pixel_top = pixel_y - 0.5;
        
        // 使用32x32子像素采样（1024个采样点）获得更精确和平滑的覆盖度
        // 更高的采样精度可以获得更接近Chrome的丝滑效果
        const sub_samples = 32;
        var covered: f32 = 0.0;
        const sample_step = 1.0 / @as(f32, @floatFromInt(sub_samples));
        
        var sy: usize = 0;
        while (sy < sub_samples) : (sy += 1) {
            var sx: usize = 0;
            while (sx < sub_samples) : (sx += 1) {
                const sample_x = pixel_left + (@as(f32, @floatFromInt(sx)) + 0.5) * sample_step;
                _ = pixel_top + (@as(f32, @floatFromInt(sy)) + 0.5) * sample_step; // Y坐标用于未来扩展
                
                // 检查采样点是否在轮廓内
                if (sample_x >= x1 and sample_x < x2) {
                    covered += 1.0;
                }
            }
        }
        
        var coverage = covered / @as(f32, @floatFromInt(sub_samples * sub_samples));
        
        // 使用改进的距离场方法增强边缘平滑度
        const center_x = pixel_x;
        
        // 计算到边缘的距离（使用更精确的距离计算）
        const dist_to_left = center_x - x1;
        const dist_to_right = x2 - center_x;
        const min_x_dist = @min(@abs(dist_to_left), @abs(dist_to_right));
        
        // 判断是否在轮廓内部（完全覆盖）
        const is_inside = center_x >= x1 and center_x < x2;
        
        // 根据字体大小调整抗锯齿参数
        // 小字体需要更低的覆盖度以避免笔画过粗
        const is_small_font = font_size < 20.0;
        const min_coverage: f32 = if (is_small_font) 0.75 else 0.95; // 小字体降低最小覆盖度
        const edge_coverage: f32 = if (is_small_font) 0.7 else 0.9; // 小字体降低边缘覆盖度
        const internal_threshold: f32 = if (is_small_font) 0.6 else 0.8; // 小字体降低内部阈值
        
        // 使用更平滑的距离场算法，参考Chrome的实现
        if (is_inside) {
            // 在轮廓内部
            if (min_x_dist > internal_threshold) {
                // 完全在内部，根据字体大小调整覆盖度
                coverage = @max(coverage, min_coverage);
            } else {
                // 在边缘附近，使用平滑过渡
                const smooth_range: f32 = 1.2;
                if (min_x_dist < smooth_range) {
                    // 使用更平滑的插值函数
                    const t = min_x_dist / smooth_range;
                    // 使用改进的smootherstep：提供更平滑的过渡
                    const t2 = t * t;
                    const t3 = t2 * t;
                    const t4 = t3 * t;
                    // 使用四次平滑函数，提供更平滑的过渡
                    const smooth = t4 * (t * (t * 10.0 - 20.0) + 15.0) - t4 * 4.0 + 1.0;
                    // 根据字体大小调整边缘覆盖度
                    const edge_factor: f32 = if (is_small_font) 0.65 else 0.75;
                    const smooth_factor: f32 = if (is_small_font) 0.15 else 0.2;
                    coverage = coverage * (edge_factor + smooth * smooth_factor);
                } else {
                    // 距离边缘较远，根据字体大小调整覆盖度
                    coverage = @max(coverage, edge_coverage);
                }
            }
        } else {
            // 在轮廓外部，使用平滑衰减
            const smooth_range: f32 = 1.2;
            if (min_x_dist < smooth_range) {
                const t = min_x_dist / smooth_range;
                const t2 = t * t;
                const t3 = t2 * t;
                const t4 = t3 * t;
                const smooth = t4 * (t * (t * 10.0 - 20.0) + 15.0) - t4 * 4.0 + 1.0;
                coverage = coverage * (1.0 - smooth);
            } else {
                coverage = 0.0;
            }
        }
        
        // 使用MSDF（多通道有符号距离场）方法
        // MSDF使用有符号距离场来获得更精确的边缘检测和平滑过渡
        const signed_distance = if (is_inside) min_x_dist else -min_x_dist;
        
        // 使用MSDF的平滑函数：将距离转换为覆盖度
        // 使用更平滑的过渡函数，参考MSDF的实现
        // 小字体使用更小的MSDF范围，避免过度平滑导致笔画变粗
        const msdf_range_val: f32 = if (is_small_font) 0.6 else 0.75; // 小字体减小MSDF范围
        const msdf_range = msdf_range_val;
        
        if (@abs(signed_distance) < msdf_range) {
            // 在平滑范围内，使用MSDF的平滑函数
            const t = signed_distance / msdf_range;
            // 使用smoothstep函数：t^2 * (3 - 2t)，提供平滑过渡
            const t2 = t * t;
            const smooth = t2 * (3.0 - 2.0 * t);
            // MSDF的覆盖度计算：内部为正，外部为负
            // 将signed_distance转换为覆盖度，使用平滑函数
            // 小字体降低MSDF覆盖度的影响
            const msdf_coverage = if (signed_distance > 0.0) 
                0.5 + smooth * 0.5  // 内部：0.5到1.0
            else 
                0.5 - smooth * 0.5; // 外部：0.5到0.0
            
            // 结合原有的覆盖度和MSDF覆盖度，小字体降低MSDF的权重
            const msdf_weight: f32 = if (is_small_font) 0.2 else 0.3;
            const base_weight: f32 = 1.0 - msdf_weight;
            coverage = coverage * base_weight + msdf_coverage * msdf_weight;
        } else {
            // 在平滑范围外，保持原有覆盖度
            // 如果距离足够远，直接使用距离场结果
            if (signed_distance > msdf_range) {
                coverage = 1.0;
            } else if (signed_distance < -msdf_range) {
                coverage = 0.0;
            }
        }
        
        return @max(0.0, @min(1.0, coverage));
    }

    /// 应用字体Hinting（字体提示）
    /// Hinting用于在低分辨率下将字形坐标对齐到像素网格，提高清晰度
    /// 
    /// 参数：
    /// - coord: 原始坐标
    /// - font_size: 字体大小
    /// 
    /// 返回：对齐后的坐标
    /// 
    /// 实现说明：
    /// - 对于小尺寸字体（< 20px），将坐标对齐到最近的像素边界
    /// - 对于中等尺寸字体（20-40px），使用轻微对齐
    /// - 对于大尺寸字体（> 40px），不应用hinting（保持平滑）
    fn applyHinting(_: *Self, coord: f32, font_size: f32) f32 {
        // 如果字体很大，不需要hinting（保持平滑）
        if (font_size > 40.0) {
            return coord;
        }
        
        // 对于小尺寸字体，应用grid fitting（网格对齐）
        if (font_size < 20.0) {
            // 强对齐：对齐到最近的像素边界
            return @round(coord);
        } else {
            // 中等尺寸：轻微对齐，使用0.5像素的阈值
            const rounded = @round(coord);
            const diff = @abs(coord - rounded);
            // 如果距离像素边界很近（< 0.3像素），对齐到边界
            if (diff < 0.3) {
                return rounded;
            }
            // 否则保持原坐标（保持平滑）
            return coord;
        }
    }

    const Point = struct {
        x: f32,
        y: f32,
    };
};
