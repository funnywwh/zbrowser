# Headless浏览器渲染引擎详细设计文档

## 1. 架构设计

### 1.1 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                   用户输入 (HTML/CSS/JS)                 │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
┌───────▼────────┐      ┌─────────▼────────┐
│  HTML解析器    │      │   CSS解析器       │
│  - Tokenizer   │      │   - Parser        │
│  - Parser      │      │   - Selector      │
│  - DOM构建     │      │   - Cascade       │
└───────┬────────┘      └─────────┬────────┘
        │                         │
        └────────────┬────────────┘
                     │
            ┌────────▼────────┐
            │   样式计算       │
            │  - 选择器匹配    │
            │  - 样式层叠      │
            │  - 继承计算      │
            └────────┬─────────┘
                     │
            ┌────────▼────────┐
            │   布局引擎       │
            │  - 盒模型        │
            │  - Block/Inline  │
            │  - Flexbox       │
            │  - Grid          │
            └────────┬─────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
┌───────▼────────┐      ┌─────────▼────────┐
│  JavaScript    │      │   渲染引擎       │
│  引擎          │      │   - Painter      │
│  - Parser      │      │   - Text         │
│  - VM          │      │   - Image        │
│  - DOM API     │      │   - Canvas       │
│  - Events      │      └─────────┬────────┘
└───────┬────────┘                │
        │                         │
        └────────────┬────────────┘
                     │
            ┌────────▼────────┐
            │   PNG编码器     │
            │   - 光栅化      │
            │   - 压缩        │
            └────────┬─────────┘
                     │
            ┌────────▼────────┐
            │   PNG文件输出    │
            └──────────────────┘
```

### 1.2 模块划分

#### 核心模块
1. **HTML解析模块**：解析HTML文档，构建DOM树
2. **CSS解析模块**：解析CSS样式表，计算样式
3. **布局模块**：计算元素位置和尺寸
4. **渲染模块**：将布局结果绘制到画布
5. **抽象渲染后端模块**：提供统一的渲染接口，支持CPU和GPU后端
6. **图像输出模块**：将画布编码为PNG

#### 扩展模块
6. **JavaScript引擎模块**：解析和执行JavaScript
7. **DOM API模块**：提供DOM操作接口
8. **事件模块**：处理用户事件和DOM事件
9. **动画模块**：处理CSS动画和过渡

## 2. 数据结构设计

### 2.1 DOM节点结构

```zig
// src/html/dom.zig

pub const NodeType = enum {
    element,
    text,
    comment,
    document,
    doctype,
};

pub const Node = struct {
    node_type: NodeType,
    parent: ?*Node = null,
    first_child: ?*Node = null,
    last_child: ?*Node = null,
    next_sibling: ?*Node = null,
    prev_sibling: ?*Node = null,
    
    // 节点数据（根据类型使用不同字段）
    data: union(NodeType) {
        element: ElementData,
        text: []const u8,
        comment: []const u8,
        document: void,
        doctype: void,
    },
    
    // 样式信息（布局后填充）
    computed_style: ?*ComputedStyle = null,
    layout_box: ?*LayoutBox = null,
    
    pub fn appendChild(self: *Node, child: *Node) void {
        // 实现子节点添加逻辑
    }
    
    pub fn removeChild(self: *Node, child: *Node) void {
        // 实现子节点移除逻辑
    }
};

pub const ElementData = struct {
    tag_name: []const u8,
    attributes: std.StringHashMap([]const u8),
    namespace: []const u8 = "http://www.w3.org/1999/xhtml",
};
```

### 2.2 CSS规则结构

```zig
// src/css/parser.zig

pub const Selector = struct {
    specificity: Specificity,
    components: []SelectorComponent,
    
    pub fn matches(self: *const Selector, element: *Node) bool {
        // 实现选择器匹配逻辑
    }
};

pub const Specificity = struct {
    inline: u32 = 0,
    id: u32 = 0,
    class: u32 = 0,
    element: u32 = 0,
    
    pub fn compare(self: *const Specificity, other: *const Specificity) std.math.Order {
        // 实现优先级比较
    }
};

pub const Rule = struct {
    selectors: []Selector,
    declarations: []Declaration,
};

pub const Declaration = struct {
    property: []const u8,
    value: Value,
    important: bool = false,
};

