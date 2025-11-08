# CSS LR 解析器实现说明

## 已完成的工作

### 1. 基础架构
- ✅ 创建了 `src/css/lr_parser.zig` 文件
- ✅ 定义了符号类型（终结符和非终结符）
- ✅ 定义了语法规则结构
- ✅ 定义了归约动作函数框架

### 2. 语法规则定义
已定义 20 条基本语法规则，包括：
- 样式表规则
- 选择器规则（包括后代选择器、组合器等）
- 声明规则
- 值规则

### 3. 数据结构
- `Symbol`: 符号结构，包含符号类型和数据
- `Production`: 语法规则结构
- `ParseAction`: 解析动作联合类型

## 待完成的工作

### 1. Comptime 解析表生成
需要实现 `comptime` 函数来生成 LR 解析表：
- ACTION 表：状态 × 终结符 → 动作
- GOTO 表：状态 × 非终结符 → 状态

### 2. LR 解析算法实现
实现完整的 LR 解析主循环：
1. 初始化状态栈和符号栈
2. 主循环：
   - 读取当前 token
   - 查找 ACTION[state][token]
   - 执行动作（shift/reduce/accept/error）
3. Shift 操作：压入 token 和新状态
4. Reduce 操作：根据规则归约，弹出符号和状态
5. Accept 操作：解析成功
6. Error 操作：报告错误

### 3. 归约动作实现
实现所有归约动作函数，将符号栈中的符号组合成解析结果：
- `reduceStylesheet`
- `reduceRule`
- `reduceSelectorList`
- `reduceSelector`
- `reduceSelectorSequence`
- `reduceSimpleSelector`
- `reduceCombinator`
- `reduceDeclarationList`
- `reduceDeclaration`
- `reduceProperty`
- `reduceValue`

### 4. 测试和验证
- 编写测试用例
- 验证解析正确性
- 性能对比测试

## 使用方式

```zig
const lr_parser = @import("css/lr_parser");

var parser = lr_parser.LRParser.init(css_input, allocator);
defer parser.deinit();
const stylesheet = try parser.parse();
```

## 优势

1. **性能**：解析表在编译时生成，运行时只需查表，性能优于递归下降
2. **可维护性**：语法规则集中定义，易于修改和扩展
3. **正确性**：LR 解析器保证解析的正确性和一致性
4. **可扩展性**：添加新语法规则只需修改语法定义

## 下一步

1. 实现 comptime LR 表生成器
2. 实现完整的 LR 解析算法
3. 实现所有归约动作函数
4. 迁移现有解析逻辑到新解析器
5. 保持 API 兼容性
6. 添加测试确保功能正确


