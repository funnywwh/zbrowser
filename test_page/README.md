# 元素Box对比测试框架

这个测试框架用于对比ZBrowser和Puppeteer（Chrome）渲染的元素的box信息，确保两者完全一致。

## 功能

- 从`test_page.html`中提取body的直接子元素
- 为每个元素创建独立的HTML文件进行测试
- 使用ZBrowser和Puppeteer分别渲染
- 对比content box和border box（误差范围1px）
- 如果验证不合格，暂停测试等待修复，修复后重新测试当前元素
- 生成详细的对比报告、PNG图片和修复日志

## 文件结构

```
test_page/
├── build.zig              # 独立的构建配置
├── extract_and_test.zig   # 主测试程序
├── puppeteer_runner.js    # Puppeteer渲染脚本
├── compare_boxes.js       # Box对比脚本（可选）
├── test_page.html         # 源HTML文件
├── test_page_next.html    # HTML模板
└── results/               # 测试结果目录
    └── element_N/         # 每个元素的测试结果
        ├── element.html   # 元素的HTML文件
        ├── zbrowser.png   # ZBrowser渲染结果
        ├── puppeteer.png # Puppeteer渲染结果
        ├── zbrowser_box.json    # ZBrowser的box信息
        ├── puppeteer_box.json   # Puppeteer的box信息
        ├── comparison.json      # 对比结果
        └── fix_log.txt         # 修复日志（如果失败）
```

## 依赖

- Zig 0.15.2
- Node.js
- Puppeteer (`npm install puppeteer`)

## 使用方法

1. **安装依赖**：
   ```bash
   npm install puppeteer
   ```

2. **初始化环境**（在项目根目录）：
   ```bash
   source env.sh  # Linux/WSL
   # 或
   . .\env.ps1    # Windows PowerShell
   ```

3. **运行测试**（在test_page目录下）：
   ```bash
   cd test_page
   zig build run
   ```

## 工作流程

1. 程序解析`test_page.html`，提取body的直接子元素
2. 对每个元素：
   - 创建独立的HTML文件
   - 使用ZBrowser渲染并提取box信息
   - 使用Puppeteer渲染并提取box信息
   - 对比box信息（content box和border box）
   - **如果验证不合格（差异>1px）**：
     * 生成修复日志
     * **暂停测试，等待用户修复ZBrowser代码**
     * **提示用户修复后按回车继续**
     * **重新测试当前元素**
   - **如果通过（差异<=1px）**：
     * 保存所有结果
     * **继续下一个元素**
3. 所有元素测试完成后，程序结束

## Box信息格式

### Content Box
元素的内容区域，不包括padding和border。

### Border Box
元素的边框区域，包括content + padding + border。

## 误差范围

- 允许的误差：1px
- 同时检查content box和border box
- 所有差异都会记录在对比报告中

## 修复日志格式

修复日志包含：
- 元素信息（tag、class、id）
- Content box和border box的详细对比
- 可能的问题原因
- 修复建议（标记需要检查的代码位置）

## 注意事项

- 确保视口大小一致（980x8000）
- 确保CSS样式一致（从原HTML提取）
- 每个元素必须通过验证才能继续下一个
- 修复后必须重新测试当前元素，确保修复有效

