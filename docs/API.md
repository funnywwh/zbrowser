# ZBrowser API 文档

本文档描述了ZBrowser的所有公共API接口。

## 版本信息

- **当前版本**: 0.8.0-alpha
- **Zig版本要求**: 0.15.2+

## 模块概览

### 主模块 (`src/main.zig`)

#### Browser

Headless浏览器的主入口点，提供HTML加载和渲染功能。

```zig
pub const Browser = struct {
    allocator: std.mem.Allocator,
    browser_allocator: allocator_utils.BrowserAllocator,
    document: *dom.Document,
    
    /// 初始化浏览器实例
    /// 
    /// 参数:
    ///   - allocator: 内存分配器
    /// 
    /// 返回:
    ///   - Browser实例或错误
    /// 
    /// 示例:
    /// ```zig
    /// var browser = try Browser.init(allocator);
    /// defer browser.deinit();
    /// ```
    pub fn init(allocator: std.mem.Allocator) !Browser;
    
    /// 加载和解析HTML内容
    /// 
    /// 参数:
    ///   - html_content: HTML字符串内容
    /// 
    /// 返回:
    ///   - void或解析错误
    /// 
    /// 示例:
    /// ```zig
    /// try browser.loadHTML("<html><body>Hello</body></html>");
    /// ```
    pub fn loadHTML(self: *Browser, html_content: []const u8) !void;
    
    /// 渲染页面（占位实现，待实现）
    /// 
    /// 参数:
    ///   - width: 渲染宽度（像素）
    ///   - height: 渲染高度（像素）
    pub fn render(self: *Browser, width: u32, height: u32) !void;
    
    /// 渲染并保存为PNG（占位实现，待实现）
    /// 
    /// 参数:
    ///   - width: 渲染宽度（像素）
    ///   - height: 渲染高度（像素）
    ///   - path: 输出文件路径
    pub fn renderToPNG(self: *Browser, width: u32, height: u32, path: []const u8) !void;
    
    /// 释放浏览器实例及其所有资源
    pub fn deinit(self: *Browser) void;
};
```

---

## HTML模块 (`src/html/`)

### DOM模块 (`dom.zig`)

#### NodeType

DOM节点类型枚举。

```zig
pub const NodeType = enum {
    element,    // 元素节点
    text,       // 文本节点
    comment,    // 注释节点
    document,   // 文档节点
    doctype,    // DOCTYPE节点
};
```

#### Node

DOM树中的节点，支持元素、文本、注释等类型。

```zig
pub const Node = struct {
    node_type: NodeType,
    parent: ?*Node,
    first_child: ?*Node,
    last_child: ?*Node,
    next_sibling: ?*Node,
    prev_sibling: ?*Node,
    data: Data,
    
    /// 添加子节点
    /// 
    /// 参数:
    ///   - child: 要添加的子节点
    ///   - allocator: 内存分配器（当前未使用）
    pub fn appendChild(self: *Node, child: *Node, allocator: std.mem.Allocator) !void;
    
    /// 移除子节点
    /// 
    /// 参数:
    ///   - child: 要移除的子节点
    pub fn removeChild(self: *Node, child: *Node) void;
    
    /// 获取元素数据（仅对element类型有效）
    /// 
    /// 返回:
    ///   - ElementData指针或null
    pub fn asElement(self: *Node) ?*ElementData;
    
    /// 获取文本内容（仅对text类型有效）
    /// 
    /// 返回:
    ///   - 文本内容或null
    pub fn asText(self: *const Node) ?[]const u8;
    
    /// 查找子元素（深度优先搜索）
    /// 
    /// 参数:
    ///   - tag_name: 标签名
    /// 
    /// 返回:
    ///   - 找到的节点或null
    /// 
    /// 示例:
    /// ```zig
    /// const div = node.querySelector("div");
    /// ```
    pub fn querySelector(self: *Node, tag_name: []const u8) ?*Node;
    
    /// 获取所有子节点
    /// 
    /// 参数:
    ///   - allocator: 内存分配器
    /// 
    /// 返回:
    ///   - 子节点数组
    pub fn getChildren(self: *Node, allocator: std.mem.Allocator) ![]*Node;
};
```

#### ElementData

元素节点的数据，包含标签名和属性。

```zig
pub const ElementData = struct {
    tag_name: []const u8,
    attributes: std.StringHashMap([]const u8),
    namespace: []const u8 = "http://www.w3.org/1999/xhtml",
    
    /// 初始化元素数据
    /// 
    /// 参数:
    ///   - allocator: 内存分配器
    ///   - tag_name: 标签名
    pub fn init(allocator: std.mem.Allocator, tag_name: []const u8) ElementData;
    
    /// 获取属性值
    /// 
    /// 参数:
    ///   - name: 属性名
    /// 
    /// 返回:
    ///   - 属性值或null
    /// 
    /// 示例:
    /// ```zig
    /// const class = elem.getAttribute("class");
    /// ```
    pub fn getAttribute(self: *const ElementData, name: []const u8) ?[]const u8;
    
    /// 设置属性
    /// 
    /// 参数:
    ///   - name: 属性名
    ///   - value: 属性值
    ///   - allocator: 内存分配器
    pub fn setAttribute(self: *ElementData, name: []const u8, value: []const u8, allocator: std.mem.Allocator) !void;
    
    /// 检查是否有指定属性
    /// 
    /// 参数:
    ///   - name: 属性名
    /// 
    /// 返回:
    ///   - true如果属性存在
    pub fn hasAttribute(self: *const ElementData, name: []const u8) bool;
    
    /// 获取ID属性
    /// 
    /// 返回:
    ///   - ID值或null
    pub fn getId(self: *const ElementData) ?[]const u8;
    
    /// 获取class属性列表
    /// 
    /// 参数:
    ///   - allocator: 内存分配器
    /// 
    /// 返回:
    ///   - class名称数组
    pub fn getClasses(self: *const ElementData, allocator: std.mem.Allocator) ![]const []const u8;
    
    /// 释放元素数据
    /// 
    /// 参数:
    ///   - allocator: 内存分配器（当前未使用）
    pub fn deinit(self: *ElementData, allocator: std.mem.Allocator) void;
};
```

#### Document

文档节点，代表整个HTML文档。

```zig
pub const Document = struct {
    node: Node,
    allocator: std.mem.Allocator,
    
    /// 初始化文档
    /// 
    /// 参数:
    ///   - allocator: 内存分配器
    /// 
    /// 返回:
    ///   - Document实例
    pub fn init(allocator: std.mem.Allocator) !Document;
    
    /// 获取根元素（html元素）
    /// 
    /// 返回:
    ///   - html节点或null
    pub fn getDocumentElement(self: *Document) ?*Node;
    
    /// 获取head元素
    /// 
    /// 返回:
    ///   - head节点或null
    pub fn getHead(self: *Document) ?*Node;
    
    /// 获取body元素
    /// 
    /// 返回:
    ///   - body节点或null
    pub fn getBody(self: *Document) ?*Node;
    
    /// 查找单个元素（通过标签名）
    /// 
    /// 参数:
    ///   - tag_name: 标签名
    /// 
    /// 返回:
    ///   - 找到的第一个元素或null
    /// 
    /// 示例:
    /// ```zig
    /// const div = doc.querySelector("div");
    /// ```
    pub fn querySelector(self: *Document, tag_name: []const u8) ?*Node;
    
    /// 查找所有匹配的元素（通过标签名）
    /// 
    /// 参数:
    ///   - tag_name: 标签名
    ///   - allocator: 内存分配器
    /// 
    /// 返回:
    ///   - 匹配的元素数组
    /// 
    /// 示例:
    /// ```zig
    /// const divs = try doc.querySelectorAll("div", allocator);
    /// defer allocator.free(divs);
    /// ```
    pub fn querySelectorAll(self: *Document, tag_name: []const u8, allocator: std.mem.Allocator) ![]*Node;
    
    /// 通过ID查找元素
    /// 
    /// 参数:
    ///   - id: 元素ID
    /// 
    /// 返回:
    ///   - 找到的元素或null
    /// 
    /// 示例:
    /// ```zig
    /// const elem = doc.getElementById("myId");
    /// ```
    pub fn getElementById(self: *Document, id: []const u8) ?*Node;
    
    /// 通过标签名查找所有元素
    /// 
    /// 参数:
    ///   - tag_name: 标签名
    ///   - allocator: 内存分配器
    /// 
    /// 返回:
    ///   - 匹配的元素数组
    /// 
    /// 示例:
    /// ```zig
    /// const divs = try doc.getElementsByTagName("div", allocator);
    /// defer allocator.free(divs);
    /// ```
    pub fn getElementsByTagName(self: *Document, tag_name: []const u8, allocator: std.mem.Allocator) ![]*Node;
    
    /// 通过类名查找所有元素
    /// 
    /// 参数:
    ///   - class_name: 类名
    ///   - allocator: 内存分配器
    /// 
    /// 返回:
    ///   - 匹配的元素数组
    /// 
    /// 示例:
    /// ```zig
    /// const items = try doc.getElementsByClassName("item", allocator);
    /// defer allocator.free(items);
    /// ```
    pub fn getElementsByClassName(self: *Document, class_name: []const u8, allocator: std.mem.Allocator) ![]*Node;
    
    /// 释放文档及其所有节点
    pub fn deinit(self: *Document) void;
};
```

---

### Parser模块 (`parser.zig`)

#### Parser

HTML5解析器，将HTML字符串解析为DOM树。

```zig
pub const Parser = struct {
    tokenizer: tokenizer.Tokenizer,
    document: *dom.Document,
    allocator: std.mem.Allocator,
    open_elements: std.ArrayList(*dom.Node),
    open_elements_allocator: std.mem.Allocator,
    insertion_mode: InsertionMode,
    
    /// 初始化解析器
    /// 
    /// 参数:
    ///   - input: HTML字符串
    ///   - document: 目标文档对象
    ///   - allocator: 内存分配器
    /// 
    /// 返回:
    ///   - Parser实例
    /// 
    /// 示例:
    /// ```zig
    /// var parser = Parser.init(html_content, doc_ptr, allocator);
    /// defer parser.deinit();
    /// try parser.parse();
    /// ```
    pub fn init(input: []const u8, document: *dom.Document, allocator: std.mem.Allocator) Self;
    
    /// 解析HTML文档
    /// 
    /// 解析HTML字符串并构建DOM树。解析过程中会自动处理token的内存管理。
    /// 
    /// 返回:
    ///   - void或解析错误
    pub fn parse(self: *Self) !void;
    
    /// 释放解析器资源
    pub fn deinit(self: *Self) void;
};
```

---

### Tokenizer模块 (`tokenizer.zig`)

#### TokenType

HTML Token类型枚举。

```zig
pub const TokenType = enum {
    doctype,           // DOCTYPE声明
    start_tag,         // 开始标签
    end_tag,           // 结束标签
    self_closing_tag,  // 自闭合标签
    text,              // 文本内容
    comment,           // 注释
    cdata,             // CDATA段
    eof,               // 文件结束
};
```

#### Token

HTML Token，包含类型和数据。

```zig
pub const Token = struct {
    token_type: TokenType,
    data: Data,
    allocator: ?std.mem.Allocator = null,
    
    /// 释放token占用的内存
    /// 
    /// 注意：使用GPA分配器时，必须调用此方法释放内存。
    /// 使用Arena分配器时，会在Arena销毁时自动释放。
    pub fn deinit(self: *Token) void;
};
```

#### Tokenizer

HTML词法分析器，将HTML字符串分解为Token序列。

```zig
pub const Tokenizer = struct {
    input: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,
    
    /// 初始化tokenizer
    /// 
    /// 参数:
    ///   - input: HTML字符串
    ///   - allocator: 内存分配器
    /// 
    /// 返回:
    ///   - Tokenizer实例
    /// 
    /// 示例:
    /// ```zig
    /// var tok = Tokenizer.init(html_input, allocator);
    /// while (try tok.next()) |token| {
    ///     defer token.deinit();
    ///     // 处理token
    /// }
    /// ```
    pub fn init(input: []const u8, allocator: std.mem.Allocator) Self;
    
    /// 获取下一个token
    /// 
    /// 返回:
    ///   - Token或null（EOF）
    ///   - 错误（如果解析失败）
    /// 
    /// 注意：返回的Token在使用完毕后应调用deinit()释放内存。
    pub fn next(self: *Self) !?Token;
};
```

---

## 字体模块 (`src/font/`)

### FontManager (`font.zig`)

字体管理器，负责加载、缓存和管理字体。

```zig
pub const FontManager = struct {
    allocator: std.mem.Allocator,
    font_cache: std.StringHashMap(*FontFace),
    font_data_cache: std.StringHashMap([]u8),
    
    /// 初始化字体管理器
    /// 
    /// 参数:
    ///   - allocator: 内存分配器
    /// 
    /// 返回:
    ///   - FontManager实例
    /// 
    /// 示例:
    /// ```zig
    /// var font_manager = FontManager.init(allocator);
    /// defer font_manager.deinit();
    /// ```
    pub fn init(allocator: std.mem.Allocator) Self;
    
    /// 清理字体管理器
    /// 
    /// 释放所有缓存的字体和字体数据
    pub fn deinit(self: *Self) void;
    
    /// 加载字体文件
    /// 
    /// 参数:
    ///   - font_path: 字体文件路径
    ///   - font_name: 字体名称（用于缓存）
    /// 
    /// 返回:
    ///   - FontFace指针或错误
    /// 
    /// 示例:
    /// ```zig
    /// const font_face = try font_manager.loadFont("arial.ttf", "Arial");
    /// ```
    pub fn loadFont(self: *Self, font_path: []const u8, font_name: []const u8) !*FontFace;
    
    /// 根据字体名称查找字体
    /// 
    /// 参数:
    ///   - font_name: 字体名称（如 "Arial", "Times New Roman"）
    /// 
    /// 返回:
    ///   - FontFace指针或null（如果未找到）
    /// 
    /// 示例:
    /// ```zig
    /// const font_face = font_manager.getFont("Arial");
    /// if (font_face) |face| {
    ///     // 使用字体
    /// }
    /// ```
    pub fn getFont(self: *Self, font_name: []const u8) ?*FontFace;
};
```

### FontFace (`font.zig`)

字体面，表示一个已加载的字体文件。

```zig
pub const FontFace = struct {
    allocator: std.mem.Allocator,
    font_data: []const u8,
    ttf_parser: ttf.TtfParser,
    
    /// 初始化字体面
    /// 
    /// 参数:
    ///   - allocator: 内存分配器
    ///   - font_data: 字体文件数据（原始字节）
    /// 
    /// 返回:
    ///   - FontFace实例或错误
    pub fn init(allocator: std.mem.Allocator, font_data: []const u8) !Self;
    
    /// 清理字体面
    /// 
    /// 参数:
    ///   - allocator: 内存分配器（当前未使用）
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void;
    
    /// 获取字符的字形索引
    /// 
    /// 参数:
    ///   - codepoint: Unicode字符码点
    /// 
    /// 返回:
    ///   - 字形索引或null（如果未找到）
    /// 
    /// 示例:
    /// ```zig
    /// const glyph_index = try font_face.getGlyphIndex('A');
    /// ```
    pub fn getGlyphIndex(self: *Self, codepoint: u21) !?u16;
    
    /// 获取字形数据
    /// 
    /// 参数:
    ///   - glyph_index: 字形索引
    /// 
    /// 返回:
    ///   - 字形数据（Glyph）
    /// 
    /// 示例:
    /// ```zig
    /// var glyph = try font_face.getGlyph(glyph_index);
    /// defer glyph.deinit(allocator);
    /// ```
    pub fn getGlyph(self: *Self, glyph_index: u16) !ttf.TtfParser.Glyph;
    
    /// 获取字形的水平度量（宽度、左边界等）
    /// 
    /// 参数:
    ///   - glyph_index: 字形索引
    /// 
    /// 返回:
    ///   - 水平度量（HorizontalMetrics）
    /// 
    /// 示例:
    /// ```zig
    /// const metrics = try font_face.getHorizontalMetrics(glyph_index);
    /// const width = metrics.advance_width;
    /// ```
    pub fn getHorizontalMetrics(self: *Self, glyph_index: u16) !ttf.TtfParser.HorizontalMetrics;
    
    /// 获取字体度量信息
    /// 
    /// 返回:
    ///   - 字体度量（FontMetrics）
    /// 
    /// 示例:
    /// ```zig
    /// const metrics = try font_face.getFontMetrics();
    /// const units_per_em = metrics.units_per_em;
    /// ```
    pub fn getFontMetrics(self: *Self) !ttf.TtfParser.FontMetrics;
};
```

### TtfParser (`ttf.zig`)

TTF/OTF字体解析器，解析字体文件的各种表。

```zig
pub const TtfParser = struct {
    allocator: std.mem.Allocator,
    font_data: []const u8,
    table_directory: TableDirectory,
    
    /// 字体度量信息
    pub const FontMetrics = struct {
        units_per_em: u16,  // 单位/EM（字体设计单位）
        ascent: i16,        // 上升高度
        descent: i16,       // 下降高度
        line_gap: i16,      // 行间距
    };
    
    /// 水平度量信息
    pub const HorizontalMetrics = struct {
        advance_width: u16,      // 前进宽度
        left_side_bearing: i16,  // 左边界
    };
    
    /// 字形数据
    pub const Glyph = struct {
        glyph_index: u16,
        points: std.ArrayList(Point),
        instructions: std.ArrayList(u8),
        
        pub const Point = struct {
            x: i16,
            y: i16,
            on_curve: bool,  // 是否在曲线上
        };
        
        /// 清理字形数据
        pub fn deinit(self: *Glyph, allocator: std.mem.Allocator) void;
    };
    
    /// 初始化TTF解析器
    /// 
    /// 参数:
    ///   - allocator: 内存分配器
    ///   - font_data: 字体文件数据（原始字节）
    /// 
    /// 返回:
    ///   - TtfParser实例或错误
    pub fn init(allocator: std.mem.Allocator, font_data: []const u8) !Self;
    
    /// 清理TTF解析器
    /// 
    /// 参数:
    ///   - allocator: 内存分配器
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void;
    
    /// 获取字符的字形索引
    /// 
    /// 参数:
    ///   - codepoint: Unicode字符码点
    /// 
    /// 返回:
    ///   - 字形索引或null（如果未找到）
    pub fn getGlyphIndex(self: *Self, codepoint: u21) !?u16;
    
    /// 获取字形数据
    /// 
    /// 参数:
    ///   - glyph_index: 字形索引
    /// 
    /// 返回:
    ///   - 字形数据（Glyph）
    pub fn getGlyph(self: *Self, glyph_index: u16) !Glyph;
    
    /// 获取字形的水平度量
    /// 
    /// 参数:
    ///   - glyph_index: 字形索引
    /// 
    /// 返回:
    ///   - 水平度量（HorizontalMetrics）
    pub fn getHorizontalMetrics(self: *Self, glyph_index: u16) !HorizontalMetrics;
    
    /// 获取字体度量信息
    /// 
    /// 返回:
    ///   - 字体度量（FontMetrics）
    pub fn getFontMetrics(self: *Self) !FontMetrics;
};
```

### GlyphRenderer (`glyph.zig`)

字形渲染器，将字形轮廓转换为像素数据。

```zig
pub const GlyphRenderer = struct {
    allocator: std.mem.Allocator,
    
    /// 初始化字形渲染器
    /// 
    /// 参数:
    ///   - allocator: 内存分配器
    /// 
    /// 返回:
    ///   - GlyphRenderer实例
    pub fn init(allocator: std.mem.Allocator) Self;
    
    /// 清理字形渲染器
    pub fn deinit(self: *Self) void;
    
    /// 渲染字形到像素缓冲区
    /// 
    /// 参数:
    ///   - glyph: 字形数据
    ///   - font_metrics: 字体度量信息
    ///   - font_size: 字体大小（像素）
    ///   - width: 输出缓冲区宽度
    ///   - height: 输出缓冲区高度
    ///   - x_offset: X偏移量
    ///   - y_offset: Y偏移量
    /// 
    /// 返回:
    ///   - 像素缓冲区（RGBA格式）或错误
    /// 
    /// 示例:
    /// ```zig
    /// const pixels = try glyph_renderer.renderGlyph(
    ///     glyph,
    ///     font_metrics,
    ///     16.0,  // 字体大小
    ///     32,    // 宽度
    ///     32,    // 高度
    ///     0,     // X偏移
    ///     0,     // Y偏移
    /// );
    /// defer allocator.free(pixels);
    /// ```
    pub fn renderGlyph(
        self: *Self,
        glyph: *ttf.TtfParser.Glyph,
        font_metrics: ttf.TtfParser.FontMetrics,
        font_size: f32,
        width: u32,
        height: u32,
        x_offset: i32,
        y_offset: i32,
    ) ![]u8;
};
```

---

## 工具模块 (`src/utils/`)

### Allocator模块 (`allocator.zig`)

#### BrowserAllocator

浏览器专用的内存分配器包装，使用Arena分配器管理DOM节点生命周期。

```zig
pub const BrowserAllocator = struct {
    arena: std.heap.ArenaAllocator,
    
    /// 初始化浏览器分配器
    /// 
    /// 参数:
    ///   - backing_allocator: 底层分配器
    /// 
    /// 返回:
    ///   - BrowserAllocator实例
    pub fn init(backing_allocator: std.mem.Allocator) BrowserAllocator;
    
    /// 获取Arena分配器
    /// 
    /// 返回:
    ///   - Arena分配器，用于分配DOM节点
    pub fn arenaAllocator(self: *BrowserAllocator) std.mem.Allocator;
    
    /// 获取GPA分配器（当前返回arena分配器）
    pub fn gpaAllocator(self: *BrowserAllocator) std.mem.Allocator;
    
    /// 释放所有分配的内存
    pub fn deinit(self: *BrowserAllocator) void;
};
```

---

### String模块 (`string.zig`)

字符串工具函数。

```zig
/// 检查字符串是否以指定前缀开始
pub fn startsWith(haystack: []const u8, needle: []const u8) bool;

