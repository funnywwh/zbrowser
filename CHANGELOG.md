# 更新日志

## [未发布]

### 新增功能
- **gap简写属性支持两个值**：现在 `gap` 简写属性支持两个值（`gap: 10px 20px`），第一个值是 `row-gap`，第二个值是 `column-gap`。如果只有一个值，则同时用于 `row-gap` 和 `column-gap`。

### 修复
- **内联样式解析支持多值属性**：修复了内联样式解析器无法处理多值属性（如 `grid-template-columns: 200px 200px`）的问题。现在多值属性会被正确解析为关键字值，Grid布局能够正确读取 `grid-template-columns` 和 `grid-template-rows` 属性。
- **Grid布局column-gap计算**：修复了Grid布局中 `column-gap` 计算错误的问题。现在Grid布局能够正确应用 `row-gap` 和 `column-gap` 值，item位置计算准确。

### 改进
- **内存泄漏修复**：修复了CSS层叠引擎中内联样式覆盖现有属性时的内存泄漏问题。现在当内联样式覆盖现有属性时，旧的key和value会被正确释放。

### 技术细节
- 修改了 `src/css/cascade.zig` 中的 `parseInlineStyle` 函数，添加了对多值属性的检查
- 如果值中包含空格（如 `"200px 200px"`），则将其作为关键字值存储
- 这样 `getPropertyKeyword` 就能正确读取多值属性，Grid布局能够正确解析 `grid-template-columns` 和 `grid-template-rows`
- 修改了 `src/layout/style_utils.zig` 中的 `getRowGap` 和 `getColumnGap` 函数，支持解析 `gap` 简写属性的两个值

