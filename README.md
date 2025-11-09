# ZBrowser - Headless浏览器渲染引擎

一个使用Zig 0.15.2从零开始实现的headless浏览器渲染引擎，支持HTML5、CSS3和现代JavaScript，输出PNG图片，0外部依赖。

## 项目概述

ZBrowser是一个完全用Zig语言实现的headless浏览器渲染引擎，严格遵循Chrome最新版本规范，确保渲染结果与Chrome浏览器视觉一致。项目采用模块化设计，从HTML解析到PNG输出，所有功能均从零实现，不依赖任何外部库。

## 特性

### 已实现
- ✅ HTML5解析器（词法分析、语法分析、DOM树构建）
- ✅ DOM数据结构（Node、Element、Document）
- ✅ CSS3解析器（递归下降解析器、tokenizer、选择器匹配）
- ✅ CSS样式层叠计算（优先级、继承、默认样式）
- ✅ 基础工具模块（内存管理、字符串处理、数学工具）
- ✅ 布局引擎基础（盒模型、布局上下文、BFC、IFC）
- ✅ 块级布局（Block布局算法）
- ✅ 行内布局（Inline布局算法）
- ✅ 定位布局（static、relative、absolute、fixed、sticky）
- ✅ 浮动布局（float: left/right，碰撞检测，清除浮动）
- ✅ Flexbox布局（完整实现）
  - ✅ flex-grow/shrink/basis计算
  - ✅ justify-content对齐（flex-start, flex-end, center, space-between, space-around, space-evenly）
  - ✅ align-items对齐（flex-start, flex-end, center, stretch）
  - ✅ flex-wrap换行处理（wrap, wrap-reverse）
  - ✅ align-content多行对齐（flex-start, flex-end, center, space-between, space-around, space-evenly, stretch）
  - ✅ flex-direction反向处理（row-reverse, column-reverse）
- ✅ Grid布局基础框架
- ✅ 布局引擎主入口（构建布局树、执行布局）
- ✅ 抽象渲染后端接口（RenderBackend VTable）
- ✅ CPU渲染后端（软件光栅化、像素缓冲、基本图形绘制）
  - ✅ 基础绘制操作（fillRect、strokeRect、fillText）
  - ✅ 路径绘制（beginPath、moveTo、lineTo、arc、closePath、fill、stroke）
  - ✅ 变换操作（save、restore、translate、scale、rotate）
  - ✅ 状态管理（裁剪、全局透明度）
  - ✅ 渲染树到像素转换（Renderer模块）
  - ✅ 布局树遍历和渲染
  - ✅ 背景、边框、文本内容渲染
  - ✅ 样式解析（颜色、字体、边框等CSS属性）
  - ✅ 真正的文本渲染（集成字体模块，渲染真实字形）
- ✅ PNG编码器（完整实现）
  - ✅ PNG文件格式（签名、IHDR、IDAT、IEND chunks）
  - ✅ CRC32校验算法
  - ✅ 5种PNG滤波器（None、Sub、Up、Average、Paeth）
  - ✅ 最优滤波器选择算法
  - ✅ DEFLATE存储模式（BTYPE=00，支持大数据分块）
  - ✅ zlib格式（头部、ADLER32校验）
  - ✅ 支持大图像（自动分块处理，避免整数溢出）