pub const Value = union(enum) {
    keyword: []const u8,
    length: Length,
    color: Color,
    percentage: f32,
    // ... 其他值类型
};
```

### 2.3 布局框结构

```zig
// src/layout/box.zig

pub const LayoutBox = struct {
    node: *Node,
    box_type: BoxType,
    dimensions: Dimensions,
    padding: EdgeSizes,
    border: EdgeSizes,
    margin: EdgeSizes,
    children: std.ArrayList(*LayoutBox),
    
    pub fn get_content_box(self: *const LayoutBox) Rectangle {
        // 计算内容区域
    }
    
    pub fn get_border_box(self: *const LayoutBox) Rectangle {
        // 计算边框区域
    }
};

pub const Dimensions = struct {
    content: Rectangle,
    padding: EdgeSizes,
    border: EdgeSizes,
    margin: EdgeSizes,
};

pub const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const EdgeSizes = struct {
    top: f32,
    right: f32,
    bottom: f32,
    left: f32,
};
```

### 2.4 渲染指令结构

```zig
// src/render/painter.zig

pub const RenderCommand = union(enum) {
    fill_rect: FillRect,
    stroke_rect: StrokeRect,
    fill_text: FillText,
    draw_image: DrawImage,
    clip: Clip,
    transform: Transform,
};

pub const FillRect = struct {
    rect: Rectangle,
    color: Color,
};

pub const FillText = struct {
    text: []const u8,
    x: f32,
    y: f32,
    font: Font,
    color: Color,
};
```

## 3. 算法设计

### 3.1 HTML解析算法

#### 3.1.1 词法分析（Tokenizer）

**算法**：状态机驱动的HTML词法分析

```
状态：
- DATA: 数据状态
- TAG_OPEN: 标签开始
- TAG_NAME: 标签名
- BEFORE_ATTRIBUTE_NAME: 属性名前
- ATTRIBUTE_NAME: 属性名
- AFTER_ATTRIBUTE_NAME: 属性名后
- BEFORE_ATTRIBUTE_VALUE: 属性值前
- ATTRIBUTE_VALUE: 属性值
- SELF_CLOSING_TAG: 自闭合标签
- COMMENT: 注释
- DOCTYPE: DOCTYPE

流程：
1. 初始状态：DATA
2. 遇到 '<'：进入TAG_OPEN
3. 遇到字母：进入TAG_NAME，收集标签名
4. 遇到空格：进入BEFORE_ATTRIBUTE_NAME
5. 遇到属性名：进入ATTRIBUTE_NAME
6. 遇到 '='：进入BEFORE_ATTRIBUTE_VALUE
7. 遇到属性值：进入ATTRIBUTE_VALUE
8. 遇到 '>'：结束标签，返回DATA
9. 遇到 '</'：结束标签
10. 遇到 '<!--'：进入COMMENT
11. 遇到 '<!DOCTYPE'：进入DOCTYPE
```

**实现要点**：
- 处理字符编码（UTF-8）
- 处理实体引用（&lt;, &gt;, &amp;等）
- 处理CDATA节
- 错误恢复机制

#### 3.1.2 语法分析（Parser）

**算法**：HTML5规范解析算法

```
流程：
1. 创建Document节点
2. 维护开放元素栈（open_elements）
3. 维护格式化元素列表（formatting_elements）
4. 根据当前token和插入模式（insertion_mode）处理：
   - initial: 处理DOCTYPE
   - before_html: 创建html元素
   - before_head: 创建head元素
   - in_head: 处理head内容
   - after_head: 处理head后内容
   - in_body: 处理body内容（主要模式）
   - after_body: 处理body后内容
   - in_table: 处理表格内容
   - ... 其他模式
5. 根据标签类型应用相应规则
6. 构建DOM树
```

**实现要点**：
- 实现HTML5规范的所有插入模式
- 处理特殊元素（script, style, noscript等）
- 处理表单元素
- 错误恢复和容错处理

### 3.2 CSS解析算法

#### 3.2.1 CSS词法分析

**算法**：CSS词法分析器

```
Token类型：
- IDENT: 标识符
- STRING: 字符串
- NUMBER: 数字
- PERCENTAGE: 百分比
- DIMENSION: 带单位的数字
- HASH: #颜色或ID
- URL: url()
- FUNCTION: 函数
- AT_KEYWORD: @规则
- DELIM: 分隔符
- WHITESPACE: 空白
- COMMENT: 注释

