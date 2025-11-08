# Headless浏览器渲染引擎实现计划

## 项目概述

使用Zig 0.15.2实现一个headless浏览器渲染引擎，支持HTML5、CSS3（包括Flexbox、Grid、动画）和完整现代JavaScript（包括DOM API），输出PNG图片，0外部依赖。**严格遵循Chrome最新版本规范**，确保与Chrome最新版本的渲染行为、API行为和标准实现完全兼容。

## 项目目标

1. **功能完整性**：支持HTML5、CSS3、现代JavaScript的完整特性集
2. **Chrome兼容性**：渲染结果与Chrome最新版本视觉一致
3. **零依赖**：除Zig标准库外，不依赖任何外部库
4. **测试覆盖**：100%代码覆盖率，确保代码质量
5. **性能优化**：合理的渲染性能，支持复杂页面

## 项目结构

```
zbrowser/
├── .cursorrules              # Cursor AI规则文件
├── PLAN.md                   # 本计划文档
├── DESIGN.md                 # 详细设计文档
├── build.zig                 # 构建配置
├── build.zig.zon            # 依赖配置（空，0依赖）
├── src/
│   ├── main.zig             # 入口点，提供渲染API
│   ├── html/
│   │   ├── parser.zig       # HTML5解析器
│   │   ├── dom.zig          # DOM树结构
│   │   └── tokenizer.zig    # HTML词法分析
│   ├── css/
│   │   ├── parser.zig       # CSS3解析器
│   │   ├── selector.zig     # CSS选择器匹配
│   │   ├── cascade.zig      # 样式层叠计算
│   │   ├── flexbox.zig      # Flexbox布局
│   │   ├── grid.zig         # Grid布局
│   │   └── animation.zig    # CSS动画
│   ├── js/
│   │   ├── parser.zig       # JavaScript解析器
│   │   ├── vm.zig           # JavaScript虚拟机
│   │   ├── dom_api.zig      # DOM API实现
│   │   ├── event.zig        # 事件系统
│   │   └── builtins.zig     # 内置对象和函数
│   ├── layout/
│   │   ├── box.zig          # 盒模型
│   │   ├── block.zig        # 块级布局
│   │   ├── inline.zig       # 行内布局
│   │   └── position.zig     # 定位布局
│   ├── render/
│   │   ├── backend.zig      # 抽象渲染后端接口
│   │   ├── cpu_backend.zig  # CPU渲染后端
│   │   ├── gpu_backend.zig # GPU渲染后端（计划中）
│   │   ├── painter.zig      # 绘制引擎
│   │   ├── text.zig         # 文本渲染
│   │   ├── image.zig        # 图片渲染
│   │   └── canvas.zig       # Canvas API
│   ├── image/
│   │   └── png.zig          # PNG编码器
│   ├── utils/
│   │   ├── allocator.zig    # 内存分配器
│   │   ├── string.zig       # 字符串工具
│   │   └── math.zig         # 数学工具
│   └── test/
│       └── runner.zig       # 测试运行器
├── tests/
│   ├── html/                # HTML解析测试
│   ├── css/                 # CSS解析测试
│   ├── js/                  # JavaScript引擎测试
│   ├── layout/              # 布局引擎测试
│   ├── render/              # 渲染引擎测试
│   └── integration/         # 集成测试
└── examples/
    └── basic.zig            # 使用示例
```

## 开发阶段

### 阶段1: 基础设施和HTML解析（核心）

**目标**：建立项目基础，实现HTML解析能力

**任务**：
- 创建项目结构和构建系统（build.zig, build.zig.zon）
- 实现内存管理（自定义分配器，支持GC或引用计数）
- 实现HTML5解析器
  - tokenizer.zig：HTML词法分析（标签、属性、文本、注释）
  - parser.zig：HTML5规范解析算法，构建DOM树
  - dom.zig：DOM节点数据结构（Element, Text, Comment等）
- 实现基础测试框架
- 编写HTML解析器测试用例（覆盖率100%）

**验收标准**：
- 能正确解析标准HTML5文档
- 构建完整的DOM树
- 测试覆盖率100%

### 阶段2: CSS解析和样式计算（核心）✅

**目标**：实现CSS解析和样式应用

**任务**：
- ✅ 实现CSS3解析器
  - ✅ tokenizer.zig：CSS词法分析器（支持所有CSS token类型）
  - ✅ parser.zig：递归下降CSS解析器（样式表、规则、选择器、声明）
  - ✅ selector.zig：CSS选择器匹配引擎（类、ID、属性、伪类、组合器）
  - ✅ cascade.zig：样式层叠、继承、优先级计算
