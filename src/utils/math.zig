const std = @import("std");

/// 数学工具函数
/// 将值限制在min和max之间
pub fn clamp(val: f32, min: f32, max: f32) f32 {
    return @max(min, @min(max, val));
}

/// 线性插值
pub fn lerp(start: f32, end: f32, t: f32) f32 {
    return start + (end - start) * clamp(t, 0.0, 1.0);
}

/// 计算两点之间的距离
pub fn distance(x1: f32, y1: f32, x2: f32, y2: f32) f32 {
    const dx = x2 - x1;
    const dy = y2 - y1;
    return @sqrt(dx * dx + dy * dy);
}

/// 将角度转换为弧度
pub fn degToRad(degrees: f32) f32 {
    return degrees * std.math.pi / 180.0;
}

/// 将弧度转换为角度
pub fn radToDeg(radians: f32) f32 {
    return radians * 180.0 / std.math.pi;
}

/// 检查浮点数是否近似相等
pub fn approxEqual(a: f32, b: f32, epsilon: f32) bool {
    return @abs(a - b) < epsilon;
}
