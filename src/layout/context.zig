const std = @import("std");
const box = @import("box");

/// 上下文类型
pub const ContextType = enum {
    block, // Block Formatting Context (BFC)
    inline_element, // Inline Formatting Context (IFC) - inline 是 Zig 关键字，使用 inline_element
    flex, // Flex Formatting Context (FFC)
    grid, // Grid Formatting Context (GFC)
};

/// 格式化上下文基类
pub const FormattingContext = struct {
    context_type: ContextType,
    container: *box.LayoutBox,
    allocator: std.mem.Allocator,

    /// 清理格式化上下文
    pub fn deinit(self: *FormattingContext) void {
        _ = self;
    }
};

/// Block Formatting Context (BFC)
pub const BlockFormattingContext = struct {
    base: FormattingContext,

    /// 浮动元素列表
    floats: std.ArrayList(*box.LayoutBox),

    /// 清除浮动的元素
    clear_elements: std.ArrayList(*box.LayoutBox),

    /// 初始化BFC
    pub fn init(container: *box.LayoutBox, allocator: std.mem.Allocator) BlockFormattingContext {
        return .{
            .base = .{
                .context_type = .block,
                .container = container,
                .allocator = allocator,
            },
            .floats = std.ArrayList(*box.LayoutBox).init(allocator),
            .clear_elements = std.ArrayList(*box.LayoutBox).init(allocator),
        };
    }

    /// 清理BFC
    pub fn deinit(self: *BlockFormattingContext) void {
        self.floats.deinit();
        self.clear_elements.deinit();
    }
};

/// Inline Formatting Context (IFC)
pub const InlineFormattingContext = struct {
    base: FormattingContext,

    /// 行框列表
    line_boxes: std.ArrayList(LineBox),

    /// 初始化IFC
    pub fn init(container: *box.LayoutBox, allocator: std.mem.Allocator) InlineFormattingContext {
        return .{
            .base = .{
                .context_type = .inline_element,
                .container = container,
                .allocator = allocator,
            },
            .line_boxes = std.ArrayList(LineBox).init(allocator),
        };
    }

    /// 清理IFC
    pub fn deinit(self: *InlineFormattingContext) void {
        // 清理所有行框中的inline_boxes
        for (self.line_boxes.items) |*line_box| {
            line_box.inline_boxes.deinit();
        }
        self.line_boxes.deinit();
    }
};

/// 行框（Line Box）
pub const LineBox = struct {
    /// 行框位置和尺寸
    rect: box.Rect,

    /// 行内元素列表
    inline_boxes: std.ArrayList(*box.LayoutBox),

    /// 基线位置
    baseline: f32,

    /// 行高
    line_height: f32,
};