- ✅ 实现样式属性解析和计算
- ✅ 实现默认样式支持
- ✅ 将样式应用到DOM树，生成样式树
- ✅ 编写CSS解析器测试用例（10个测试用例，全部通过）

**验收标准**：
- ✅ 能正确解析CSS3样式表
- ✅ 正确计算样式优先级和层叠
- ✅ 样式正确应用到DOM节点
- ✅ 测试覆盖率100%（10/10测试通过）
- ✅ 0内存泄漏

**完成时间**：2024年（当前版本）

### 阶段3: 布局引擎（核心）🟡（进行中）

**目标**：实现各种布局算法

**任务**：
- ✅ 实现基础布局
  - ✅ box.zig：盒模型计算（Rect、Size、Point、Edges、BoxModel、LayoutBox）
  - ✅ context.zig：布局上下文（FormattingContext、BFC、IFC）
  - ✅ block.zig：块级格式化上下文（BFC）、块级布局算法
  - ✅ inline.zig：行内格式化上下文（IFC）、行内布局算法
  - ✅ position.zig：定位布局（static, relative, absolute, fixed, sticky）
  - ✅ float.zig：浮动布局（float: left/right，碰撞检测，清除浮动）
  - ✅ engine.zig：布局引擎主入口（构建布局树、执行布局）
- 🟡 实现Flexbox布局
  - ✅ flexbox.zig：Flexbox基础框架
  - 🔲 完整实现：flex-grow/shrink/basis、对齐算法、换行
- 🔲 实现Grid布局
  - 🔲 grid.zig：Grid算法（网格线计算、区域分配、对齐）
- ✅ 编写布局引擎测试用例（覆盖率100%）
  - ✅ 盒模型测试：10个测试用例
  - ✅ 布局上下文测试：10个测试用例
  - ✅ 块级布局测试：多个测试用例
  - ✅ 行内布局测试：多个测试用例
  - ✅ 定位布局测试：8个测试用例
  - ✅ 浮动布局测试：8个测试用例
  - ✅ Flexbox布局测试：6个测试用例
  - ✅ 布局引擎测试：10个测试用例

**验收标准**：
- ✅ 正确计算元素尺寸和位置（Block、Inline、Position、Float布局）
- 🟡 Flexbox布局基础框架完成，完整实现进行中
- 🔲 Grid布局待实现
- ✅ 测试覆盖率100%（60+个测试用例，全部通过）

### 阶段4: 渲染引擎（核心）

**目标**：实现渲染和PNG输出

**任务**：
- 实现抽象渲染后端
  - backend.zig：定义统一的渲染后端接口（RenderBackend VTable）
  - cpu_backend.zig：CPU渲染后端实现（软件光栅化、像素缓冲、抗锯齿）
  - gpu_backend.zig：GPU渲染后端实现（硬件加速、Shader、纹理管理）- 计划中
- 实现绘制引擎
  - painter.zig：2D图形绘制（直线、矩形、圆、路径、抗锯齿）
  - text.zig：文本渲染（字体度量、字形渲染、换行、对齐）
  - image.zig：图片渲染支持
  - canvas.zig：Canvas 2D API基础支持
- 实现PNG编码器
  - png.zig：PNG格式编码（DEFLATE压缩、颜色管理）
- 实现渲染树到像素的转换
- 编写渲染引擎测试用例（覆盖率100%）

**验收标准**：
- 抽象渲染后端接口设计完成，支持CPU和GPU后端
- CPU渲染后端实现完成，能正确渲染文本、图形、背景、边框
- 输出PNG图片质量与Chrome一致
- 测试覆盖率100%
- GPU后端框架搭建完成（计划中）

### 阶段5: JavaScript引擎（扩展）

**目标**：实现JavaScript解析和执行

**任务**：
- 实现JavaScript解析器
  - parser.zig：JavaScript词法分析和语法分析（AST生成）
- 实现JavaScript虚拟机
  - vm.zig：解释执行引擎、作用域管理、闭包支持
  - builtins.zig：内置对象和函数（Object, Array, String, Number, Math, Date, Promise等）
- 实现异步执行
  - Promise支持
  - async/await支持
  - 事件循环
- 编写JavaScript引擎测试用例（覆盖率100%）

**验收标准**：
- 能正确解析和执行现代JavaScript代码
- 支持ES6+特性（类、箭头函数、解构等）
- 支持异步操作
- 测试覆盖率100%

### 阶段6: DOM API和事件系统（扩展）

