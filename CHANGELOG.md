# 更新日志

## [未发布]

### 新增功能
- **gap简写属性支持两个值**：现在 `gap` 简写属性支持两个值（`gap: 10px 20px`），第一个值是 `row-gap`，第二个值是 `column-gap`。如果只有一个值，则同时用于 `row-gap` 和 `column-gap`。
- **gap属性边界测试**：添加了gap属性的边界测试用例，包括单个值、零值、无gap属性等情况，确保各种边界条件都能正确处理。
- **Position布局relative定位支持right和bottom**：现在relative定位支持使用`right`和`bottom`属性进行定位，当`left`/`top`未设置时会使用`right`/`bottom`计算偏移量。
- **Position布局absolute定位查找定位祖先**：absolute定位现在会正确查找最近的定位祖先（position != static）作为包含块，如果找不到则使用视口。
- **Float布局碰撞检测改进**：Float布局的碰撞检测现在考虑padding和border，使用`totalSize()`获取完整的盒模型尺寸。
- **Float布局换行功能**：当浮动元素在当前行放不下时，会自动换行到下一行，使用`clearFloats`找到合适的y位置。
- **Flexbox布局flex-direction反向**：`row-reverse`和`column-reverse`方向已实现，在`applyJustifyContent`中正确处理反向布局。

### 修复
- **内联样式解析支持多值属性**：修复了内联样式解析器无法处理多值属性（如 `grid-template-columns: 200px 200px`）的问题。现在多值属性会被正确解析为关键字值，Grid布局能够正确读取 `grid-template-columns` 和 `grid-template-rows` 属性。
- **Grid布局column-gap计算**：修复了Grid布局中 `column-gap` 计算错误的问题。现在Grid布局能够正确应用 `row-gap` 和 `column-gap` 值，item位置计算准确。

### 改进
- **内存泄漏修复**：修复了CSS层叠引擎中内联样式覆盖现有属性时的内存泄漏问题。现在当内联样式覆盖现有属性时，旧的key和value会被正确释放。
- **getPropertyLength修复**：修复了`getPropertyLength`函数对关键字值返回0而不是null的问题。现在当属性值是关键字类型（如多值属性）时，`getPropertyLength`会正确返回`null`，允许`getPropertyKeyword`正确读取关键字值。
- **Inline布局内存泄漏修复**：修复了Inline布局中`layoutInline`函数总是创建新的IFC而不清理已存在的formatting_context导致的内存泄漏问题。现在在创建新的IFC之前，会先检查并清理已存在的formatting_context。
- **LayoutBox.deinit文档改进**：在`LayoutBox.deinit`方法中添加了详细注释，说明`formatting_context`的清理由创建它的布局函数负责（如`layoutInline`）。由于循环依赖的限制，`box`模块无法直接导入`context`或`inline`模块来清理`formatting_context`，但`layoutInline`已经处理了IFC的清理，确保不会发生内存泄漏。
- **Position布局改进**：
  - `layoutRelative`函数现在接收`containing_block`参数，支持`right`和`bottom`属性的计算
  - `layoutAbsolute`函数已实现查找定位祖先的功能，更新了注释说明
  - 添加了3个测试用例验证relative定位的right/bottom功能和优先级
  - 添加了3个测试用例验证absolute定位的定位祖先查找功能
- **Float布局改进**：
  - `findFloatPosition`函数现在使用`totalSize()`考虑padding和border进行碰撞检测
  - `layoutFloat`函数实现了换行功能，当元素放不下时自动换行
  - 添加了测试用例验证碰撞检测和换行功能
- **Flexbox布局改进**：
  - `flex-direction: row-reverse`和`column-reverse`已在`applyJustifyContent`中实现
  - 更新了注释说明反向功能已实现

### 技术细节
- 修改了 `src/css/cascade.zig` 中的 `parseInlineStyle` 函数，添加了对多值属性的检查
- 如果值中包含空格（如 `"200px 200px"`），则将其作为关键字值存储
- 这样 `getPropertyKeyword` 就能正确读取多值属性，Grid布局能够正确解析 `grid-template-columns` 和 `grid-template-rows`
- 修改了 `src/layout/style_utils.zig` 中的 `getRowGap` 和 `getColumnGap` 函数，支持解析 `gap` 简写属性的两个值
- 修改了 `src/layout/position.zig`：
  - `layoutRelative`函数接收`containing_block`参数，实现`right`和`bottom`的计算逻辑
  - `layoutSticky`函数调用`layoutRelative`时传入`containing_block`参数
  - 更新了`layoutAbsolute`的注释，说明定位祖先查找功能已实现
- 修改了 `src/layout/float.zig`：
  - `layoutFloat`函数使用`totalSize()`计算初始位置和换行检查
  - `findFloatPosition`函数使用`totalSize()`进行碰撞检测
  - 实现了换行逻辑：当元素放不下时，使用`clearFloats`找到下一行的y位置
- 修改了 `src/layout/flexbox.zig`：
  - 更新了注释，说明`flex-direction`反向功能已在`applyJustifyContent`中实现