/// 检查字符串是否以指定后缀结束
pub fn endsWith(haystack: []const u8, needle: []const u8) bool;

/// 去除字符串首尾空白字符
pub fn trim(str: []const u8) []const u8;

/// 将字符串转换为小写（原地修改）
pub fn toLowerInPlace(str: []u8) void;

/// 检查字符是否为空白字符
pub fn isWhitespace(c: u8) bool;

/// 检查字符是否为字母
pub fn isAlpha(c: u8) bool;

/// 检查字符是否为数字
pub fn isDigit(c: u8) bool;

/// 检查字符是否为字母或数字
pub fn isAlnum(c: u8) bool;

/// 解码HTML实体
/// 
/// 参数:
///   - allocator: 内存分配器
///   - entity: HTML实体字符串（如"&amp;"）
/// 
/// 返回:
///   - 解码后的字符串
pub fn decodeHtmlEntity(allocator: std.mem.Allocator, entity: []const u8) ![]const u8;
```

---

### Math模块 (`math.zig`)

数学工具函数。

```zig
/// 将值限制在指定范围内
pub fn clamp(val: f32, min: f32, max: f32) f32;

/// 线性插值
pub fn lerp(start: f32, end: f32, t: f32) f32;

/// 计算两点间距离
pub fn distance(x1: f32, y1: f32, x2: f32, y2: f32) f32;

