# 测试说明

## 测试结构

项目使用Zig内置的测试框架，测试文件组织在 `tests/` 目录下，与 `src/` 目录结构对应。

```
tests/
├── html/              # HTML模块测试
│   ├── parser_test.zig
│   ├── tokenizer_test.zig
│   └── dom_test.zig
├── css/               # CSS模块测试
│   ├── parser_test.zig
│   ├── tokenizer_test.zig
│   ├── selector_test.zig
│   └── cascade_test.zig
├── utils/             # Utils模块测试
│   ├── string_test.zig
│   ├── math_test.zig
│   └── allocator_test.zig
└── test_helpers.zig   # 测试辅助函数
```

## 运行测试

### 运行所有测试

```bash
zig build test
```

这会运行所有测试模块，包括：
- HTML模块测试（parser, tokenizer, dom）
- CSS模块测试（parser, tokenizer, selector, cascade）
- Utils模块测试（string, math, allocator）
- 根测试文件（test.zig）

### 运行特定模块的测试

```bash
# 只运行HTML模块测试
zig build test:html

# 只运行CSS模块测试
zig build test:css

# 只运行Utils模块测试
zig build test:utils
```

## 根测试文件

项目根目录的 `test.zig` 文件作为所有测试的统一入口点，它导入所有子测试模块，确保所有测试都被编译和运行。

### 功能

- 统一导入所有测试模块
- 提供测试统计信息结构
- 确保测试模块的正确性

## 测试辅助函数

`tests/test_helpers.zig` 提供了通用的测试工具函数：

- `freeAllNodes()` - 释放所有DOM节点
- `freeNode()` - 释放单个节点
- `createTestDocument()` - 创建测试用的Document
- `cleanupTestDocument()` - 清理测试用的Document
- `createTestElement()` - 创建测试用的元素节点
- `createTestTextNode()` - 创建测试用的文本节点
- `TestConfig` - 测试配置结构
- `testPrint()` - 条件打印测试信息

## 测试规范

### 内存管理

所有测试必须使用 `GeneralPurposeAllocator` 进行内存泄漏检测：

```zig
test "example test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 测试代码...
}
```

### 资源清理

使用 `defer` 确保资源在测试结束时被正确释放：

```zig
test "example test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const doc = try createTestDocument(allocator);
    defer cleanupTestDocument(allocator, doc);
    
    // 测试代码...
}
```

### 测试命名

测试函数使用描述性的名称：

```zig
test "parse simple HTML" { ... }
test "tokenize identifier" { ... }
test "compute style for element" { ... }
```

## 测试覆盖率

目标：100%代码覆盖率

- 每个公开函数必须有测试
- 边界条件必须有测试
- 错误情况必须有测试
- 所有代码路径必须被覆盖

## 添加新测试

1. 在对应的 `tests/` 子目录中创建测试文件
2. 在 `test.zig` 中导入新测试模块
3. 在 `build.zig` 中添加测试模块配置
4. 运行 `zig build test` 验证测试通过

## 测试统计

运行测试后，会显示：
- 通过的测试数量
- 失败的测试数量
- 总测试数量
- 内存泄漏检测结果