流程：
1. 读取字符
2. 根据字符类型确定token类型
3. 收集token值
4. 返回token
```

#### 3.2.2 CSS语法分析

**算法**：递归下降解析器

```
规则：
stylesheet: (CDO | CDC | rule | at_rule)*
rule: selector_list '{' declaration_list '}'
selector_list: selector (',' selector)*
selector: simple_selector_sequence (combinator simple_selector_sequence)*
declaration_list: declaration (';' declaration)*
declaration: property ':' value important?
```

#### 3.2.3 选择器匹配算法

**算法**：从右到左匹配（Chrome方式）

```
流程：
1. 将选择器分解为组件序列
2. 从最右侧的简单选择器开始
3. 在DOM树中查找匹配的元素
4. 验证左侧的组件是否匹配
5. 计算specificity
```

**示例**：
```
选择器: div.container > p#intro
匹配流程：
1. 查找id="intro"的元素
2. 验证是否为p标签
3. 验证父元素是否为div且class包含"container"
4. 验证父元素关系为">"（直接子元素）
```

#### 3.2.4 样式层叠算法

**算法**：CSS层叠规则

```
优先级计算：
1. 重要性（!important）
2. 来源（用户代理、用户、作者）
3. Specificity（内联 > ID > 类 > 元素）
4. 声明顺序（后声明的覆盖先声明的）

流程：
1. 收集所有匹配的规则
2. 按来源分组
3. 按specificity排序
4. 按声明顺序排序
5. 应用!important规则
6. 计算最终样式值
```

### 3.3 布局算法

#### 3.3.1 块级布局算法

**算法**：块级格式化上下文（BFC）

```
流程：
1. 计算包含块的宽度
2. 计算元素宽度（考虑margin、border、padding）
3. 计算元素高度（递归计算子元素）
4. 处理浮动元素
5. 处理清除浮动
6. 计算垂直边距折叠
```

#### 3.3.2 Flexbox布局算法

**算法**：Flexbox规范算法

```
流程：
1. 确定主轴和交叉轴方向
2. 计算flex容器的尺寸
3. 计算flex项的初始尺寸
4. 计算flex项的flex基础尺寸
5. 计算可用空间
6. 分配flex增长/收缩
7. 对齐flex项（justify-content, align-items）
8. 处理换行（flex-wrap）
```

**关键计算**：
```
flex-basis: 基础尺寸
flex-grow: 增长因子
flex-shrink: 收缩因子
可用空间 = 容器尺寸 - 所有flex-basis
增长空间 = 可用空间 * (flex-grow / sum(flex-grow))
收缩空间 = 超出空间 * (flex-shrink * flex-basis / sum(flex-shrink * flex-basis))
```

#### 3.3.3 Grid布局算法

**算法**：CSS Grid规范算法

```
流程：
1. 解析grid-template-rows和grid-template-columns
2. 计算网格线位置
3. 解析grid-area或grid-row/grid-column
4. 分配网格区域
5. 计算网格项尺寸
6. 对齐网格项（justify-items, align-items）
7. 处理grid-auto-rows和grid-auto-columns
```

**网格线计算**：
```
对于grid-template-columns: 100px 1fr 2fr
- 第1条线：0px
- 第2条线：100px
- 第3条线：100px + (可用宽度 * 1/3)
- 第4条线：100px + (可用宽度 * 2/3) + (可用宽度 * 1/3)
```

### 3.4 渲染算法

#### 3.4.1 绘制顺序

**算法**：Z-index和层叠上下文

```
流程：
1. 构建层叠上下文树
2. 按z-index排序
3. 按文档顺序绘制
4. 处理透明度混合
5. 处理transform和filter
```

#### 3.4.2 文本渲染算法

**算法**：文本布局和渲染

```
流程：
1. 文本分段（按语言、字体）
2. 字形定位（考虑字距、连字）
3. 行布局（换行、对齐）
4. 字形光栅化
5. 抗锯齿处理
6. 子像素渲染
```

**换行算法**：
```
1. 测量文本宽度
2. 找到换行点（空格、连字符、CJK字符边界）
3. 应用text-align对齐
4. 计算行高和行间距
```

#### 3.4.3 抽象渲染后端设计

**设计目标**：提供统一的渲染接口，支持CPU和GPU两种后端实现

**架构设计**：

```zig
// src/render/backend.zig

