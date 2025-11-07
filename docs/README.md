# ZBrowser - Headless浏览器渲染引擎

一个使用Zig 0.15.2从零开始实现的headless浏览器渲染引擎，支持HTML5、CSS3和现代JavaScript，输出PNG图片，0外部依赖。

## 项目概述

ZBrowser是一个完全用Zig语言实现的headless浏览器渲染引擎，严格遵循Chrome最新版本规范，确保渲染结果与Chrome浏览器视觉一致。项目采用模块化设计，从HTML解析到PNG输出，所有功能均从零实现，不依赖任何外部库。

## 特性

### 已实现
- ✅ HTML5解析器（词法分析、语法分析、DOM树构建）
- ✅ DOM数据结构（Node、Element、Document）
- ✅ 基础工具模块（内存管理、字符串处理、数学工具）

### 计划中
- 🔲 CSS3解析器和样式计算
- 🔲 布局引擎（Block、Inline、Flexbox、Grid）
- 🔲 渲染引擎（文本、图形、图片）
- 🔲 PNG编码器
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
│   ├── css/                  # CSS解析模块（待实现）
│   ├── js/                   # JavaScript引擎（待实现）
│   ├── layout/               # 布局引擎（待实现）
│   ├── render/               # 渲染引擎（待实现）
│   ├── image/                # 图像处理（待实现）
│   ├── utils/                # 工具模块
│   │   ├── allocator.zig    # 内存分配器
│   │   ├── string.zig       # 字符串工具
│   │   └── math.zig         # 数学工具
│   └── test/                # 测试运行器
├── tests/                    # 测试用例
│   ├── html/                # HTML解析测试
│   ├── css/                 # CSS解析测试（待实现）
│   ├── js/                  # JavaScript测试（待实现）
│   └── integration/         # 集成测试（待实现）
├── build.zig                 # 构建配置
├── PLAN.md                   # 开发计划
├── DESIGN.md                 # 详细设计文档
└── README.md                 # 本文件
```

## 快速开始

### 环境要求

- Zig 0.15.2（需要单独下载，见下方说明）
- Linux系统（其他平台需要相应调整）

**注意**: Zig编译器文件较大（>100MB），未包含在git仓库中。请从[Zig官网](https://ziglang.org/download/)下载Zig 0.15.2，解压到项目根目录，或使用系统包管理器安装。

### 构建项目

```bash
# 设置环境变量（使用项目自带的Zig）
source env.sh

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

2. **阶段2: CSS解析和样式计算** 🔲
   - CSS3解析器
   - 选择器匹配
   - 样式层叠计算

3. **阶段3: 布局引擎** 🔲
   - 盒模型
   - Block/Inline布局
   - Flexbox和Grid布局

4. **阶段4: 渲染引擎** 🔲
   - 绘制引擎
   - 文本渲染
   - PNG编码器

5. **阶段5-8: JavaScript引擎、DOM API、动画等** 🔲
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

### CSS解析（计划中）

- **选择器匹配**: 支持类、ID、属性、伪类、组合器
- **样式层叠**: 实现CSS优先级和继承规则
- **样式计算**: 计算每个元素的最终样式

### 布局引擎（计划中）

- **盒模型**: 支持content-box和border-box
- **布局算法**: Block格式化上下文、Flexbox、Grid
- **定位**: 支持static、relative、absolute、fixed、sticky

### 渲染引擎（计划中）

- **绘制**: 2D图形绘制（直线、矩形、圆、路径）
- **文本**: 字体度量、字形渲染、换行、对齐
- **图像**: PNG编码、抗锯齿处理

详细设计请参考 [DESIGN.md](DESIGN.md)

## 测试

项目目标实现100%代码覆盖率。测试包括：

- **单元测试**: 每个模块独立测试
- **集成测试**: 模块间交互测试
- **兼容性测试**: 与Chrome渲染结果对比

### 测试覆盖

当前测试覆盖以下场景：

#### HTML解析测试（8个测试用例）

1. **简单HTML解析** - 验证基本的HTML结构解析
2. **带属性的HTML** - 验证元素属性的解析和访问
3. **文本内容** - 验证文本节点的解析
4. **注释** - 验证HTML注释的解析
5. **自闭合标签** - 验证br、img等自闭合标签
6. **复杂HTML（多属性）** - 验证包含多种属性的复杂HTML结构
   - 支持lang、charset、class、id、data-*等属性
   - 支持嵌套结构（header、nav、main、article、section、footer）
   - 支持表单元素、链接、图片等
7. **特殊属性值** - 验证特殊属性值的解析
   - JSON数据属性
   - 复杂URL（包含查询参数）
   - 内联CSS样式
   - HTML实体
   - 布尔属性
8. **包含JavaScript代码的HTML** - 验证script标签和JavaScript代码的解析
   - 内联脚本（type="text/javascript"）
   - 内联脚本（无type属性）
   - 外部脚本（src属性）
   - ES6模块脚本（type="module"）

#### 测试结果

- ✅ 所有测试通过：`1/1 passed` (runner测试) + `8/8 passed` (parser_test)
- ✅ 0个内存泄漏
- ✅ 代码编译无错误

运行测试：
```bash
zig build test
```

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

**当前版本**: 0.1.0-alpha  
**开发阶段**: 阶段1完成，阶段2进行中

### 最新更新

- ✅ 修复了所有内存泄漏问题（从405个降至0个）
- ✅ 修复了所有测试错误
- ✅ 添加了8个HTML解析测试用例，包括：
  - 简单HTML、带属性的HTML、文本内容、注释
  - 自闭合标签、复杂HTML结构
  - 特殊属性值（JSON、URL、CSS、HTML实体）
  - 包含JavaScript代码的HTML（内联脚本、外部脚本、ES6模块）
- ✅ 完善了内存管理机制
- ✅ 所有测试通过，0内存泄漏

---

**注意**: 这是一个正在积极开发中的项目，API可能会发生变化。

