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

        // 将控制点转换为曲线上的点
        var i: usize = 0;
        while (i < glyph.points.items.len) : (i += 1) {
            const point = glyph.points.items[i];
            const px = x + @as(f32, @floatFromInt(point.x)) * scale;
            const py = y - @as(f32, @floatFromInt(point.y)) * scale; // Y轴翻转

            if (point.is_control) {
                // 控制点：需要与前一个点和后一个点形成二次贝塞尔曲线
                if (i > 0 and i + 1 < glyph.points.items.len) {
                    const prev_point = glyph.points.items[i - 1];
                    const next_point = glyph.points.items[i + 1];
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

        // 使用扫描线算法填充轮廓
        self.fillOutline(pixel_points.items, pixels, width, height, color);
    }

    /// 使用扫描线算法填充轮廓
    fn fillOutline(
        _: *Self,
        points: []const Point,
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

        const start_scanline = @max(0, @as(i32, @intFromFloat(min_y)));
        const end_scanline = @min(@as(i32, @intCast(height)), @as(i32, @intFromFloat(max_y)) + 1);

        // 对每条扫描线，计算与轮廓的交点
        var scanline = start_scanline;
        while (scanline < end_scanline) : (scanline += 1) {
            const y = @as(f32, @floatFromInt(scanline)) + 0.5; // 扫描线中心

            // 计算与轮廓的交点
            var intersections = std.ArrayList(f32){};
            defer intersections.deinit(std.heap.page_allocator);

            var i: usize = 0;
            while (i < points.len) : (i += 1) {
                const p1 = points[i];
                const p2 = points[(i + 1) % points.len];

                // 检查线段是否与扫描线相交
                if ((p1.y <= y and p2.y > y) or (p1.y > y and p2.y <= y)) {
                    if (p1.y != p2.y) {
                        const t = (y - p1.y) / (p2.y - p1.y);
                        const x = p1.x + t * (p2.x - p1.x);
                        intersections.append(std.heap.page_allocator, x) catch continue;
                    }
                }
            }

            // 对交点排序
            std.mem.sort(f32, intersections.items, {}, comptime std.sort.asc(f32));

            // 填充交点之间的区域
            var j: usize = 0;
            while (j + 1 < intersections.items.len) : (j += 2) {
                const x1 = intersections.items[j];
                const x2 = intersections.items[j + 1];

                const start_x = @max(0, @as(i32, @intFromFloat(x1)));
                const end_x = @min(@as(i32, @intCast(width)), @as(i32, @intFromFloat(x2)) + 1);

                var px = start_x;
                while (px < end_x) : (px += 1) {
                    const index = (@as(usize, @intCast(scanline)) * width + @as(usize, @intCast(px))) * 4;
                    if (index + 3 < pixels.len) {
                        pixels[index] = color.r;
                        pixels[index + 1] = color.g;
                        pixels[index + 2] = color.b;
                        pixels[index + 3] = color.a;
                    }
                }
            }
        }
    }

    const Point = struct {
        x: f32,
        y: f32,
    };
};
