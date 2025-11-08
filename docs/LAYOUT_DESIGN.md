# 布局引擎详细设计文档

## 1. 概述

布局引擎是浏览器渲染引擎的核心组件之一，负责根据CSS样式计算每个DOM元素在页面中的位置和尺寸。本设计文档详细描述了布局引擎的架构、数据结构和算法实现。

### 1.1 设计目标

1. **准确性**：严格遵循CSS规范，确保布局结果与Chrome浏览器一致
2. **完整性**：支持所有主流布局模式（Block、Inline、Flexbox、Grid、定位）
3. **性能**：高效的布局计算算法，支持复杂页面
4. **可维护性**：清晰的模块划分，易于扩展和维护

### 1.2 参考规范

- [CSS Box Model](https://www.w3.org/TR/CSS2/box.html)
- [CSS Display](https://www.w3.org/TR/CSS2/visuren.html)
- [CSS Positioning](https://www.w3.org/TR/CSS2/visuren.html#position)
- [CSS Flexible Box Layout](https://www.w3.org/TR/css-flexbox-1/)
- [CSS Grid Layout](https://www.w3.org/TR/css-grid-1/)
- Chrome最新版本的布局行为

## 2. 架构设计

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                    DOM树 + 样式树                      │
└────────────────────┬────────────────────────────────────┘
                     │
            ┌────────▼────────┐
            │   布局引擎       │
            │  - 盒模型计算    │
            │  - 布局上下文    │
            │  - 布局算法      │
            └────────┬─────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
┌───────▼────────┐      ┌─────────▼────────┐
│   布局树       │      │   布局结果       │
│  (Layout Tree) │      │  - 位置坐标      │
│                │      │  - 尺寸信息      │
└────────────────┘      └──────────────────┘
```

### 2.2 模块划分

```
src/layout/
├── box.zig          # 盒模型计算
├── context.zig      # 布局上下文（BFC、IFC、FFC、GFC）
├── block.zig        # 块级布局
├── inline.zig       # 行内布局
├── flexbox.zig      # Flexbox布局
├── grid.zig         # Grid布局
├── position.zig     # 定位布局
├── float.zig        # 浮动布局
└── engine.zig       # 布局引擎主入口
```

## 3. 数据结构设计

### 3.1 盒模型（Box Model）

```zig
// src/layout/box.zig

/// CSS盒模型
pub const BoxModel = struct {
    /// 内容区域（content box）
    content: Rect,
    
    /// 内边距（padding）
    padding: Edges,
    
    /// 边框（border）
    border: Edges,
    
    /// 外边距（margin）
    margin: Edges,
    
    /// 盒模型类型（content-box 或 border-box）
    box_sizing: BoxSizing,
    
    /// 计算总尺寸（包含padding和border）
    pub fn totalSize(self: BoxModel) Size {
        const padding_size = self.padding.horizontal() + self.padding.vertical();
        const border_size = self.border.horizontal() + self.border.vertical();
        return switch (self.box_sizing) {
            .content_box => .{
                .width = self.content.width + padding_size.width + border_size.width,
                .height = self.content.height + padding_size.height + border_size.height,
            },
            .border_box => .{
                .width = self.content.width,
                .height = self.content.height,
            },
        };
    }
};

/// 矩形区域
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    
    pub fn contains(self: Rect, point: Point) bool {
        return point.x >= self.x and point.x < self.x + self.width and
               point.y >= self.y and point.y < self.y + self.height;
    }
    
    pub fn intersects(self: Rect, other: Rect) bool {
        return !(self.x + self.width <= other.x or
                 other.x + other.width <= self.x or
                 self.y + self.height <= other.y or
                 other.y + other.height <= self.y);
    }
};

/// 尺寸
pub const Size = struct {
    width: f32,
    height: f32,
};

/// 点坐标
pub const Point = struct {
    x: f32,
    y: f32,
};

/// 边距（上下左右）
pub const Edges = struct {
    top: f32,
    right: f32,
    bottom: f32,
    left: f32,
    
    pub fn horizontal(self: Edges) f32 {
        return self.left + self.right;
    }
    
    pub fn vertical(self: Edges) f32 {
        return self.top + self.bottom;
    }
};

/// 盒模型类型
pub const BoxSizing = enum {
    content_box,  // width/height 只包含内容
    border_box,   // width/height 包含内容+padding+border
};
```

### 3.2 布局框（Layout Box）

```zig
// src/layout/box.zig

/// 布局框（每个DOM元素对应一个布局框）
pub const LayoutBox = struct {
    /// 对应的DOM节点
    node: *dom.Node,
    
    /// 盒模型
    box_model: BoxModel,
    
    /// 显示类型（block, inline, flex, grid等）
    display: DisplayType,
    
    /// 定位类型（static, relative, absolute, fixed, sticky）
    position: PositionType,
    
    /// 浮动类型（none, left, right）
    float: FloatType,
    
    /// 子布局框列表
    children: std.ArrayList(*LayoutBox),
    
    /// 父布局框
    parent: ?*LayoutBox,
    
    /// 布局上下文（BFC、IFC、FFC、GFC）
    formatting_context: ?*FormattingContext,
    
    /// 是否已布局
    is_layouted: bool,
    
    allocator: std.mem.Allocator,
    
    pub fn init(node: *dom.Node, allocator: std.mem.Allocator) LayoutBox {
        return .{
            .node = node,
            .box_model = BoxModel{
                .content = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 },
                .padding = Edges{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
                .border = Edges{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
                .margin = Edges{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
                .box_sizing = .content_box,
            },
            .display = .block,
            .position = .static,
            .float = .none,
            .children = std.ArrayList(*LayoutBox).init(allocator),
            .parent = null,
            .formatting_context = null,
            .is_layouted = false,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *LayoutBox) void {
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit();
        if (self.formatting_context) |ctx| {
            ctx.deinit();
        }
    }
};

/// 显示类型
pub const DisplayType = enum {
    none,
    block,
    inline_block,
    inline,
    flex,
    inline_flex,
    grid,
    inline_grid,
    table,
    inline_table,
    table_row,
    table_cell,
    // ... 其他类型
};

/// 定位类型
pub const PositionType = enum {
    static,
    relative,
    absolute,
    fixed,
    sticky,
};

/// 浮动类型
pub const FloatType = enum {
    none,
    left,
    right,
};
```

### 3.3 布局上下文（Formatting Context）

```zig
// src/layout/context.zig

/// 格式化上下文基类
pub const FormattingContext = struct {
    context_type: ContextType,
    container: *LayoutBox,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *FormattingContext) void {
        _ = self;
    }
};

/// 上下文类型
pub const ContextType = enum {
    block,      // Block Formatting Context (BFC)
    inline,     // Inline Formatting Context (IFC)
    flex,       // Flex Formatting Context (FFC)
    grid,       // Grid Formatting Context (GFC)
};

/// Block Formatting Context (BFC)
pub const BlockFormattingContext = struct {
    base: FormattingContext,
    
    /// 浮动元素列表
    floats: std.ArrayList(*LayoutBox),
    
    /// 清除浮动的元素
    clear_elements: std.ArrayList(*LayoutBox),
    
    pub fn init(container: *LayoutBox, allocator: std.mem.Allocator) BlockFormattingContext {
        return .{
            .base = .{
                .context_type = .block,
                .container = container,
                .allocator = allocator,
            },
            .floats = std.ArrayList(*LayoutBox).init(allocator),
            .clear_elements = std.ArrayList(*LayoutBox).init(allocator),
        };
    }
    
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
    
    pub fn init(container: *LayoutBox, allocator: std.mem.Allocator) InlineFormattingContext {
        return .{
            .base = .{
                .context_type = .inline,
                .container = container,
                .allocator = allocator,
            },
            .line_boxes = std.ArrayList(LineBox).init(allocator),
        };
    }
    
    pub fn deinit(self: *InlineFormattingContext) void {
        self.line_boxes.deinit();
    }
};

/// 行框（Line Box）
pub const LineBox = struct {
    /// 行框位置和尺寸
    rect: Rect,
    
    /// 行内元素列表
    inline_boxes: std.ArrayList(*LayoutBox),
    
    /// 基线位置
    baseline: f32,
    
    /// 行高
    line_height: f32,
};
```

## 4. 布局算法

### 4.1 布局流程

```zig
// src/layout/engine.zig

/// 布局引擎
pub const LayoutEngine = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) LayoutEngine {
        return .{ .allocator = allocator };
    }
    
    /// 执行布局计算
    pub fn layout(self: *LayoutEngine, root: *dom.Node, stylesheets: []const css.parser.Stylesheet, viewport: Size) !*LayoutBox {
        // 1. 构建布局树
        const layout_tree = try self.buildLayoutTree(root, stylesheets);
        
        // 2. 计算盒模型
        try self.calculateBoxModel(layout_tree);
        
        // 3. 执行布局算法
        try self.layoutBox(layout_tree, viewport);
        
        return layout_tree;
    }
    
    /// 构建布局树（从DOM树和样式树构建）
    fn buildLayoutTree(self: *LayoutEngine, node: *dom.Node, stylesheets: []const css.parser.Stylesheet) !*LayoutBox {
        // 获取计算样式
        var cascade_engine = css.cascade.Cascade.init(self.allocator);
        const computed_style = try cascade_engine.computeStyle(node, stylesheets);
        defer computed_style.deinit();
        
        // 创建布局框
        const layout_box = try self.allocator.create(LayoutBox);
        layout_box.* = LayoutBox.init(node, self.allocator);
        
        // 设置显示类型和定位类型
        if (computed_style.getProperty("display")) |display_prop| {
            layout_box.display = try self.parseDisplayType(display_prop.value);
        }
        if (computed_style.getProperty("position")) |position_prop| {
            layout_box.position = try self.parsePositionType(position_prop.value);
        }
        if (computed_style.getProperty("float")) |float_prop| {
            layout_box.float = try self.parseFloatType(float_prop.value);
        }
        
        // 递归构建子节点
        var child = node.first_child;
        while (child) |c| {
            const child_layout_box = try self.buildLayoutTree(c, stylesheets);
            child_layout_box.parent = layout_box;
            try layout_box.children.append(child_layout_box);
            child = c.next_sibling;
        }
        
        return layout_box;
    }
    
    /// 计算盒模型
    fn calculateBoxModel(self: *LayoutEngine, layout_box: *LayoutBox) !void {
        // 获取计算样式
        // ... 从样式树获取样式值
        
        // 计算padding、border、margin
        // ... 解析CSS值并转换为像素值
        
        // 设置box_sizing
        // ... 根据box-sizing属性设置
    }
    
    /// 执行布局算法
    fn layoutBox(self: *LayoutEngine, layout_box: *LayoutBox, containing_block: Size) !void {
        // 根据display类型选择布局算法
        switch (layout_box.display) {
            .block => try self.layoutBlock(layout_box, containing_block),
            .inline => try self.layoutInline(layout_box, containing_block),
            .flex, .inline_flex => try self.layoutFlexbox(layout_box, containing_block),
            .grid, .inline_grid => try self.layoutGrid(layout_box, containing_block),
            else => {
                // 默认使用block布局
                try self.layoutBlock(layout_box, containing_block);
            },
        }
    }
};
```

### 4.2 块级布局（Block Layout）

```zig
// src/layout/block.zig

/// 块级布局算法
pub fn layoutBlock(layout_box: *LayoutBox, containing_block: Size) !void {
    // 1. 计算宽度
    const width = calculateBlockWidth(layout_box, containing_block);
    layout_box.box_model.content.width = width;
    
    // 2. 计算子元素布局
    var y: f32 = 0;
    var child = layout_box.children.items[0];
    var i: usize = 0;
    
    while (i < layout_box.children.items.len) : (i += 1) {
        child = layout_box.children.items[i];
        
        // 处理浮动
        if (child.float != .none) {
            try layoutFloat(child, layout_box, &y);
            continue;
        }
        
        // 清除浮动
        if (needsClear(child)) {
            y = try clearFloats(layout_box, y);
        }
        
        // 布局子元素
        try layoutBox(child, Size{ .width = width, .height = containing_block.height });
        
        // 计算位置
        child.box_model.content.x = layout_box.box_model.content.x;
        child.box_model.content.y = layout_box.box_model.content.y + y;
        
        // 更新y坐标
        y += child.box_model.totalSize().height;
    }
    
    // 3. 计算高度
    if (layout_box.box_model.content.height == 0) {
        layout_box.box_model.content.height = y;
    }
}

/// 计算块级元素宽度
fn calculateBlockWidth(layout_box: *LayoutBox, containing_block: Size) f32 {
    // 获取width样式值
    // 如果width是auto，使用containing_block的宽度
    // 如果width是百分比，计算百分比值
    // 如果width是固定值，使用固定值
    
    // 考虑margin、padding、border
    // 考虑box-sizing
    
    return containing_block.width; // 简化实现
}
```

### 4.3 行内布局（Inline Layout）

```zig
// src/layout/inline.zig

/// 行内布局算法
pub fn layoutInline(layout_box: *LayoutBox, containing_block: Size) !void {
    // 创建或获取IFC
    var ifc: ?*InlineFormattingContext = null;
    if (layout_box.formatting_context) |ctx| {
        if (ctx.context_type == .inline) {
            ifc = @ptrCast(*InlineFormattingContext, ctx);
        }
    }
    
    if (ifc == null) {
        const new_ifc = try layout_box.allocator.create(InlineFormattingContext);
        new_ifc.* = InlineFormattingContext.init(layout_box, layout_box.allocator);
        layout_box.formatting_context = @ptrCast(*FormattingContext, new_ifc);
        ifc = new_ifc;
    }
    
    // 创建行框
    var current_line = try createLineBox(ifc.?);
    var line_width: f32 = 0;
    var line_height: f32 = 0;
    
    // 布局行内元素
    for (layout_box.children.items) |child| {
        try layoutBox(child, containing_block);
        
        const child_width = child.box_model.totalSize().width;
        const child_height = child.box_model.totalSize().height;
        
        // 检查是否需要换行
        if (line_width + child_width > containing_block.width and line_width > 0) {
            // 完成当前行
            current_line.rect.width = line_width;
            current_line.rect.height = line_height;
            
            // 创建新行
            current_line = try createLineBox(ifc.?);
            line_width = 0;
            line_height = 0;
        }
        
        // 添加到当前行
        child.box_model.content.x = layout_box.box_model.content.x + line_width;
        child.box_model.content.y = layout_box.box_model.content.y + current_line.rect.y;
        try current_line.inline_boxes.append(child);
        
        line_width += child_width;
        line_height = @max(line_height, child_height);
    }
    
    // 完成最后一行
    current_line.rect.width = line_width;
    current_line.rect.height = line_height;
    
    // 计算容器高度
    var total_height: f32 = 0;
    for (ifc.?.line_boxes.items) |line| {
        total_height += line.rect.height;
    }
    layout_box.box_model.content.height = total_height;
}
```

### 4.4 Flexbox布局

```zig
// src/layout/flexbox.zig

/// Flexbox布局算法
pub fn layoutFlexbox(layout_box: *LayoutBox, containing_block: Size) !void {
    // 获取Flexbox属性
    const flex_direction = getFlexDirection(layout_box); // row, column, row-reverse, column-reverse
    const flex_wrap = getFlexWrap(layout_box); // nowrap, wrap, wrap-reverse
    const justify_content = getJustifyContent(layout_box);
    const align_items = getAlignItems(layout_box);
    const align_content = getAlignContent(layout_box);
    
    // 确定主轴和交叉轴
    const is_row = flex_direction == .row or flex_direction == .row_reverse;
    const main_axis = if (is_row) .horizontal else .vertical;
    const cross_axis = if (is_row) .vertical else .horizontal;
    
    // 计算可用空间
    const available_main = if (is_row) containing_block.width else containing_block.height;
    const available_cross = if (is_row) containing_block.height else containing_block.width;
    
    // 收集flex items
    var flex_items = std.ArrayList(FlexItem).init(layout_box.allocator);
    defer flex_items.deinit();
    
    for (layout_box.children.items) |child| {
        const flex_item = try createFlexItem(child, main_axis);
        try flex_items.append(flex_item);
    }
    
    // 计算flex items的基础尺寸
    for (flex_items.items) |*item| {
        try calculateFlexItemBaseSize(item, main_axis);
    }
    
    // 计算flex items的flex尺寸
    try calculateFlexItemFlexSize(&flex_items, available_main, main_axis);
    
    // 计算flex lines（如果允许换行）
    var flex_lines = std.ArrayList(FlexLine).init(layout_box.allocator);
    defer flex_lines.deinit();
    
    if (flex_wrap == .nowrap) {
        // 单行
        const line = try createFlexLine(&flex_items, available_main, main_axis);
        try flex_lines.append(line);
    } else {
        // 多行
        try createFlexLines(&flex_lines, &flex_items, available_main, main_axis);
    }
    
    // 计算交叉轴尺寸
    try calculateCrossAxisSize(&flex_lines, available_cross, cross_axis);
    
    // 应用对齐
    try applyJustifyContent(&flex_lines, justify_content, available_main, main_axis);
    try applyAlignItems(&flex_items, align_items, cross_axis);
    try applyAlignContent(&flex_lines, align_content, available_cross, cross_axis);
    
    // 计算最终位置
    var main_offset: f32 = 0;
    var cross_offset: f32 = 0;
    
    for (flex_lines.items) |*line| {
        for (line.items.items) |*item| {
            item.box.box_model.content.x = layout_box.box_model.content.x + main_offset;
            item.box.box_model.content.y = layout_box.box_model.content.y + cross_offset;
            main_offset += item.main_size;
        }
        cross_offset += line.cross_size;
        main_offset = 0;
    }
    
    // 计算容器尺寸
    layout_box.box_model.content.width = if (is_row) available_main else available_cross;
    layout_box.box_model.content.height = if (is_row) available_cross else available_main;
}

/// Flex Item
const FlexItem = struct {
    box: *LayoutBox,
    main_size: f32,
    cross_size: f32,
    flex_grow: f32,
    flex_shrink: f32,
    flex_basis: f32,
    min_main_size: f32,
    max_main_size: f32,
};

/// Flex Line
const FlexLine = struct {
    items: std.ArrayList(*FlexItem),
    main_size: f32,
    cross_size: f32,
};
```

### 4.5 Grid布局

```zig
// src/layout/grid.zig

/// Grid布局算法
pub fn layoutGrid(layout_box: *LayoutBox, containing_block: Size) !void {
    // 获取Grid属性
    const grid_template_rows = getGridTemplateRows(layout_box);
    const grid_template_columns = getGridTemplateColumns(layout_box);
    const grid_template_areas = getGridTemplateAreas(layout_box);
    const grid_auto_rows = getGridAutoRows(layout_box);
    const grid_auto_columns = getGridAutoColumns(layout_box);
    const gap_row = getGapRow(layout_box);
    const gap_column = getGapColumn(layout_box);
    
    // 解析grid模板
    const grid_tracks = try parseGridTracks(
        grid_template_rows,
        grid_template_columns,
        grid_template_areas,
        grid_auto_rows,
        grid_auto_columns,
        containing_block,
    );
    
    // 计算网格线位置
    var row_positions = std.ArrayList(f32).init(layout_box.allocator);
    defer row_positions.deinit();
    var column_positions = std.ArrayList(f32).init(layout_box.allocator);
    defer column_positions.deinit();
    
    try calculateGridLinePositions(&row_positions, &grid_tracks.rows, gap_row);
    try calculateGridLinePositions(&column_positions, &grid_tracks.columns, gap_column);
    
    // 布局grid items
    for (layout_box.children.items) |child| {
        const grid_area = try getGridArea(child);
        
        // 计算位置和尺寸
        const row_start = grid_area.row_start;
        const row_end = grid_area.row_end;
        const col_start = grid_area.col_start;
        const col_end = grid_area.col_end;
        
        const x = column_positions.items[col_start];
        const y = row_positions.items[row_start];
        const width = column_positions.items[col_end] - column_positions.items[col_start];
        const height = row_positions.items[row_end] - row_positions.items[row_start];
        
        // 布局子元素
        try layoutBox(child, Size{ .width = width, .height = height });
        
        // 设置位置
        child.box_model.content.x = layout_box.box_model.content.x + x;
        child.box_model.content.y = layout_box.box_model.content.y + y;
    }
    
    // 计算容器尺寸
    layout_box.box_model.content.width = column_positions.items[column_positions.items.len - 1];
    layout_box.box_model.content.height = row_positions.items[row_positions.items.len - 1];
}

/// Grid Tracks
const GridTracks = struct {
    rows: std.ArrayList(GridTrack),
    columns: std.ArrayList(GridTrack),
};

/// Grid Track
const GridTrack = struct {
    min_size: f32,
    max_size: f32,
    size_type: TrackSizeType, // fixed, min-content, max-content, auto, fr
    fr_value: f32, // 用于fr单位
};

/// Grid Area
const GridArea = struct {
    row_start: usize,
    row_end: usize,
    col_start: usize,
    col_end: usize,
};
```

### 4.6 定位布局（Positioning）

```zig
// src/layout/position.zig

/// 定位布局算法
pub fn layoutPositioned(layout_box: *LayoutBox, containing_block: Size) !void {
    switch (layout_box.position) {
        .static => {
            // static定位不需要特殊处理
            return;
        },
        .relative => {
            // relative定位：相对于正常流位置偏移
            try layoutRelative(layout_box, containing_block);
        },
        .absolute, .fixed => {
            // absolute/fixed定位：相对于包含块定位
            try layoutAbsolute(layout_box, containing_block);
        },
        .sticky => {
            // sticky定位：在滚动容器中粘性定位
            try layoutSticky(layout_box, containing_block);
        },
    }
}

/// Relative定位
fn layoutRelative(layout_box: *LayoutBox, containing_block: Size) !void {
    // 先按正常流布局
    try layoutBox(layout_box, containing_block);
    
    // 应用偏移
    const top = getPositionValue(layout_box, "top");
    const right = getPositionValue(layout_box, "right");
    const bottom = getPositionValue(layout_box, "bottom");
    const left = getPositionValue(layout_box, "left");
    
    if (top) |t| {
        layout_box.box_model.content.y += t;
    }
    if (left) |l| {
        layout_box.box_model.content.x += l;
    }
    // right和bottom需要特殊处理
}

/// Absolute/Fixed定位
fn layoutAbsolute(layout_box: *LayoutBox, containing_block: Size) !void {
    // 从正常流中移除
    // 计算位置
    const top = getPositionValue(layout_box, "top");
    const right = getPositionValue(layout_box, "right");
    const bottom = getPositionValue(layout_box, "bottom");
    const left = getPositionValue(layout_box, "left");
    
    // 计算宽度和高度
    var width: ?f32 = null;
    var height: ?f32 = null;
    
    if (getWidth(layout_box)) |w| {
        width = w;
    } else if (left != null and right != null) {
        width = containing_block.width - left.? - right.?;
    }
    
    if (getHeight(layout_box)) |h| {
        height = h;
    } else if (top != null and bottom != null) {
        height = containing_block.height - top.? - bottom.?;
    }
    
    // 布局子元素
    const size = Size{
        .width = width orelse containing_block.width,
        .height = height orelse containing_block.height,
    };
    try layoutBox(layout_box, size);
    
    // 设置位置
    layout_box.box_model.content.x = left orelse 0;
    layout_box.box_model.content.y = top orelse 0;
}
```

### 4.7 浮动布局（Float）

```zig
// src/layout/float.zig

/// 浮动布局算法
pub fn layoutFloat(layout_box: *LayoutBox, containing_block: *LayoutBox, y: *f32) !void {
    // 计算浮动元素尺寸
    try layoutBox(layout_box, containing_block.box_model.content);
    
    // 确定浮动方向
    const float_left = layout_box.float == .left;
    
    // 查找浮动位置
    var x: f32 = if (float_left) 0 else containing_block.box_model.content.width - layout_box.box_model.totalSize().width;
    
    // 检查与其他浮动元素的碰撞
    x = try findFloatPosition(layout_box, containing_block, x, y.*, float_left);
    
    // 设置位置
    layout_box.box_model.content.x = containing_block.box_model.content.x + x;
    layout_box.box_model.content.y = containing_block.box_model.content.y + y.*;
    
    // 更新y坐标
    y.* += layout_box.box_model.totalSize().height;
}

/// 查找浮动位置
fn findFloatPosition(layout_box: *LayoutBox, containing_block: *LayoutBox, x: f32, y: f32, float_left: bool) !f32 {
    // 获取包含块中的所有浮动元素
    const floats = getFloats(containing_block);
    
    // 检查碰撞
    var current_x = x;
    while (true) {
        var collision = false;
        for (floats.items) |float_box| {
            if (float_box == layout_box) continue;
            
            const float_rect = Rect{
                .x = float_box.box_model.content.x,
                .y = float_box.box_model.content.y,
                .width = float_box.box_model.totalSize().width,
                .height = float_box.box_model.totalSize().height,
            };
            
            const layout_rect = Rect{
                .x = current_x,
                .y = y,
                .width = layout_box.box_model.totalSize().width,
                .height = layout_box.box_model.totalSize().height,
            };
            
            if (float_rect.intersects(layout_rect)) {
                collision = true;
                if (float_left) {
                    current_x = float_rect.x + float_rect.width;
                } else {
                    current_x = float_rect.x - layout_rect.width;
                }
                break;
            }
        }
        
        if (!collision) break;
    }
    
    return current_x;
}

/// 清除浮动
pub fn clearFloats(containing_block: *LayoutBox, y: f32) !f32 {
    const floats = getFloats(containing_block);
    var max_y: f32 = y;
    
    for (floats.items) |float_box| {
        const float_bottom = float_box.box_model.content.y + float_box.box_model.totalSize().height;
        max_y = @max(max_y, float_bottom);
    }
    
    return max_y;
}
```

## 5. 实现细节

### 5.1 样式值解析

布局引擎需要从CSS样式值中解析出数值：

```zig
// src/layout/values.zig

/// 解析长度值
pub fn parseLength(value: css.parser.Value, font_size: f32, viewport_width: f32, viewport_height: f32) !f32 {
    return switch (value) {
        .length => |l| {
            return switch (l.unit) {
                .px => l.value,
                .em, .rem => l.value * font_size,
                .percent => l.value / 100.0 * viewport_width, // 简化：假设是宽度百分比
                .vw => l.value / 100.0 * viewport_width,
                .vh => l.value / 100.0 * viewport_height,
                .vmin => l.value / 100.0 * @min(viewport_width, viewport_height),
                .vmax => l.value / 100.0 * @max(viewport_width, viewport_height),
                else => return error.UnsupportedUnit,
            };
        },
        .percentage => |p| p / 100.0 * viewport_width,
        .keyword => |k| {
            if (std.mem.eql(u8, k, "auto")) {
                return 0; // auto需要特殊处理
            }
            return error.InvalidValue;
        },
        else => error.InvalidValue,
    };
}

/// 解析颜色值
pub fn parseColor(value: css.parser.Value) !Color {
    return switch (value) {
        .color => |c| c,
        .keyword => |k| {
            // 解析命名颜色
            return parseNamedColor(k);
        },
        else => error.InvalidValue,
    };
}
```

### 5.2 布局优化

1. **增量布局**：只重新布局变化的元素
2. **布局缓存**：缓存布局结果，避免重复计算
3. **并行布局**：独立子树可以并行布局

## 6. API设计

### 6.1 公共API

```zig
// src/layout/engine.zig

/// 布局引擎公共API
pub const Layout = struct {
    /// 执行完整布局
    pub fn layout(document: *dom.Document, stylesheets: []const css.parser.Stylesheet, viewport: Size, allocator: std.mem.Allocator) !*LayoutBox {
        var engine = LayoutEngine.init(allocator);
        return try engine.layout(document.node, stylesheets, viewport);
    }
    
    /// 获取元素布局信息
    pub fn getLayoutInfo(layout_box: *LayoutBox) LayoutInfo {
        return .{
            .x = layout_box.box_model.content.x,
            .y = layout_box.box_model.content.y,
            .width = layout_box.box_model.content.width,
            .height = layout_box.box_model.content.height,
            .total_width = layout_box.box_model.totalSize().width,
            .total_height = layout_box.box_model.totalSize().height,
        };
    }
};

/// 布局信息
pub const LayoutInfo = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    total_width: f32,
    total_height: f32,
};
```

## 7. 测试策略

### 7.1 单元测试

- 盒模型计算测试
- 各种布局算法测试
- 定位算法测试
- 浮动算法测试

### 7.2 集成测试

- 完整页面布局测试
- Chrome对比测试

### 7.3 测试用例示例

```zig
// tests/layout/block_test.zig

test "block layout basic" {
    // 测试基本块级布局
}

test "block layout with margin" {
    // 测试带margin的块级布局
}

test "flexbox layout row" {
    // 测试Flexbox行布局
}

test "grid layout basic" {
    // 测试Grid基本布局
}
```

## 8. 性能考虑

1. **布局计算复杂度**：O(n)，n为DOM节点数
2. **内存使用**：布局树大小约为DOM树的1.5倍
3. **优化策略**：
   - 延迟计算：只在需要时计算
   - 缓存结果：缓存布局结果
   - 增量更新：只更新变化的部分

## 9. 后续扩展

1. **表格布局**：实现table布局算法
2. **多列布局**：实现CSS多列布局
3. **响应式布局**：支持媒体查询和响应式设计
4. **打印布局**：支持打印样式和分页

## 10. 参考资料

- [CSS Box Model](https://www.w3.org/TR/CSS2/box.html)
- [CSS Display](https://www.w3.org/TR/CSS2/visuren.html)
- [CSS Positioning](https://www.w3.org/TR/CSS2/visuren.html#position)
- [CSS Flexible Box Layout](https://www.w3.org/TR/css-flexbox-1/)
- [CSS Grid Layout](https://www.w3.org/TR/css-grid-1/)
- [Chrome Layout Engine](https://chromium.googlesource.com/chromium/src/+/main/third_party/blink/renderer/core/layout/)

