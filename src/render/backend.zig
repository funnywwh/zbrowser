const std = @import("std");

/// 颜色（RGBA格式）
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    /// 创建颜色
    pub fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    /// 创建不透明颜色
    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }

    /// 转换为32位RGBA值
    pub fn toU32(self: Color) u32 {
        return (@as(u32, self.r) << 24) |
            (@as(u32, self.g) << 16) |
            (@as(u32, self.b) << 8) |
            @as(u32, self.a);
    }
};

/// 矩形
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    /// 创建矩形
    pub fn init(x: f32, y: f32, width: f32, height: f32) Rect {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }
};

/// 字体（简化实现）
pub const Font = struct {
    family: []const u8,
    size: f32,
    weight: FontWeight = .normal,
    style: FontStyle = .normal,

    pub const FontWeight = enum {
        normal,
        bold,
        lighter, // 细体（比normal更细）
    };

    pub const FontStyle = enum {
        normal,
        italic,
    };
};

/// 图像（简化实现）
pub const Image = struct {
    width: u32,
    height: u32,
    data: []const u8, // RGBA格式
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Image) void {
        self.allocator.free(self.data);
    }
};

/// 渲染后端接口
/// 使用VTable模式实现多态，支持CPU和GPU两种后端
pub const RenderBackend = struct {
    vtable: *const VTable,
    data: *anyopaque,

    pub const VTable = struct {
        // 基础绘制操作
        fillRect: *const fn (self: *RenderBackend, rect: Rect, color: Color) void,
        strokeRect: *const fn (self: *RenderBackend, rect: Rect, color: Color, width: f32) void,
        fillText: *const fn (self: *RenderBackend, text: []const u8, x: f32, y: f32, font: Font, color: Color) void,
        drawImage: *const fn (self: *RenderBackend, image: *Image, src_rect: Rect, dst_rect: Rect) void,

        // 路径绘制
        beginPath: *const fn (self: *RenderBackend) void,
        moveTo: *const fn (self: *RenderBackend, x: f32, y: f32) void,
        lineTo: *const fn (self: *RenderBackend, x: f32, y: f32) void,
        arc: *const fn (self: *RenderBackend, x: f32, y: f32, radius: f32, start: f32, end: f32) void,
        closePath: *const fn (self: *RenderBackend) void,
        fill: *const fn (self: *RenderBackend, color: Color) void,
        stroke: *const fn (self: *RenderBackend, color: Color, width: f32) void,

        // 变换和状态
        save: *const fn (self: *RenderBackend) void,
        restore: *const fn (self: *RenderBackend) void,
        translate: *const fn (self: *RenderBackend, x: f32, y: f32) void,
        rotate: *const fn (self: *RenderBackend, angle: f32) void,
        scale: *const fn (self: *RenderBackend, x: f32, y: f32) void,

        // 裁剪和混合
        clip: *const fn (self: *RenderBackend, rect: Rect) void,
        setGlobalAlpha: *const fn (self: *RenderBackend, alpha: f32) void,

        // 获取渲染结果
        getPixels: *const fn (self: *RenderBackend, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8,
        getWidth: *const fn (self: *const RenderBackend) u32,
        getHeight: *const fn (self: *const RenderBackend) u32,

        // 清理
        deinit: *const fn (self: *RenderBackend) void,
    };

    /// 调用fillRect
    pub fn fillRect(self: *RenderBackend, rect: Rect, color: Color) void {
        self.vtable.fillRect(self, rect, color);
    }

    /// 调用strokeRect
    pub fn strokeRect(self: *RenderBackend, rect: Rect, color: Color, width: f32) void {
        self.vtable.strokeRect(self, rect, color, width);
    }

    /// 调用fillText
    pub fn fillText(self: *RenderBackend, text: []const u8, x: f32, y: f32, font: Font, color: Color) void {
        self.vtable.fillText(self, text, x, y, font, color);
    }

    /// 调用drawImage
    pub fn drawImage(self: *RenderBackend, image: *Image, src_rect: Rect, dst_rect: Rect) void {
        self.vtable.drawImage(self, image, src_rect, dst_rect);
    }

    /// 调用beginPath
    pub fn beginPath(self: *RenderBackend) void {
        self.vtable.beginPath(self);
    }

    /// 调用moveTo
    pub fn moveTo(self: *RenderBackend, x: f32, y: f32) void {
        self.vtable.moveTo(self, x, y);
    }

    /// 调用lineTo
    pub fn lineTo(self: *RenderBackend, x: f32, y: f32) void {
        self.vtable.lineTo(self, x, y);
    }

    /// 调用arc
    pub fn arc(self: *RenderBackend, x: f32, y: f32, radius: f32, start: f32, end: f32) void {
        self.vtable.arc(self, x, y, radius, start, end);
    }

    /// 调用closePath
    pub fn closePath(self: *RenderBackend) void {
        self.vtable.closePath(self);
    }

    /// 调用fill
    pub fn fill(self: *RenderBackend, color: Color) void {
        self.vtable.fill(self, color);
    }

    /// 调用stroke
    pub fn stroke(self: *RenderBackend, color: Color, width: f32) void {
        self.vtable.stroke(self, color, width);
    }

    /// 调用save
    pub fn save(self: *RenderBackend) void {
        self.vtable.save(self);
    }

    /// 调用restore
    pub fn restore(self: *RenderBackend) void {
        self.vtable.restore(self);
    }

    /// 调用translate
    pub fn translate(self: *RenderBackend, x: f32, y: f32) void {
        self.vtable.translate(self, x, y);
    }

    /// 调用rotate
    pub fn rotate(self: *RenderBackend, angle: f32) void {
        self.vtable.rotate(self, angle);
    }

    /// 调用scale
    pub fn scale(self: *RenderBackend, x: f32, y: f32) void {
        self.vtable.scale(self, x, y);
    }

    /// 调用clip
    pub fn clip(self: *RenderBackend, rect: Rect) void {
        self.vtable.clip(self, rect);
    }

    /// 调用setGlobalAlpha
    pub fn setGlobalAlpha(self: *RenderBackend, alpha: f32) void {
        self.vtable.setGlobalAlpha(self, alpha);
    }

    /// 调用getPixels
    pub fn getPixels(self: *RenderBackend, allocator: std.mem.Allocator) ![]u8 {
        return self.vtable.getPixels(self, allocator);
    }

    /// 调用getWidth
    pub fn getWidth(self: *const RenderBackend) u32 {
        return self.vtable.getWidth(self);
    }

    /// 调用getHeight
    pub fn getHeight(self: *const RenderBackend) u32 {
        return self.vtable.getHeight(self);
    }

    /// 调用deinit
    pub fn deinit(self: *RenderBackend) void {
        self.vtable.deinit(self);
    }
};
