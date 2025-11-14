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
            .floats = std.ArrayList(*box.LayoutBox){},
            .clear_elements = std.ArrayList(*box.LayoutBox){},
        };
    }

    /// 清理BFC
    pub fn deinit(self: *BlockFormattingContext) void {
        self.floats.deinit(self.base.allocator);
        self.clear_elements.deinit(self.base.allocator);
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
            .line_boxes = std.ArrayList(LineBox){},
        };
    }

    /// 清理IFC
    pub fn deinit(self: *InlineFormattingContext) void {
        // 清理所有行框中的inline_boxes
        // 注意：必须使用base.allocator，因为IFC初始化时使用的是container的allocator
        // 而container的allocator就是base.allocator（在init中设置的）
        // 但是，在createLineBox和append时使用的是layout_box.allocator，应该与base.allocator相同
        const allocator = self.base.allocator;
        for (self.line_boxes.items) |*line_box| {
            // 必须清理inline_boxes，即使capacity为0（因为可能已经分配了内存）
            line_box.inline_boxes.deinit(allocator);
        }
        // 必须清理line_boxes，即使capacity为0（因为可能已经分配了内存）
        self.line_boxes.deinit(allocator);
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

/// 清理formatting_context（从*anyopaque转换并清理）
/// 这是一个辅助函数，用于从LayoutBox中清理formatting_context
/// 根据context_type来判断具体类型并进行清理
pub fn deinitFormattingContext(ctx_ptr: *anyopaque, allocator: std.mem.Allocator) void {
    // 先转换为FormattingContext基类指针，以访问context_type
    const base_ptr: *FormattingContext = @ptrCast(@alignCast(ctx_ptr));
    
    // 根据context_type判断具体类型并清理
    switch (base_ptr.context_type) {
        .inline_element => {
            // 转换为InlineFormattingContext并清理
            const ifc: *InlineFormattingContext = @ptrCast(@alignCast(ctx_ptr));
            ifc.deinit();
            allocator.destroy(ifc);
        },
        .block => {
            // 转换为BlockFormattingContext并清理
            const bfc: *BlockFormattingContext = @ptrCast(@alignCast(ctx_ptr));
            bfc.deinit();
            allocator.destroy(bfc);
        },
        .flex, .grid => {
            // TODO: 实现Flex和Grid格式化上下文的清理
            // 暂时只释放内存（使用FormattingContext作为类型，因为flex和grid都继承自它）
            const ptr: *FormattingContext = @ptrCast(@alignCast(ctx_ptr));
            allocator.destroy(ptr);
        },
    }
}