- ✅ 字体模块（核心功能完成，已集成到渲染后端）
  - ✅ 字体管理器（FontManager、FontFace）
  - ✅ TTF/OTF字体解析器（完整实现）
    - ✅ 字体表目录解析（SFNT头部、表记录）
    - ✅ head表解析（字体度量信息、units_per_em）
    - ✅ hhea表解析（水平头部信息、ascent、descent、line_gap）
    - ✅ hmtx表解析（水平度量表、advance_width、left_side_bearing）
    - ✅ cmap表解析（字符到字形映射，支持格式4和格式12）
    - ✅ loca表解析（字形位置索引，支持短格式和长格式）
    - ✅ glyf表解析（字形轮廓数据，包括控制点和坐标）
    - ✅ fpgm表解析（Font Program，用于hinting）
    - ✅ prep表解析（Control Value Program，用于hinting）
    - ✅ cvt表解析（Control Value Table，用于hinting）
  - ✅ 字形渲染器（完整实现）
    - ✅ 字形轮廓转换（字体单位到像素单位）
    - ✅ 二次贝塞尔曲线处理（TrueType轮廓）
    - ✅ 扫描线填充算法（轮廓填充，支持多轮廓even-odd规则）
    - ✅ 抗锯齿渲染（32x32子像素采样，MSDF技术，smootherstep平滑函数）
    - ✅ 小字体优化（根据字体大小动态调整抗锯齿参数）
  - ✅ TrueType Hinting解释器（完整实现）
    - ✅ HintingInterpreter虚拟机（支持100+指令）
    - ✅ 栈操作（PUSH、POP、DUP、CLEAR等）
    - ✅ 数学运算（ADD、SUB、MUL、DIV、ABS、NEG等）
    - ✅ 逻辑运算（LT、GT、EQ、AND、OR等）
    - ✅ 图形状态管理（向量设置、rounding状态）
    - ✅ 点操作（MIAP、IP、MD、GC等）
    - ✅ 存储区和CVT操作（WS、RS、RCVT、WCVTP等）
  - ✅ 文本渲染集成（已完成）
    - ✅ 自动字体加载（从Windows系统字体目录自动加载）
    - ✅ 真正的文本渲染（使用字形渲染器渲染真实字形）
    - ✅ 字体缓存机制（避免重复加载）
    - ✅ 回退机制（字体加载失败时使用占位符）
    - ✅ CJK语言支持（中文、日文、韩文自动检测和字体加载）
    - ✅ 混合字体渲染（按字符切换字体，支持多语言混合文本）
  - 🔲 抗锯齿渲染（计划中）
  - 🔲 复合字形处理（计划中）

### 计划中
- 🔲 Flexbox布局baseline对齐（待实现）
- 🔲 Grid布局完整实现（grid-template、grid-area、对齐等）
- 🔲 渲染引擎优化（完整扫描线填充、Bresenham算法）
- 🔲 JavaScript引擎（解析、执行、DOM API）
- 🔲 事件系统
- 🔲 CSS动画支持

## 技术栈

- **编程语言**: Zig 0.15.2
- **目标平台**: Linux (可扩展至Windows、macOS)
- **外部依赖**: 0（仅使用Zig标准库）
- **构建系统**: Zig Build System

## 项目结构

```
zbrowser/
├── src/
│   ├── main.zig              # 主入口，提供浏览器API
│   ├── html/                 # HTML解析模块
│   │   ├── parser.zig        # HTML5解析器
│   │   ├── dom.zig           # DOM树结构
│   │   └── tokenizer.zig     # HTML词法分析器
│   ├── css/                  # CSS解析模块
│   │   ├── parser.zig        # CSS3解析器
│   │   ├── selector.zig      # CSS选择器匹配
│   │   ├── cascade.zig       # 样式层叠计算
│   │   ├── tokenizer.zig    # CSS词法分析器
│   ├── js/                   # JavaScript引擎（待实现）
│   ├── layout/               # 布局引擎（进行中）
│   │   ├── box.zig          # 盒模型数据结构
│   │   ├── context.zig      # 布局上下文（BFC、IFC）
│   │   ├── block.zig        # 块级布局算法
│   │   ├── inline.zig       # 行内布局算法
│   │   ├── position.zig    # 定位布局算法
│   │   ├── float.zig       # 浮动布局算法
│   │   ├── flexbox.zig     # Flexbox布局算法
│   │   └── engine.zig      # 布局引擎主入口
│   ├── render/               # 渲染引擎（进行中）
│   │   ├── backend.zig      # 抽象渲染后端接口
│   │   ├── cpu_backend.zig  # CPU渲染后端
│   │   └── renderer.zig     # 渲染树到像素转换
│   ├── image/                # 图像处理
│   │   ├── png.zig          # PNG编码器
│   │   └── deflate.zig      # DEFLATE压缩算法
│   ├── font/                 # 字体模块（进行中）
│   │   ├── font.zig         # 字体管理器（FontManager, FontFace）
│   │   ├── ttf.zig          # TTF/OTF字体解析器
│   │   └── glyph.zig        # 字形渲染器
│   ├── utils/                # 工具模块
│   │   ├── allocator.zig    # 内存分配器
│   │   ├── string.zig       # 字符串工具
│   │   └── math.zig         # 数学工具
│   └── test/                # 测试运行器
├── tests/                    # 测试用例
│   ├── html/                # HTML解析测试
│   ├── css/                 # CSS解析测试
│   ├── layout/              # 布局引擎测试
│   ├── render/              # 渲染引擎测试
│   ├── image/               # 图像处理测试
│   │   ├── test_png_direct.zig  # PNG直接测试
│   │   └── test_png_solid.zig  # PNG纯色测试
│   ├── font/                # 字体模块测试
│   │   ├── font_test.zig   # 字体管理器测试
│   │   └── ttf_test.zig    # TTF解析器测试
│   ├── utils/               # 工具模块测试
│   ├── js/                  # JavaScript测试（待实现）
│   └── integration/         # 集成测试（待实现）
├── test.zig                 # 根测试文件（统一入口）
├── build.zig                 # 构建配置
├── docs/                     # 文档目录
│   ├── README.md            # 项目说明（从根目录复制）
│   ├── PLAN.md              # 开发计划
│   ├── DESIGN.md            # 详细设计文档
│   └── API.md               # API文档
├── PLAN.md                   # 开发计划（已移至docs/）
├── DESIGN.md                 # 详细设计文档（已移至docs/）
└── README.md                 # 本文件
```