/// 渲染后端接口
pub const RenderBackend = struct {
    vtable: *const VTable,
    
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
        getPixels: *const fn (self: *RenderBackend, allocator: std.mem.Allocator) ![]u8,
        getWidth: *const fn (self: *const RenderBackend) u32,
        getHeight: *const fn (self: *const RenderBackend) u32,
        
        // 清理
        deinit: *const fn (self: *RenderBackend) void,
    };
};

/// CPU渲染后端（软件光栅化）
pub const CpuRenderBackend = struct {
    base: RenderBackend,
    width: u32,
    height: u32,
    pixels: []u8, // RGBA格式
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !*CpuRenderBackend {
        const self = try allocator.create(CpuRenderBackend);
        self.* = .{
            .base = .{
                .vtable = &cpu_vtable,
            },
            .width = width,
            .height = height,
            .pixels = try allocator.alloc(u8, width * height * 4),
            .allocator = allocator,
        };
        
        // 初始化为白色背景
        @memset(self.pixels, 255);
        
        return self;
    }
    
    pub fn deinit(self: *CpuRenderBackend) void {
        self.allocator.free(self.pixels);
        self.allocator.destroy(self);
    }
    
    // 实现VTable中的各个方法
    fn fillRectImpl(self: *RenderBackend, rect: Rect, color: Color) void {
        const cpu = @fieldParentPtr(CpuRenderBackend, "base", self);
        // CPU软件光栅化实现
    }
    
    // ... 其他方法实现
};

/// GPU渲染后端（硬件加速，计划中）
pub const GpuRenderBackend = struct {
    base: RenderBackend,
    // TODO: GPU相关资源（纹理、Shader、命令缓冲区等）
    
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !*GpuRenderBackend {
        // TODO: 初始化GPU资源
        _ = allocator;
        _ = width;
        _ = height;
        return error.NotImplemented;
    }
    
    // TODO: 实现GPU加速的绘制方法
};
```

**CPU后端实现要点**：
- 使用软件光栅化算法
- 维护RGBA像素缓冲区
- 实现抗锯齿、混合、裁剪等操作
- 支持路径绘制（直线、曲线、圆弧）
- 支持文本渲染（字形光栅化）

**GPU后端实现要点（计划）**：
- 使用现代图形API（Vulkan/Metal/DirectX12）
- 使用Shader进行硬件加速绘制
- 纹理管理和缓存
- 命令缓冲区优化
- 减少CPU-GPU数据传输

**后端选择策略**：
- 默认使用CPU后端（兼容性最好）
- 可通过配置选择GPU后端（性能更好）
- 运行时可以切换后端

#### 3.4.4 抗锯齿算法

**算法**：灰度抗锯齿

```
流程：
1. 将图形放大N倍（如4x）
2. 在高分辨率下绘制
3. 计算每个像素的覆盖率
4. 按覆盖率混合前景色和背景色
5. 缩小到目标分辨率
```

### 3.5 JavaScript引擎算法

#### 3.5.1 词法分析

**算法**：JavaScript词法分析器

```
Token类型：
- IDENTIFIER: 标识符
- KEYWORD: 关键字
- NUMBER: 数字（整数、浮点数、科学计数法）
- STRING: 字符串（单引号、双引号、模板字符串）
- REGEXP: 正则表达式
- PUNCTUATOR: 标点符号
- TEMPLATE: 模板字符串

特殊处理：
- 自动分号插入（ASI）
- Unicode转义序列
- 数字字面量（二进制、八进制、十六进制）
```

#### 3.5.2 语法分析

**算法**：递归下降解析器生成AST

```
语法规则（简化）：
Program: Statement*
Statement: 
  - ExpressionStatement
  - BlockStatement
  - IfStatement
  - WhileStatement
  - ForStatement
  - FunctionDeclaration
  - VariableDeclaration
  - ReturnStatement
  - ...
Expression:
  - AssignmentExpression
  - ConditionalExpression
  - LogicalExpression
  - BinaryExpression
  - UnaryExpression
  - CallExpression
  - MemberExpression
  - ...
