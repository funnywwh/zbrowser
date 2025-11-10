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

    /// 渲染参数配置（可调整以优化字体渲染效果）
    const RenderParams = struct {
        /// MSDF范围（像素）：控制边缘平滑过渡的范围
        /// 较小值：更精确的边缘，笔画更清晰，但可能略硬
        /// 较大值：更平滑的边缘，但可能过度平滑导致笔画变粗
        /// 推荐范围：0.5 - 1.0
        const msdf_range: f32 = 1.0;

        /// 边缘覆盖度：边缘像素的最小覆盖度
        /// 较小值：边缘更柔和，但可能模糊
        /// 较大值：边缘更清晰，笔画更粗
        /// 推荐范围：0.6 - 0.9
        const edge_coverage: f32 = 0.3;

        /// 是否启用Hinting
        /// true：启用hinting，提高小字体清晰度，但可能导致粗细不均匀
        /// false：禁用hinting，保持原始精度，确保一致性
        const enable_hinting: bool = true;

        /// Hinting强度：根据字号动态调整Hinting强度
        /// 小字号（<20px）下减弱Hinting强度，避免过度网格对齐
        /// 范围：0.0 - 1.0，1.0表示完全对齐，0.5表示50%强度
        const hinting_strength: f32 = 0.5;

        /// 小字号阈值：小于此值的字号使用减弱的Hinting强度
        const small_font_threshold: f32 = 20.0;

        /// 是否启用Gamma校正
        /// true：应用sRGB Gamma校正（2.2），改善视觉感知亮度
        /// false：使用线性空间，可能导致暗部笔画对比度不足
        const enable_gamma_correction: bool = true;

        /// Gamma值：用于sRGB校正
        const gamma: f32 = 2.2;
    };

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

                            // 应用字体Hinting（只对端点应用，保持曲线形状一致）
                            // 控制点不应用hinting，避免曲线形状不一致
                            if (!prev_point.is_control) {
                                prev_px = self.applyHinting(prev_px, font_size);
                                prev_py = self.applyHinting(prev_py, font_size);
                            }
                            if (!next_point.is_control) {
                                next_px = self.applyHinting(next_px, font_size);
                                next_py = self.applyHinting(next_py, font_size);
                            }

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
    /// 使用非零填充规则（non-zero winding rule）：根据路径方向决定填充区域
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

            // 计算与所有轮廓的交点（使用非零填充规则）
            // 存储交点和方向
            const Intersection = struct {
                x: f32,
                direction: i32, // +1 表示从下到上，-1 表示从上到下
            };
            var intersections = std.ArrayList(Intersection){};
            defer intersections.deinit(std.heap.page_allocator);

            // 遍历每个轮廓
            var contour_start: usize = 0;
            var contour_idx: usize = 0;
            while (contour_idx < contour_end_points.len) : (contour_idx += 1) {
                const contour_end = contour_end_points[contour_idx];

                // 计算当前轮廓与扫描线的交点（使用非零填充规则）
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
                            // 计算方向：从下到上为+1，从上到下为-1
                            const direction: i32 = if (p1.y < p2.y) 1 else -1;
                            intersections.append(std.heap.page_allocator, Intersection{ .x = x, .direction = direction }) catch continue;
                        }
                    }
                }

                contour_start = contour_end + 1;
            }

            // 对交点按x坐标排序
            std.mem.sort(Intersection, intersections.items, {}, struct {
                fn lessThan(_: void, a: Intersection, b: Intersection) bool {
                    return a.x < b.x;
                }
            }.lessThan);

            // 使用非零填充规则：从左边开始，累加方向值，当累加值不为0时填充
            var winding: i32 = 0;
            var fill_start_x: ?f32 = null;

            var j: usize = 0;
            while (j < intersections.items.len) : (j += 1) {
                const intersection = intersections.items[j];
                const prev_winding = winding;
                winding += intersection.direction;

                // 当winding从0变为非0时，开始填充区间
                if (prev_winding == 0 and winding != 0) {
                    fill_start_x = intersection.x;
                }
                // 当winding从非0变为0时，结束填充区间
                else if (prev_winding != 0 and winding == 0) {
                    if (fill_start_x) |x1| {
                        const x2 = intersection.x;

                        // 填充从x1到x2的区间（非零填充规则）
                        // 使用精确的像素范围，确保边缘抗锯齿
                        // 扩展范围基于MSDF范围（1.0像素），确保覆盖所有需要抗锯齿的像素
                        const start_x = @as(i32, @intFromFloat(x1)) - 1;
                        const end_x = @as(i32, @intFromFloat(x2)) + 1;

                        var px = start_x;
                        while (px < end_x) : (px += 1) {
                            // 检查像素是否在画布范围内
                            if (px < 0 or px >= @as(i32, @intCast(width))) continue;

                            const pixel_x = @as(f32, @floatFromInt(px)) + 0.5;

                            // 使用统一的覆盖度计算，确保字体粗细一致
                            // 关键改进：使用更精确的边缘检测，确保相同位置总是产生相同的覆盖度
                            var coverage = self.calculateCoverageWithMSDF(pixel_x, y, x1, x2, font_size);

                            // 应用Gamma校正（如果启用）
                            // Gamma校正将线性空间转换为感知空间，改善视觉感知亮度
                            // 这可以解决暗部笔画对比度不足的问题
                            if (RenderParams.enable_gamma_correction) {
                                // sRGB Gamma校正：coverage^(1/gamma)
                                // 线性空间coverage转换为感知空间
                                const gamma = RenderParams.gamma;
                                coverage = std.math.pow(f32, coverage, 1.0 / gamma);
                            }

                            // 只有当覆盖度大于0时才渲染
                            if (coverage > 0.0) {
                                const index = (@as(usize, @intCast(scanline)) * width + @as(usize, @intCast(px))) * 4;
                                if (index + 3 < pixels.len) {
                                    const alpha = @as(f32, @floatFromInt(color.a)) / 255.0;
                                    const final_alpha = coverage * alpha;
                                    const final_alpha_u8 = @as(u8, @intFromFloat(final_alpha * 255.0));

                                    // 如果像素已有内容，进行alpha混合
                                    // 使用叠加混合，但限制最大alpha值避免过度叠加
                                    if (pixels[index + 3] > 0) {
                                        const existing_alpha = @as(f32, @floatFromInt(pixels[index + 3])) / 255.0;
                                        // 使用叠加混合，但限制最大alpha值为1.0
                                        const combined_alpha = @min(1.0, existing_alpha + final_alpha * (1.0 - existing_alpha));

                                        if (combined_alpha > 0.0) {
                                            const blend_factor = final_alpha / combined_alpha;

                                            // 使用统一的覆盖度混合RGB通道，确保一致性
                                            pixels[index] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(pixels[index])) * (1.0 - blend_factor) + @as(f32, @floatFromInt(color.r)) * blend_factor));
                                            pixels[index + 1] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(pixels[index + 1])) * (1.0 - blend_factor) + @as(f32, @floatFromInt(color.g)) * blend_factor));
                                            pixels[index + 2] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(pixels[index + 2])) * (1.0 - blend_factor) + @as(f32, @floatFromInt(color.b)) * blend_factor));
                                            pixels[index + 3] = @as(u8, @intFromFloat(combined_alpha * 255.0));
                                        }
                                    } else {
                                        // 直接设置像素，使用统一的覆盖度
                                        pixels[index] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(color.r)) * final_alpha));
                                        pixels[index + 1] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(color.g)) * final_alpha));
                                        pixels[index + 2] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(color.b)) * final_alpha));
                                        pixels[index + 3] = final_alpha_u8;
                                    }
                                }
                            }
                        }

                        fill_start_x = null; // 重置填充起始点
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

    /// 计算像素的覆盖度（使用精确的距离场方法）
    /// 使用统一的距离场方法获得一致且平滑的边缘
    /// 关键：确保相同位置总是产生相同的覆盖度，避免笔画粗细不均匀
    /// font_size: 字体大小（像素），保留用于未来扩展
    fn calculateCoverageWithMSDF(_: *Self, pixel_x: f32, pixel_y: f32, x1: f32, x2: f32, font_size: f32) f32 {
        _ = pixel_y; // Y坐标用于未来扩展
        _ = font_size; // 字体大小保留用于未来扩展

        // 使用统一的距离场方法，确保相同距离产生相同的覆盖度
        // 这是修复字体粗细不均匀的关键：使用纯距离场计算，避免采样不一致
        const center_x = pixel_x;

        // 判断是否在轮廓内部（使用精确的边界检查）
        // 注意：使用 >= 和 < 确保边界的一致性，与扫描线算法保持一致
        const is_inside = center_x >= x1 and center_x < x2;

        // 计算到边缘的距离（使用精确的距离计算）
        // 关键：使用像素中心到边缘的精确距离，确保一致性
        const dist_to_left = center_x - x1;
        const dist_to_right = x2 - center_x;

        // 计算到最近边缘的距离
        const min_dist_to_edge = @min(@abs(dist_to_left), @abs(dist_to_right));

        // 使用可配置的MSDF范围，确保一致性
        // 使用RenderParams中的配置值，方便调整优化
        const msdf_range = RenderParams.msdf_range;
        const edge_coverage = RenderParams.edge_coverage;

        // 使用统一的smoothstep函数计算覆盖度
        // 这确保了相同距离总是产生相同的覆盖度
        // 关键优化：使用可配置的参数，确保笔画粗细一致
        if (is_inside) {
            // 内部像素
            if (min_dist_to_edge >= msdf_range) {
                // 距离边缘足够远，完全覆盖
                return 1.0;
            } else {
                // 在边缘附近，使用smoothstep平滑过渡
                // 使用更精确的过渡，确保笔画粗细一致
                const t = min_dist_to_edge / msdf_range; // 归一化到[0, 1]
                const t2 = t * t;
                const smooth = t2 * (3.0 - 2.0 * t); // smoothstep函数
                // 覆盖度从edge_coverage（边缘，t=0）到1.0（内部，t=1）
                // 使用可配置的边缘覆盖度，确保笔画更清晰且一致
                return edge_coverage + smooth * (1.0 - edge_coverage);
            }
        } else {
            // 外部像素
            if (min_dist_to_edge >= msdf_range) {
                // 距离边缘足够远，完全不覆盖
                return 0.0;
            } else {
                // 在边缘附近，使用smoothstep平滑过渡
                const t = min_dist_to_edge / msdf_range; // 归一化到[0, 1]
                const t2 = t * t;
                const smooth = t2 * (3.0 - 2.0 * t); // smoothstep函数
                // 覆盖度从edge_coverage（边缘，t=0）到0.0（外部，t=1）
                // 使用可配置的边缘覆盖度，确保笔画更清晰且一致
                return edge_coverage * (1.0 - smooth);
            }
        }
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
    /// - 根据RenderParams.enable_hinting配置决定是否启用Hinting
    /// - 禁用Hinting：保持原坐标不变，确保所有位置使用相同的精度
    /// - 启用Hinting：根据字号动态调整Hinting强度，小字号下减弱对齐，避免过度网格化
    /// - 引入亚像素偏移（+0.5），提高对齐精度
    fn applyHinting(_: *Self, coord: f32, font_size: f32) f32 {
        // 根据配置决定是否启用Hinting
        if (RenderParams.enable_hinting) {
            // 根据字号动态调整Hinting强度
            // 小字号（<20px）下减弱Hinting强度，避免过度网格对齐导致笔画粗细不均
            const hinting_amount = if (font_size < RenderParams.small_font_threshold)
                RenderParams.hinting_strength
            else
                1.0;

            // 应用Hinting强度：使用线性插值在原始坐标和对齐坐标之间
            // 引入亚像素偏移（+0.5），提高对齐精度
            const rounded = @round(coord + 0.5);
            const original = coord;

            // 线性插值：hinting_amount=0.5时，坐标在原始和对齐之间取中点
            // 这样可以减少过度对齐，同时保持一定的清晰度
            return original + (rounded - original) * hinting_amount;
        } else {
            // 禁用Hinting：保持原坐标不变
            // 这确保了所有位置的坐标都保持原始精度，避免对齐导致的不一致
            // 这是修复笔画粗细不均匀的关键：避免hinting导致的不同位置对齐不一致
            return coord;
        }
    }

    const Point = struct {
        x: f32,
        y: f32,
    };
};