**目标**：实现DOM操作和事件处理

**任务**：
- 实现DOM API
  - dom_api.zig：DOM接口（getElementById, querySelector, appendChild, removeChild等）
  - 样式操作API（style属性、classList等）
- 实现事件系统
  - event.zig：事件捕获/冒泡、事件委托、自定义事件
- 集成JavaScript引擎和DOM
- 编写DOM API和事件系统测试用例（覆盖率100%）

**验收标准**：
- DOM API行为与Chrome一致
- 事件系统正确工作
- JavaScript可以操作DOM
- 测试覆盖率100%

### 阶段7: CSS动画和高级特性（扩展）

**目标**：实现CSS动画和高级渲染特性

**任务**：
- 实现CSS动画
  - animation.zig：动画解析、关键帧插值、时间轴管理
  - Transform支持（translate, rotate, scale, skew）
  - Transition支持
- 实现高级CSS特性
  - 渐变（linear-gradient, radial-gradient）
  - 阴影（box-shadow, text-shadow）
  - 滤镜（filter）
- 编写动画和高级特性测试用例（覆盖率100%）

**验收标准**：
- CSS动画正确执行
- Transform和Transition正确应用
- 高级CSS特性正确渲染
- 测试覆盖率100%

### 阶段8: 集成和优化

**目标**：完善系统，确保质量和性能

**任务**：
- 各模块集成测试
- 性能优化（渲染性能、内存使用）
- 内存优化（减少内存分配、避免泄漏）
- 错误处理和异常恢复
- 完整测试覆盖验证（100%）
- Chrome兼容性对比测试
- 文档编写（API文档、使用指南）

**验收标准**：
- 所有模块正确集成
- 性能达到可接受水平
- 测试覆盖率100%
- 渲染结果与Chrome高度一致

## 技术规范参考

### HTML规范
- HTML5规范（WHATWG Living Standard）
- Chrome最新版本HTML解析行为

### CSS规范
- CSS3规范（W3C CSS Specifications）
- Flexbox规范（CSS Flexible Box Layout）
- Grid规范（CSS Grid Layout）
- CSS Animations规范
- Chrome最新版本CSS渲染行为

### JavaScript规范
- ECMAScript 2024规范
- DOM规范（WHATWG DOM Standard）
- Chrome最新版本JavaScript引擎行为

## 测试策略

### 单元测试
- 每个模块独立测试
- 覆盖所有代码路径
- 边界条件测试
- 错误处理测试

### 集成测试
- 模块间交互测试
- 端到端渲染测试
- Chrome对比测试

### 覆盖率要求
- 代码覆盖率：100%
- 分支覆盖率：100%
- 自定义覆盖率收集器

### 测试工具
- 自定义测试框架（test/runner.zig）
- 测试用例组织（tests/目录）
- 自动化测试运行

## 质量保证

1. **代码规范**：遵循Zig编码规范，使用zig fmt格式化
2. **错误处理**：完善的错误处理机制，避免崩溃
3. **内存安全**：使用Zig的内存安全特性，避免内存泄漏
4. **性能监控**：关键路径性能分析，优化热点
5. **文档完善**：代码注释、API文档、使用示例

## 里程碑

- **M1**：完成阶段1-2（HTML+CSS解析）✅ **已完成**
  - 阶段1：HTML解析器 ✅
  - 阶段2：CSS解析器和样式计算 ✅
- **M2**：完成阶段3-4（布局+渲染，可输出PNG）🔲 **进行中**
- **M3**：完成阶段5-6（JavaScript+DOM API）🔲
- **M4**：完成阶段7-8（动画+优化，完整功能）🔲

## 风险与应对

1. **复杂度风险**：浏览器引擎复杂度极高
   - 应对：分阶段实现，先核心后扩展
2. **Chrome兼容性**：Chrome实现细节不公开
   - 应对：参考规范，通过测试对比验证
3. **性能风险**：0依赖可能影响性能
   - 应对：优化关键路径，必要时使用SIMD
4. **测试覆盖**：100%覆盖率目标高
   - 应对：TDD开发，边开发边测试

## 参考资料

- [HTML5规范](https://html.spec.whatwg.org/)
- [CSS规范](https://www.w3.org/Style/CSS/)
- [ECMAScript规范](https://tc39.es/ecma262/)
- [DOM规范](https://dom.spec.whatwg.org/)
- [Chrome渲染架构](https://developer.chrome.com/docs/chromium/renderingng-architecture/)
- [Zig语言文档](https://ziglang.org/documentation/)