```

#### 3.5.3 执行引擎

**算法**：AST解释执行

```
执行流程：
1. 创建全局执行上下文
2. 创建全局对象（globalThis）
3. 执行代码：
   - 变量声明提升
   - 函数声明提升
   - 执行语句
   - 表达式求值
4. 管理作用域链
5. 处理this绑定
6. 处理闭包
```

**作用域管理**：
```
执行上下文栈：
- 全局上下文
- 函数上下文
- eval上下文

作用域链：
每个上下文维护作用域链，查找变量时沿链向上查找
```

#### 3.5.4 原型链

**算法**：原型链查找

```
流程：
1. 在对象自身属性中查找
2. 如果未找到，在__proto__中查找
3. 递归向上查找原型链
4. 直到Object.prototype或null
```

### 3.6 事件系统算法

**算法**：事件捕获和冒泡

```
流程：
1. 事件捕获阶段：
   - 从document根节点向下传播
   - 触发捕获阶段监听器
2. 目标阶段：
   - 在目标元素触发
3. 事件冒泡阶段：
   - 从目标元素向上传播
   - 触发冒泡阶段监听器
4. 默认行为处理
```

### 3.7 CSS动画算法

**算法**：CSS动画时间轴

```
流程：
1. 解析@keyframes规则
2. 创建动画时间轴
3. 每帧计算：
   - 当前时间进度（0-1）
   - 查找关键帧区间
   - 插值计算属性值
   - 应用transform
4. 更新DOM样式
5. 触发重绘
```

**插值算法**：
```
线性插值：
value = start_value + (end_value - start_value) * progress

缓动函数：
ease: cubic-bezier(0.25, 0.1, 0.25, 1)
ease-in: cubic-bezier(0.42, 0, 1, 1)
ease-out: cubic-bezier(0, 0, 0.58, 1)
ease-in-out: cubic-bezier(0.42, 0, 0.58, 1)
```

### 3.8 PNG编码算法

**算法**：PNG编码流程

```
流程：
1. 准备图像数据（RGBA格式）
2. 过滤（Filter）：
   - None: 无过滤
   - Sub: 减去左侧像素
   - Up: 减去上方像素
   - Average: 减去平均值
   - Paeth: Paeth预测器
3. DEFLATE压缩：
   - LZ77压缩
   - Huffman编码
4. 构建PNG文件结构：
   - PNG签名
   - IHDR块（图像头）
   - IDAT块（图像数据）
   - IEND块（结束）
```

**DEFLATE算法**：
```
1. LZ77压缩：
   - 查找重复字符串
   - 用(距离, 长度)对替换
2. Huffman编码：
   - 统计字符频率
   - 构建Huffman树
   - 生成编码表
   - 编码数据
```

## 4. 接口设计

### 4.1 主API接口

```zig
// src/main.zig

pub const Browser = struct {
    allocator: std.mem.Allocator,
    document: *html.Document,
    stylesheet: *css.StyleSheet,
    js_engine: *js.VM,
    
    pub fn init(allocator: std.mem.Allocator) !Browser {
        // 初始化浏览器实例
    }
    
    pub fn loadHTML(self: *Browser, html_content: []const u8) !void {
        // 加载和解析HTML
    }
    
    pub fn loadCSS(self: *Browser, css_content: []const u8) !void {
        // 加载和解析CSS
    }
    
    pub fn loadJS(self: *Browser, js_content: []const u8) !void {
        // 加载和执行JavaScript
    }
    
    pub fn render(self: *Browser, width: u32, height: u32) !Image {
        // 渲染页面为图像
    }
    
    pub fn renderToPNG(self: *Browser, width: u32, height: u32, path: []const u8) !void {
        // 渲染并保存为PNG文件
    }
    
    pub fn deinit(self: *Browser) void {
        // 清理资源
    }
};
```

### 4.2 DOM API接口

```zig
// src/js/dom_api.zig

pub const Document = struct {
    pub fn getElementById(self: *Document, id: []const u8) ?*Element {
        // 实现getElementById
    }
    
    pub fn querySelector(self: *Document, selector: []const u8) ?*Element {
        // 实现querySelector
    }
    
    pub fn createElement(self: *Document, tag_name: []const u8) *Element {
        // 创建元素
    }
};