## 快速开始

### 环境要求

- Zig 0.15.2（需要单独下载，见下方说明）
- Linux系统或Windows系统（支持WSL）

**注意**: Zig编译器文件较大（>100MB），未包含在git仓库中。请从[Zig官网](https://ziglang.org/download/)下载Zig 0.15.2，解压到项目根目录：
- Linux: `zig-x86_64-linux-0.15.2/`
- Windows: `zig-x86_64-windows-0.15.2/`

### 构建项目

**Linux/WSL:**
```bash
# 设置环境变量（使用项目自带的Zig）
source env.sh

# 构建项目
zig build

# 运行示例
zig build run
```

**Windows (PowerShell):**
```powershell
# 设置环境变量（使用项目自带的Zig）
. .\env.ps1

# 构建项目
zig build

# 运行示例
zig build run
```

**Windows (CMD):**
```cmd
# 设置环境变量（使用项目自带的Zig）
env.bat

# 构建项目
zig build

# 运行示例
zig build run
```

### 运行测试

```bash
# 运行所有测试
zig build test
```

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
    const html = 
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>Test</title></head>
        \\<body><h1>Hello, World!</h1></body>
        \\</html>
    ;
    try browser.loadHTML(html);

    // 渲染为PNG（待实现）
    // try browser.renderToPNG(800, 600, "output.png");
}
```

## 开发计划

项目按照以下阶段进行开发：

1. **阶段1: 基础设施和HTML解析** ✅
   - 项目结构搭建
   - HTML5解析器实现
   - DOM树构建

2. **阶段2: CSS解析和样式计算** ✅
   - CSS3解析器（递归下降解析器）
   - CSS Tokenizer（词法分析）
   - 选择器匹配（类型、类、ID、属性、伪类、组合器）
   - 样式层叠计算（优先级、继承、默认样式）

3. **阶段3: 布局引擎** 🟡（进行中）
   - ✅ 盒模型（BoxModel、LayoutBox）
   - ✅ 布局上下文（BFC、IFC）
   - ✅ Block布局算法
   - ✅ Inline布局算法
   - ✅ 定位布局（static、relative、absolute、fixed、sticky）
   - ✅ 浮动布局（float: left/right）
   - ✅ Flexbox布局（完整实现，baseline对齐待实现）
   - 🔲 Grid布局算法

4. **阶段4: 渲染引擎** ✅
   - ✅ 抽象渲染后端接口（RenderBackend VTable）
   - ✅ CPU渲染后端（软件光栅化、像素缓冲、基本图形绘制）
   - ✅ 渲染树到像素转换（Renderer模块）
   - ✅ PNG编码器（完整实现，支持大图像）

5. **阶段5: 字体加载和字形渲染** ✅（核心功能完成）
   - ✅ 字体管理器（FontManager、FontFace）
   - ✅ TTF/OTF字体解析器（完整实现）
     - ✅ 字体表目录解析
     - ✅ head、hhea、hmtx、cmap、loca、glyf表解析
   - ✅ 字形渲染器（完整实现）
     - ✅ 字形轮廓转换
     - ✅ 二次贝塞尔曲线处理
     - ✅ 扫描线填充算法
   - ✅ 集成到渲染后端（已完成）
     - ✅ 自动字体加载（从系统字体目录加载）
     - ✅ 真正的文本渲染（使用字形渲染器）
     - ✅ 字体缓存机制
   - 🔲 抗锯齿渲染（计划中）
   - 🔲 复合字形处理（计划中）

6. **阶段6-8: JavaScript引擎、DOM API、动画等** 🔲
   - JavaScript解析和执行
   - DOM API实现
   - 事件系统
   - CSS动画

详细计划请参考 [PLAN.md](PLAN.md)

## 技术设计

### HTML解析

- **词法分析**: 实现HTML5规范的tokenizer，支持标签、属性、注释、CDATA、DOCTYPE
- **语法分析**: 实现HTML5规范的解析算法，支持多种插入模式（initial、before_html、before_head、in_head、in_body等）
- **DOM构建**: 构建完整的DOM树，支持元素、文本、注释节点
- **Script标签处理**: 支持内联脚本、外部脚本和ES6模块脚本的解析
- **内存管理**: 使用Arena分配器管理DOM节点生命周期，确保无内存泄漏

### CSS解析（已实现）

- **CSS Tokenizer**: 实现CSS词法分析，支持所有CSS token类型
- **递归下降解析器**: 实现CSS语法分析，解析样式表、规则、选择器、声明
- **选择器匹配**: 支持类型、类、ID、属性、伪类（first-child、last-child、only-child、empty、nth-child、nth-of-type）、组合器（后代、子、相邻、兄弟）
- **样式层叠**: 实现CSS优先级计算和样式继承
- **样式计算**: 计算每个元素的最终样式，支持默认样式

### 布局引擎（进行中）

- ✅ **盒模型**: 支持content-box和border-box（BoxModel、LayoutBox）
- ✅ **布局上下文**: Block格式化上下文（BFC）、Inline格式化上下文（IFC）
- ✅ **块级布局**: Block布局算法（宽度计算、垂直堆叠）
- ✅ **行内布局**: Inline布局算法（行框创建、元素放置、换行）
- ✅ **定位布局**: 支持static、relative、absolute、fixed、sticky定位
- ✅ **浮动布局**: 支持float: left/right，碰撞检测，清除浮动
- ✅ **Flexbox布局**: 完整实现（flex-grow/shrink/basis、对齐算法、换行、多行对齐），baseline对齐待实现
- 🔲 **Grid布局**: 待实现

### 渲染引擎（已完成）

- ✅ **抽象渲染后端**: 统一的渲染接口（RenderBackend VTable）
  - ✅ **CPU后端**（已实现）：软件光栅化、像素缓冲、基本图形绘制
    - fillRect、strokeRect、fillText
    - 路径绘制（beginPath、moveTo、lineTo、arc、closePath、fill、stroke）
    - 变换操作（save、restore、translate、scale、rotate）
    - 状态管理（裁剪、全局透明度）
  - 🔲 **GPU后端**（计划中）：硬件加速、Shader、纹理管理
- ✅ **渲染树到像素转换**: Renderer模块
  - 布局树遍历和渲染
  - 背景、边框、文本内容渲染
  - 样式解析（颜色、字体、边框等CSS属性）
- ✅ **PNG编码器**: 完整实现
  - PNG文件格式（签名、IHDR、IDAT、IEND chunks）
  - CRC32校验算法
  - 5种PNG滤波器（None、Sub、Up、Average、Paeth）
  - 最优滤波器选择算法
  - DEFLATE存储模式（支持大数据自动分块）
  - zlib格式（头部、ADLER32校验）

### 字体模块（核心功能完成，已集成到渲染后端）

- ✅ **字体管理器**: FontManager和FontFace
  - ✅ 字体加载和缓存机制
  - ✅ 字体查找接口
  - ✅ 字体数据生命周期管理
- ✅ **TTF/OTF解析器**: TtfParser
  - ✅ 字体表目录解析（SFNT头部、表记录）
  - ✅ 基础数据结构（FontMetrics、HorizontalMetrics、Glyph）
  - ✅ cmap表解析（字符到字形索引映射，支持格式4和格式12）
  - ✅ head表解析（字体度量信息、units_per_em）
  - ✅ hhea表解析（水平头部信息、ascent、descent、line_gap）
  - ✅ hmtx表解析（水平度量表、advance_width、left_side_bearing）
  - ✅ glyf表解析（字形轮廓数据，包括控制点和坐标）
  - ✅ loca表解析（字形位置索引，支持短格式和长格式）
- ✅ **字形渲染器**: GlyphRenderer
  - ✅ 字形轮廓转换（字体单位到像素单位）
  - ✅ 扫描线填充算法（轮廓填充）
  - ✅ 二次贝塞尔曲线处理（TrueType轮廓）
- ✅ **文本渲染集成**:
  - ✅ 字体模块集成到CPU渲染后端
  - ✅ 自动字体加载（从Windows系统字体目录自动加载）
  - ✅ 真正的文本渲染（使用字形渲染器渲染真实字形）
  - ✅ 字体缓存机制（避免重复加载）
  - ✅ 回退机制（字体加载失败时使用占位符）
  - ✅ 抗锯齿渲染（覆盖度抗锯齿，4x4子像素采样，smootherstep平滑函数）
  - ✅ 多轮廓字形处理（支持even-odd规则填充，正确处理如'e'、'o'等字符的内外轮廓）
  - ✅ CJK语言支持（中文、日文、韩文自动检测和字体加载）
  - ✅ 混合字体渲染（按字符切换字体，支持多语言混合文本）
  - ✅ 自动页面尺寸计算（根据文本实际宽度自动计算最小页面尺寸，确保刚好显示所有内容）

详细设计请参考 [DESIGN.md](DESIGN.md)

## 测试

项目目标实现100%代码覆盖率。测试包括：

- **单元测试**: 每个模块独立测试
- **集成测试**: 模块间交互测试
- **兼容性测试**: 与Chrome渲染结果对比

### 测试覆盖

**✅ 所有测试已完成！** 当前测试覆盖以下模块：

#### 测试统计

- **Font 模块**：24 个测试
  - FontManager测试（初始化、空缓存、查找不存在的字体等）
  - TTF解析器测试（13个测试用例，包括边界测试）
    - 初始化、字体度量、字符映射、水平度量、字形解析
    - 边界情况：空数据、无效格式、缺失表、表太短等
  - 字形渲染器测试（8个测试用例，包括边界测试）
    - 空字形、简单轮廓、控制点处理、边界情况等
- **HTML DOM 模块**：26 个测试
  - Document API测试（getDocumentElement、getHead、getBody、getElementsByTagName等）
  - Node操作测试（appendChild、removeChild、querySelector等）
  - ElementData测试（getAttribute、setAttribute、getClasses等）
  - 内存管理测试（Document.deinit、ElementData.deinit）

- **HTML Parser 模块**：25 个测试
  - 基础解析测试（简单HTML、带属性、文本、注释、自闭合标签等）
  - 边界情况测试（不完整标签、嵌套错误、实体编码、Unicode、emoji）
  - 插入模式测试（initial、before_html、before_head、in_head、after_head、in_body）
  - 错误恢复机制测试

- **HTML Tokenizer 模块**：30 个测试
  - 基础tokenization测试（开始标签、结束标签、文本、注释、CDATA、DOCTYPE等）
  - 边界情况测试（不完整CDATA、DOCTYPE、特殊字符、Unicode、emoji）
  - 错误处理测试（UnexpectedEOF、InvalidTag）

- **CSS 模块**：52 个测试
  - CSS Tokenizer测试（27个测试用例）
  - CSS Parser测试（10个测试用例）
  - CSS Selector测试（12个测试用例）
  - CSS Cascade测试（3个测试用例）

- **Utils 模块**：27 个测试
  - String Utils测试（13个测试用例）
  - Math Utils测试（8个测试用例）
  - Allocator Utils测试（6个测试用例）

- **Font Hinting模块**：26 个测试
  - HintingInterpreter初始化和清理
  - CVT表加载（正常情况、边界情况、错误情况）
  - 指令执行（栈操作、数学运算、逻辑运算、图形状态）
  - 边界情况（空指令、栈溢出、无效指令、除零）
  - 存储区操作（WS、RS）
  - CVT操作（RCVT、WCVTP）
  - 图形状态管理（向量设置、rounding状态）
- **总计**：330 个测试

#### 测试完成状态

- ✅ **高优先级（核心功能）**：全部完成
  - Document.deinit、ElementData.deinit、Parser.deinit、Token.deinit等内存管理测试
- ✅ **中优先级（边界情况）**：全部完成
  - 不完整HTML、嵌套错误、实体编码、Unicode、emoji等边界情况测试
- ✅ **低优先级（错误处理）**：全部完成
  - InvalidTag错误、插入模式、错误恢复机制等测试

#### 测试结果

- ✅ 所有测试通过：330/330 passed
- ✅ 0个内存泄漏
- ✅ 代码编译无错误
- ✅ 所有内存管理正确（无双重释放、无泄漏）
- ✅ 使用GeneralPurposeAllocator进行内存泄漏检测

运行测试：
```bash
zig build test
```

详细测试报告请参考 [tests/MISSING_TESTS.md](tests/MISSING_TESTS.md)

## 开发规范

- 使用`zig fmt`格式化代码
- 所有公共API必须有文档注释（///）
- 遵循Zig编码规范
- 测试驱动开发（TDD）
- 目标：100%代码覆盖率

详细规范请参考 [.cursorrules](.cursorrules)

## 兼容性

- **HTML**: HTML5规范（WHATWG Living Standard）
- **CSS**: CSS3规范，包括Flexbox、Grid、动画
- **JavaScript**: ECMAScript 2024规范
- **渲染**: 与Chrome最新版本视觉一致

## 性能目标

- 支持复杂页面的渲染
- 合理的内存使用
- 可接受的渲染速度

## 贡献

欢迎贡献！请遵循以下步骤：

1. Fork项目
2. 创建特性分支
3. 编写测试（确保100%覆盖率）
4. 提交更改
5. 创建Pull Request

## 许可证

[待定]

## 参考资料

- [HTML5规范](https://html.spec.whatwg.org/)
- [CSS规范](https://www.w3.org/Style/CSS/)
- [ECMAScript规范](https://tc39.es/ecma262/)
- [DOM规范](https://dom.spec.whatwg.org/)
- [Chrome渲染架构](https://developer.chrome.com/docs/chromium/renderingng-architecture/)
- [Zig语言文档](https://ziglang.org/documentation/)

## 状态

**当前版本**: 0.8.1-alpha  
**开发阶段**: 阶段1-5核心功能完成（TrueType Hinting完整实现，小字体优化）

### 最新更新（v0.8.1-alpha）

- ✅ **TrueType Hinting完整实现**
  - ✅ HintingInterpreter虚拟机（支持100+ TrueType指令）
  - ✅ 栈操作、数学运算、逻辑运算、图形状态管理
  - ✅ 点操作（MIAP、IP、MD、GC等）
  - ✅ 存储区和CVT操作（WS、RS、RCVT、WCVTP等）
  - ✅ 完整的测试覆盖（26个测试用例，包括边界情况）
  - ✅ 修复整数溢出问题（point_index和cvt_index的有效性检查）

- ✅ **小字体抗锯齿优化**
  - ✅ 根据字体大小动态调整抗锯齿参数
  - ✅ 小字体（< 20px）使用更低的覆盖度，避免笔画过粗
  - ✅ 优化MSDF参数，小字体使用更小的平滑范围
  - ✅ 改善小字体渲染质量，特别是中文字符的横线

### 历史更新（v0.8.0-alpha）

- ✅ **文本渲染增强和优化**
  - ✅ 抗锯齿渲染（覆盖度抗锯齿，32x32子像素采样，MSDF技术，smootherstep平滑函数）
  - ✅ 多轮廓字形处理（支持even-odd规则填充，正确处理如'e'、'o'、'p'等字符的内外轮廓）
  - ✅ CJK语言支持（中文、日文、韩文自动检测和字体加载）
  - ✅ 混合字体渲染（按字符切换字体，支持多语言混合文本，如韩文文本中的中文字符）
  - ✅ 自动页面尺寸计算（根据文本实际宽度自动计算最小页面尺寸，确保刚好显示所有内容）
  - ✅ 文本宽度计算（calculateTextWidth函数，使用字体advance_width精确计算文本宽度）
  - ✅ 修复文本重叠问题（正确处理绝对定位元素的子元素位置）
  - ✅ 修复文本对齐问题（第一个字符不使用left_side_bearing，确保正确对齐）
  - ✅ 修复文本显示问题（跳过metadata标签如title、head、meta等的渲染）

### 历史更新（v0.7.0-alpha）

- ✅ **完成字体模块核心功能并集成到渲染后端**
  - TTF/OTF字体解析器完整实现
    - ✅ head表解析（字体度量信息、units_per_em）
    - ✅ hhea表解析（水平头部信息、ascent、descent、line_gap）
    - ✅ hmtx表解析（水平度量表、advance_width、left_side_bearing）
    - ✅ cmap表解析（字符到字形映射，支持格式4和格式12）
    - ✅ loca表解析（字形位置索引，支持短格式和长格式）
    - ✅ glyf表解析（字形轮廓数据，包括控制点和坐标）
  - 字形渲染器完整实现
    - ✅ 字形轮廓转换（字体单位到像素单位）
    - ✅ 二次贝塞尔曲线处理（TrueType轮廓）
    - ✅ 扫描线填充算法（轮廓填充）
  - 文本渲染集成
    - ✅ 字体模块集成到CPU渲染后端
    - ✅ 自动字体加载（从Windows系统字体目录自动加载）
    - ✅ 真正的文本渲染（使用字形渲染器渲染真实字形）
    - ✅ 字体缓存机制（避免重复加载）
    - ✅ 回退机制（字体加载失败时使用占位符）
  - 完整的测试覆盖（24个测试用例，包括边界测试）
  - 修复所有内存泄漏问题
  - 修复段错误（布局树清理问题）
  - 适配Zig 0.15.2 API（ArrayList初始化方式）
- ✅ **Windows支持**
  - 添加env.bat和env.ps1脚本，支持Windows环境
  - 修复Windows下的编译和测试问题

### 历史更新（v0.5.0-alpha）

- ✅ **完成渲染引擎和PNG编码器实现**
  - 抽象渲染后端接口（RenderBackend VTable）
  - CPU渲染后端（软件光栅化、像素缓冲、基本图形绘制）
  - 渲染树到像素转换（Renderer模块）
  - PNG编码器完整实现（支持大图像自动分块）
  - 修复DEFLATE压缩问题（使用存储模式，确保数据正确编码）
  - 修复整数溢出问题（支持超过65535字节的数据分块处理）
  - 修复PNG文件生成问题（现在可以正确显示内容）
- ✅ **文件结构整理**
  - test.zig 保持在根目录（统一测试入口）
  - 测试文件整理到 tests/ 相关目录
  - test_png_direct.zig 和 test_png_solid.zig 移到 tests/image/
- ✅ **测试验证**
  - PNG文件格式验证通过
  - PNG数据可以正确解压
  - PNG文件可以在图像查看器中正确显示

### 历史更新（v0.4.0-alpha）

- ✅ **完成布局引擎核心功能实现**
  - 盒模型数据结构（Rect、Size、Point、Edges、BoxModel、LayoutBox）
  - 布局上下文（FormattingContext、BFC、IFC）
  - 块级布局算法（Block布局，宽度计算，垂直堆叠）
  - 行内布局算法（Inline布局，行框创建，元素放置，换行）
  - 定位布局算法（static、relative、absolute、fixed、sticky）
  - 浮动布局算法（float: left/right，碰撞检测，清除浮动）
  - Flexbox布局完整实现（flex-grow/shrink/basis、对齐算法、换行、多行对齐）
  - 布局引擎主入口（构建布局树、执行布局）
  - 支持content-box和border-box盒模型
  - 完整的初始化和清理机制（deinit、deinitAndDestroyChildren）
- ✅ **布局引擎测试覆盖**
  - 盒模型测试：10个测试用例
  - 布局上下文测试：10个测试用例
  - 块级布局测试：多个测试用例
  - 行内布局测试：多个测试用例
  - 定位布局测试：8个测试用例（包括边界测试）
  - 浮动布局测试：8个测试用例（包括边界测试）
  - Flexbox布局测试：6个测试用例（包括边界测试，待扩展）
  - 布局引擎测试：10个测试用例
  - 所有测试通过，0内存泄漏
- ✅ **修复关键问题**
  - 修复defer执行顺序问题（先deinit，再destroy）
  - 修复内存泄漏问题（正确释放子节点内存）
  - 修复DOM节点清理问题（使用freeAllNodes清理有子节点的节点）
  - 修复浮动布局碰撞检测问题（使用is_layouted标志判断已布局元素）
- ✅ **遵循TDD开发流程**
  - 先写测试，再写实现
  - 100%测试覆盖率
  - 严格的内存管理
  - 所有简化实现都添加了TODO注释

### 历史更新（v0.2.0-alpha）

- ✅ **完成CSS解析器实现**（递归下降方法）
  - CSS Tokenizer：完整的词法分析器，支持所有CSS token类型
  - CSS Parser：递归下降解析器，解析样式表、规则、选择器、声明
  - 选择器匹配：支持类型、类、ID、属性、伪类、组合器
  - 样式层叠：实现优先级计算和样式继承
  - 样式计算：计算元素最终样式，支持默认样式
- ✅ **完成所有测试任务**
  - 高优先级测试：8项全部完成（Document.deinit、ElementData.deinit等）
  - 中优先级测试：5项全部完成（边界情况、不完整HTML、Unicode等）
  - 低优先级测试：2项全部完成（错误处理、插入模式测试）
  - 新增测试：24个测试用例
  - 测试总数：160个测试，全部通过
- ✅ **修复所有内存管理问题**
  - 修复段错误：在advance()之前先复制token数据
  - 修复双重释放：添加deinitValueOnly()方法，正确处理HashMap中的Declaration
  - 修复内存泄漏：所有分配的内存都正确释放
  - 修复ElementData.setAttribute内存泄漏：正确释放旧属性值
- ✅ **测试覆盖详情**
  - HTML DOM模块：26个测试
  - HTML Parser模块：25个测试（包括边界情况和插入模式测试）
  - HTML Tokenizer模块：30个测试（包括边界情况和错误处理测试）
  - CSS模块：52个测试
  - Utils模块：27个测试
  - Layout模块：60+个测试
    - 盒模型测试：10个测试用例
    - 布局上下文测试：10个测试用例
    - 块级布局测试：多个测试用例
    - 行内布局测试：多个测试用例
    - 定位布局测试：8个测试用例
    - 浮动布局测试：8个测试用例
    - Flexbox布局测试：6个测试用例
    - 布局引擎测试：10个测试用例
  - 所有测试通过，0内存泄漏

### 历史更新（v0.1.0-alpha）

- ✅ 修复了所有内存泄漏问题（从405个降至0个）
- ✅ 修复了所有测试错误
- ✅ 添加了8个HTML解析测试用例
- ✅ 完善了内存管理机制
- ✅ 所有测试通过，0内存泄漏

---

**注意**: 这是一个正在积极开发中的项目，API可能会发生变化。