/// 角度转弧度
pub fn degToRad(degrees: f32) f32;

/// 弧度转角度
pub fn radToDeg(radians: f32) f32;

/// 近似相等比较（考虑浮点误差）
pub fn approxEqual(a: f32, b: f32, epsilon: f32) bool;
```

---

## 使用示例

### 基础HTML解析

```zig
const std = @import("std");
const Browser = @import("zbrowser").Browser;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建浏览器实例
    var browser = try Browser.init(allocator);
    defer browser.deinit();

    // 加载HTML
    const html = "<html><body><h1>Hello</h1></body></html>";
    try browser.loadHTML(html);

    // 访问DOM - 使用Document的查找方法
    const h1 = browser.document.querySelector("h1");
    if (h1) |h| {
        if (h.first_child) |text| {
            const text_content = text.asText().?;
            // 使用 text_content
            _ = text_content;
        }
    }
    
    // 通过ID查找
    const elem = browser.document.getElementById("myId");
    
    // 通过类名查找所有元素
    const items = try browser.document.getElementsByClassName("item", allocator);
    defer allocator.free(items);
    
    // 通过标签名查找所有元素
    const divs = try browser.document.getElementsByTagName("div", allocator);
    defer allocator.free(divs);
}
```

### 直接使用Parser

```zig
const std = @import("std");
const html = @import("html");
const dom = @import("dom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建文档
    var doc = try dom.Document.init(allocator);
    defer doc.deinit();
    const doc_ptr = try allocator.create(dom.Document);
    defer allocator.destroy(doc_ptr);
    doc_ptr.* = doc;

    // 创建解析器
    var parser = html.Parser.init("<html><body>Test</body></html>", doc_ptr, allocator);
    defer parser.deinit();
    
    // 解析
    try parser.parse();

    // 访问DOM
    const body = doc_ptr.getBody();
    // ...
}
```

### 使用Tokenizer

```zig
const std = @import("std");
const tokenizer = @import("tokenizer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tok = tokenizer.Tokenizer.init("<div>Hello</div>", allocator);
    
    while (try tok.next()) |token| {
        defer token.deinit();
        
        switch (token.token_type) {
            .start_tag => {
                const tag_name = token.data.start_tag.name;
                // 使用 tag_name
                _ = tag_name;
            },
            .text => {
                const text_content = token.data.text;
                // 使用 text_content
                _ = text_content;
            },
            .end_tag => {
                const tag_name = token.data.end_tag.name;
                // 使用 tag_name
                _ = tag_name;
            },
            .eof => break,
            else => {},
        }
    }
}
```

---

## 错误处理

所有可能失败的操作都返回错误联合类型（Error Union Types）。常见错误包括：

- 内存分配失败
- HTML解析错误（无效标签、未闭合标签等）
- 文件I/O错误（未来实现）

使用`try`或`catch`处理错误：

```zig
var browser = try Browser.init(allocator);
try browser.loadHTML(html);
```

---

## 内存管理

### Arena分配器

Browser使用Arena分配器管理DOM节点生命周期。所有通过Parser创建的节点会在Browser销毁时自动释放。

### 手动内存管理

在测试代码中使用GPA分配器时，需要手动释放节点：

```zig
// 在测试中手动释放所有节点
freeAllNodes(allocator, &doc_ptr.node);
```

---

## 注意事项

1. **内存管理**: 使用Browser API时，DOM节点由Arena分配器管理，无需手动释放。使用Parser/Tokenizer API时，需要注意内存管理。

2. **线程安全**: 当前实现不是线程安全的，不应在多线程环境中共享Browser实例。

3. **错误处理**: 所有可能失败的操作都返回错误，必须使用`try`或`catch`处理。

4. **API稳定性**: 当前版本为0.1.0-alpha，API可能会发生变化。

---

## 版本历史

### 0.7.0-alpha

- ✅ **完成字体模块核心功能并集成到渲染后端**
  - TTF/OTF字体解析器完整实现
  - 字形渲染器完整实现
  - 文本渲染集成（已完成）
    - ✅ 字体模块集成到CPU渲染后端
    - ✅ 自动字体加载（从Windows系统字体目录自动加载）
    - ✅ 真正的文本渲染（使用字形渲染器渲染真实字形）
    - ✅ 字体缓存机制（避免重复加载）
    - ✅ 回退机制（字体加载失败时使用占位符）
- ✅ Windows支持（环境脚本、字体目录支持）
- ✅ 所有测试通过：304/304 passed
- ✅ 0内存泄漏

### 0.1.0-alpha

- 初始版本
- HTML5解析器实现
- DOM树构建
- 基础工具模块
- 8个HTML解析测试用例
- 0内存泄漏