pub const Element = struct {
    node: *html.Node,
    
    pub fn appendChild(self: *Element, child: *Element) void {
        // 添加子元素
    }
    
    pub fn setAttribute(self: *Element, name: []const u8, value: []const u8) void {
        // 设置属性
    }
    
    pub fn addEventListener(self: *Element, event_type: []const u8, handler: EventHandler) void {
        // 添加事件监听器
    }
};
```

## 5. 内存管理

### 5.1 分配策略

```zig
// src/utils/allocator.zig

// 使用Zig的标准分配器
// 对于频繁分配的小对象，使用Arena分配器
// 对于大对象，使用GeneralPurposeAllocator

pub const BrowserAllocator = struct {
    arena: std.heap.ArenaAllocator,
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    
    pub fn init() BrowserAllocator {
        // 初始化分配器
    }
    
    pub fn allocator(self: *BrowserAllocator) std.mem.Allocator {
        // 返回合适的分配器
    }
};
```

### 5.2 引用计数

对于DOM节点，使用引用计数管理生命周期：

```zig
pub const RefCounted = struct {
    count: usize,
    
    pub fn retain(self: *RefCounted) void {
        self.count += 1;
    }
    
    pub fn release(self: *RefCounted) void {
        self.count -= 1;
        if (self.count == 0) {
            // 释放资源
        }
    }
};
```

## 6. 错误处理

### 6.1 错误类型

```zig
pub const BrowserError = error{
    ParseError,
    RenderError,
    MemoryError,
    InvalidInput,
};
```

### 6.2 错误恢复

- HTML解析：容错解析，尽可能恢复
- CSS解析：忽略无效规则，继续解析
- JavaScript：抛出异常，可由try-catch捕获

## 7. 性能优化

### 7.1 缓存策略

- 样式计算缓存
- 布局结果缓存
- 字体度量缓存

### 7.2 增量更新

- 仅重新计算变化的样式
- 仅重新布局变化的元素
- 仅重新渲染变化的区域

### 7.3 SIMD优化

对于图像处理操作，使用SIMD指令加速。

## 8. 测试设计

### 8.1 单元测试结构

```zig
// tests/html/parser_test.zig

test "parse simple HTML" {
    const html = "<html><body><p>Hello</p></body></html>";
    const doc = try parseHTML(html);
    // 验证DOM结构
}

test "parse with attributes" {
    const html = "<div class='container' id='main'></div>";
    const doc = try parseHTML(html);
    // 验证属性解析
}
```

### 8.2 集成测试

```zig
// tests/integration/render_test.zig

test "render simple page" {
    var browser = try Browser.init(test_allocator);
    defer browser.deinit();
    
    try browser.loadHTML("<html><body><h1>Test</h1></body></html>");
    try browser.loadCSS("h1 { color: red; }");
    
    const image = try browser.render(800, 600);
    // 验证渲染结果
}
```

### 8.3 Chrome对比测试

```zig
// tests/integration/chrome_compat_test.zig

test "chrome compatibility" {
    // 加载测试HTML
    // 使用Chrome渲染
    // 使用本引擎渲染
    // 对比PNG图像（允许小误差）
}
```

## 9. 开发规范

### 9.1 代码风格

- 使用`zig fmt`格式化代码
- 函数命名：camelCase
- 类型命名：PascalCase
- 常量命名：UPPER_SNAKE_CASE

### 9.2 注释规范

- 公共API必须有文档注释
- 复杂算法必须有注释说明
- 使用Zig文档注释格式（///）

### 9.3 测试要求

- 每个公开函数必须有测试
- 边界条件必须有测试
- 错误情况必须有测试
- 目标：100%代码覆盖率

## 10. 参考实现

### 10.1 参考项目

- Chromium Blink引擎（参考架构）
- Servo引擎（参考Rust实现）
- WebKit（参考算法）

### 10.2 规范文档

- HTML5规范：https://html.spec.whatwg.org/
- CSS规范：https://www.w3.org/Style/CSS/
- ECMAScript规范：https://tc39.es/ecma262/
- DOM规范：https://dom.spec.whatwg.org/

### 10.3 Chrome行为参考

- Chrome DevTools Protocol文档
- Chrome源码（参考实现思路，不直接使用代码）
- Chrome渲染测试用例

---

本文档将随着开发进展持续更新和完善。

