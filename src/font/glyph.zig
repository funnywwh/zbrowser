const std = @import("std");
const backend = @import("backend");
const ttf_module = @import("ttf");

/// 字形渲染器
/// 负责将字形轮廓转换为像素
pub const GlyphRenderer = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 初始化字形渲染器
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// 清理字形渲染器
    pub fn deinit(self: *Self) void {
        _ = self;
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
        glyph: *const ttf_module.TtfParser.Glyph,
        pixels: []u8,
        width: u32,
        height: u32,
        x: f32,
        y: f32,
        font_size: f32,
        units_per_em: u16,
        color: backend.Color,
    ) void {
        if (glyph.points.items.len == 0) {
            // 空字形，不渲染
            return;
        }

        // 边界检查：units_per_em 不能为 0
        if (units_per_em == 0) {
            // units_per_em 为 0 时，无法计算缩放因子，不渲染
            return;
        }

        // 计算缩放因子
        const scale = font_size / @as(f32, @floatFromInt(units_per_em));

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
                const px = x + @as(f32, @floatFromInt(point.x)) * scale;
                const py = y - @as(f32, @floatFromInt(point.y)) * scale;

                if (point.is_control) {
                    if (i > 0 and i + 1 < glyph.points.items.len) {
                        const prev_point = glyph.points.items[i - 1];
                        const next_point = glyph.points.items[i + 1];
                        const prev_px = x + @as(f32, @floatFromInt(prev_point.x)) * scale;
                        const prev_py = y - @as(f32, @floatFromInt(prev_point.y)) * scale;
                        const next_px = x + @as(f32, @floatFromInt(next_point.x)) * scale;
                        const next_py = y - @as(f32, @floatFromInt(next_point.y)) * scale;

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
                    const px = x + @as(f32, @floatFromInt(point.x)) * scale;
                    const py = y - @as(f32, @floatFromInt(point.y)) * scale; // Y轴翻转：字体坐标系y向上，屏幕坐标系y向下

                    if (point.is_control) {
                        // 控制点：需要与前一个点和后一个点形成二次贝塞尔曲线
                        const prev_i = if (i > contour_start) i - 1 else contour_end;
                        const next_i = if (i < contour_end) i + 1 else contour_start;
                        
                        if (prev_i < glyph.points.items.len and next_i < glyph.points.items.len) {
                            const prev_point = glyph.points.items[prev_i];
                            const next_point = glyph.points.items[next_i];
                            const prev_px = x + @as(f32, @floatFromInt(prev_point.x)) * scale;
                            const prev_py = y - @as(f32, @floatFromInt(prev_point.y)) * scale;
                            const next_px = x + @as(f32, @floatFromInt(next_point.x)) * scale;
                            const next_py = y - @as(f32, @floatFromInt(next_point.y)) * scale;

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
        self.fillOutline(pixel_points.items, pixel_contour_end_points.items, pixels, width, height, color);
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

        // 扩展扫描范围以处理边缘抗锯齿
        // 注意：不要过早裁剪，允许扫描超出画布边界（但会在像素写入时检查）
        const start_scanline = @as(i32, @intFromFloat(min_y)) - 2;
        const end_scanline = @as(i32, @intFromFloat(max_y)) + 3;

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
                const start_x = @as(i32, @intFromFloat(x1)) - 2;
                const end_x = @as(i32, @intFromFloat(x2)) + 3;

                var px = start_x;
                while (px < end_x) : (px += 1) {
                    // 检查像素是否在画布范围内
                    if (px < 0 or px >= @as(i32, @intCast(width))) continue;
                    
                    const pixel_x = @as(f32, @floatFromInt(px)) + 0.5;
                    const coverage = self.calculateCoverage(pixel_x, y, x1, x2);
                    
                    if (coverage > 0.0) {
                        const index = (@as(usize, @intCast(scanline)) * width + @as(usize, @intCast(px))) * 4;
                        if (index + 3 < pixels.len) {
                            // 使用alpha混合
                            const alpha = @as(f32, @floatFromInt(color.a)) / 255.0;
                            const final_alpha = coverage * alpha;
                            const final_alpha_u8 = @as(u8, @intFromFloat(final_alpha * 255.0));
                            
                            // 如果像素已有内容，进行alpha混合
                            if (pixels[index + 3] > 0) {
                                const existing_alpha = @as(f32, @floatFromInt(pixels[index + 3])) / 255.0;
                                const combined_alpha = existing_alpha + final_alpha * (1.0 - existing_alpha);
                                
                                if (combined_alpha > 0.0) {
                                    const t = final_alpha / combined_alpha;
                                    pixels[index] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(pixels[index])) * (1.0 - t) + @as(f32, @floatFromInt(color.r)) * t));
                                    pixels[index + 1] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(pixels[index + 1])) * (1.0 - t) + @as(f32, @floatFromInt(color.g)) * t));
                                    pixels[index + 2] = @as(u8, @intFromFloat(@as(f32, @floatFromInt(pixels[index + 2])) * (1.0 - t) + @as(f32, @floatFromInt(color.b)) * t));
                                    pixels[index + 3] = @as(u8, @intFromFloat(combined_alpha * 255.0));
                                }
                            } else {
                                // 直接设置像素
                                pixels[index] = color.r;
                                pixels[index + 1] = color.g;
                                pixels[index + 2] = color.b;
                                pixels[index + 3] = final_alpha_u8;
                            }
                        }
                    }
                }
            }
        }
    }

    /// 计算像素的覆盖度（用于抗锯齿）
    /// 使用子像素采样和距离场方法获得更平滑的边缘
    fn calculateCoverage(_: *Self, pixel_x: f32, pixel_y: f32, x1: f32, x2: f32) f32 {
        const pixel_left = pixel_x - 0.5;
        const pixel_top = pixel_y - 0.5;
        
        // 使用4x4子像素采样（16个采样点）获得更精确的覆盖度
        const sub_samples = 4;
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
        
        // 使用距离场方法增强边缘平滑度
        const center_x = pixel_x;
        const dist_to_left = center_x - x1;
        const dist_to_right = x2 - center_x;
        const min_dist = @min(@abs(dist_to_left), @abs(dist_to_right));
        
        // 如果接近边缘，使用更平滑的过渡
        if (min_dist < 1.0) {
            // 使用改进的smoothstep函数，在边缘处提供更平滑的过渡
            const t = min_dist / 1.0;
            // 使用三次平滑函数：t^2 * (3 - 2t) 的改进版本
            const smooth = t * t * t * (t * (t * 6.0 - 15.0) + 10.0); // smootherstep函数
            // 在边缘处使用更低的覆盖度，提供更明显的抗锯齿效果
            if (center_x >= x1 and center_x < x2) {
                // 在轮廓内，边缘处覆盖度降低
                coverage = coverage * (0.4 + smooth * 0.6);
            } else {
                // 在轮廓外，使用平滑衰减
                coverage = coverage * (1.0 - smooth);
            }
        }
        
        return @max(0.0, @min(1.0, coverage));
    }

    const Point = struct {
        x: f32,
        y: f32,
    };
};
